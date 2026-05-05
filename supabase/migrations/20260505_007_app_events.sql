-- =============================================================================
-- Pixora App Events — generic event log for engagement analytics
-- Migration: 20260505_007_app_events
--
-- Complements wallpaper_events (which is wallpaper-specific). This table
-- captures everything else: tab navigation, AURA listening time, tutorial
-- progress, subscription funnel, welcome gift redemption, event-section
-- engagement, AI generation taps, etc.
--
-- Schema is intentionally generic: a single (event_name, props jsonb) pair
-- so we can add new event kinds without migrations. The downside is loose
-- typing — discipline lives in the AnalyticsService client (Flutter).
-- =============================================================================

create table if not exists public.app_events (
  id           bigserial primary key,
  device_id    text not null check (length(device_id) between 1 and 80),
  user_id      uuid,
  session_id   text,                              -- groups events from one app run
  event_name   text not null check (length(event_name) between 1 and 60),
  props        jsonb not null default '{}'::jsonb,
  app_version  text,
  ts           timestamptz not null default now(),
  ts_minute    bigint                             -- populated by trigger
);

comment on table public.app_events is
  'Generic engagement events. event_name is the catalog key, props is free-form JSON.';

create or replace function public.ae_set_ts_minute()
returns trigger language plpgsql as $$
begin
  new.ts_minute := (extract(epoch from new.ts) / 60)::bigint;
  return new;
end$$;

drop trigger if exists trg_ae_ts_minute on public.app_events;
create trigger trg_ae_ts_minute
  before insert or update of ts on public.app_events
  for each row execute function public.ae_set_ts_minute();

create index if not exists idx_ae_event_ts        on public.app_events (event_name, ts desc);
create index if not exists idx_ae_user_ts         on public.app_events (user_id, ts desc) where user_id is not null;
create index if not exists idx_ae_device_ts       on public.app_events (device_id, ts desc);
create index if not exists idx_ae_session         on public.app_events (session_id) where session_id is not null;

-- Partial GIN index for common props queries (section, track_id, event_id, etc.)
create index if not exists idx_ae_props_gin       on public.app_events using gin (props);

-- Anti-spam dedupe: same device+event+props fingerprint can't fire >1/minute
-- for hot events (tab_viewed). We don't enforce uniqueness for everything
-- because aura_play_tick must fire many times in a row.
create unique index if not exists idx_ae_dedupe_tab_viewed
  on public.app_events (device_id, ts_minute, (props->>'section'))
  where event_name = 'tab_viewed';

alter table public.app_events enable row level security;
-- No policies → service_role only.

-- ───────── RPC: log a single event (anon-callable) ─────────
create or replace function public.app_log_event(
  p_event_name  text,
  p_device_id   text,
  p_props       jsonb default '{}'::jsonb,
  p_session_id  text default null,
  p_app_version text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid := auth.uid();
begin
  if p_event_name is null or length(p_event_name) = 0 then
    raise exception 'event_name required';
  end if;
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;

  begin
    insert into public.app_events
      (device_id, user_id, session_id, event_name, props, app_version)
      values (p_device_id, v_user_id, p_session_id, p_event_name,
              coalesce(p_props, '{}'::jsonb), p_app_version);
    return true;
  exception
    when unique_violation then
      return false;  -- silently dropped (dedupe)
  end;
end$$;

grant execute on function public.app_log_event(text,text,jsonb,text,text) to anon, authenticated;

-- ───────── Bulk RPC: log many events (batch flush from client) ─────────
create or replace function public.app_log_events_batch(
  p_events jsonb,         -- array of {name, props, ts}
  p_device_id   text,
  p_session_id  text default null,
  p_app_version text default null
) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid := auth.uid();
  v_inserted int := 0;
  v_event jsonb;
begin
  if jsonb_typeof(p_events) <> 'array' then
    raise exception 'p_events must be a jsonb array';
  end if;
  for v_event in select * from jsonb_array_elements(p_events) loop
    begin
      insert into public.app_events
        (device_id, user_id, session_id, event_name, props, app_version, ts)
        values (
          p_device_id, v_user_id, p_session_id,
          v_event->>'name',
          coalesce(v_event->'props', '{}'::jsonb),
          p_app_version,
          coalesce((v_event->>'ts')::timestamptz, now())
        );
      v_inserted := v_inserted + 1;
    exception
      when unique_violation then
        null;  -- skip dedupe collisions silently
      when others then
        null;  -- skip malformed rows; don't kill the batch
    end;
  end loop;
  return v_inserted;
end$$;

grant execute on function public.app_log_events_batch(jsonb,text,text,text) to anon, authenticated;

-- ───────── Admin views (service_role only) ─────────

-- Tab traffic — last 30 days
create or replace view public.admin_tab_views_30d as
select
  coalesce(props->>'section', 'unknown') as section,
  count(*) as views,
  count(distinct device_id) as unique_devices,
  count(distinct user_id) filter (where user_id is not null) as unique_users,
  max(ts) as last_seen
from public.app_events
where event_name = 'tab_viewed'
  and ts > now() - interval '30 days'
group by 1
order by views desc;

-- Subscription funnel — last 30 days
create or replace view public.admin_pitch_funnel_30d as
with raw as (
  select event_name, device_id
  from public.app_events
  where event_name in ('pitch_shown','pitch_cta_tap','pitch_paid')
    and ts > now() - interval '30 days'
)
select
  count(distinct device_id) filter (where event_name='pitch_shown')   as devices_saw_pitch,
  count(distinct device_id) filter (where event_name='pitch_cta_tap') as devices_tapped_subscribe,
  count(distinct device_id) filter (where event_name='pitch_paid')    as devices_paid,
  case when count(distinct device_id) filter (where event_name='pitch_shown') > 0
    then round(100.0 * count(distinct device_id) filter (where event_name='pitch_paid') /
               count(distinct device_id) filter (where event_name='pitch_shown'), 2)
    else 0 end as conversion_pct
from raw;

-- AURA top tracks by listening minutes — last 30 days
-- Each 'aura_play_tick' is 30 seconds of listening.
create or replace view public.admin_aura_top_tracks_30d as
select
  coalesce(props->>'track_id', 'unknown') as track_id,
  count(*) * 0.5                          as approx_minutes,  -- 30s ticks
  count(distinct device_id)               as unique_listeners,
  max(ts)                                 as last_played
from public.app_events
where event_name = 'aura_play_tick'
  and ts > now() - interval '30 days'
group by 1
order by approx_minutes desc
limit 50;

-- Event-section engagement — which season events get followed
create or replace view public.admin_event_followers_30d as
select
  coalesce(props->>'event_id', 'unknown') as event_id,
  count(*) filter (where event_name='event_opened')   as opens,
  count(*) filter (where event_name='event_followed') as follows,
  count(distinct device_id)               as unique_devices,
  max(ts) as last_activity
from public.app_events
where event_name in ('event_opened','event_followed')
  and ts > now() - interval '30 days'
group by 1
order by follows desc nulls last, opens desc;

-- Tutorial completion rate — last 30 days
create or replace view public.admin_tutorial_completion_30d as
with cohorts as (
  select device_id,
    bool_or(event_name='tutorial_started')   as started,
    bool_or(event_name='tutorial_finished')  as finished,
    bool_or(event_name='welcome_gift_redeemed') as redeemed_gift
  from public.app_events
  where event_name in ('tutorial_started','tutorial_finished','welcome_gift_redeemed')
    and ts > now() - interval '30 days'
  group by 1
)
select
  count(*)                                              as devices_seen_tutorial,
  count(*) filter (where finished)                      as completions,
  count(*) filter (where redeemed_gift)                 as gift_redemptions,
  case when count(*) filter (where started) > 0
    then round(100.0 * count(*) filter (where finished) / count(*) filter (where started), 2)
    else 0 end                                          as completion_pct
from cohorts;

-- Top events by raw count — last 24h (for at-a-glance dashboard panel)
create or replace view public.admin_app_event_counts_24h as
select
  event_name,
  count(*) as events,
  count(distinct device_id) as unique_devices
from public.app_events
where ts > now() - interval '24 hours'
group by 1
order by events desc;

-- Daily totals for sparkline
create or replace view public.admin_app_events_daily as
select
  date_trunc('day', ts)::date as day,
  count(*)                    as total,
  count(distinct device_id)   as unique_devices,
  count(distinct user_id) filter (where user_id is not null) as unique_users
from public.app_events
where ts > now() - interval '90 days'
group by 1
order by 1 desc;
