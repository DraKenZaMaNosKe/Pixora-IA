-- =========================================================================
-- Device presence + real usage-time tracking (F0 backend)
-- Design by Fable 5, reviewed by Opus. 2026-07-11.
--
-- Model: monotonic-clock delta credits (client measures time with
-- SystemClock.elapsedRealtime → only advances while the phone is ON), reported
-- as idempotent credits. Server accumulates + anti-cheat clamp. Phone off /
-- uninstalled → no credits → the sum freezes on its own.
--
-- RLS ON + zero policies + SECURITY DEFINER RPC = same pattern as app_events
-- (writes only through usage_report). Admin views: security_invoker=on +
-- revoked from anon/authenticated (only service_role reads them) — keeps the
-- 2026-07-08 advisor fixes intact.
-- =========================================================================

BEGIN;

-- 1. Live state — one row per device (drives the phone cards) -------------
create table if not exists public.device_presence (
  device_id             text primary key check (length(device_id) between 1 and 80),
  first_seen_at         timestamptz not null default now(),
  last_seen_at          timestamptz not null default now(),
  last_source           text,
  app_version           text,
  device_model          text,
  android_sdk           int,
  active_kind           text check (active_kind in
                          ('static','live_video','canvas_scene','daily',
                           'day_cycle','story','shader','external')),
  active_wallpaper_id   text,
  daily_enabled         boolean not null default false,
  wallpaper_set_at      timestamptz,
  active_ringtone_id    text,
  active_ringtone_title text,
  active_ringtone_type  smallint,
  ringtone_set_at       timestamptz,
  credit_watermark      timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists idx_dp_last_seen on public.device_presence (last_seen_at desc);

-- 2. Append-only delta credits — the time series ------------------------
create table if not exists public.usage_credits (
  id              bigserial primary key,
  device_id       text not null,
  content_kind    text not null check (content_kind in ('wallpaper','ringtone')),
  content_id      text not null,
  is_daily        boolean not null default false,
  seconds         int  not null check (seconds between 1 and 86400),
  segment_start   timestamptz,
  client_entry_id text not null,
  created_at      timestamptz not null default now(),
  unique (device_id, client_entry_id)
);
create index if not exists idx_uc_content on public.usage_credits (content_kind, content_id, created_at desc);
create index if not exists idx_uc_device  on public.usage_credits (device_id, created_at desc);
create index if not exists idx_uc_day     on public.usage_credits (created_at);

-- 3. Materialized accumulator — O(1) reads for cards/tops ----------------
create table if not exists public.usage_totals (
  device_id     text not null,
  content_kind  text not null,
  content_id    text not null,
  total_seconds bigint not null default 0,
  daily_seconds bigint not null default 0,
  first_used_at timestamptz not null default now(),
  last_used_at  timestamptz not null default now(),
  primary key (device_id, content_kind, content_id)
);
create index if not exists idx_ut_content on public.usage_totals (content_kind, content_id);

alter table public.device_presence enable row level security;
alter table public.usage_credits   enable row level security;
alter table public.usage_totals    enable row level security;

-- 4. usage_report — the single write door (SECURITY DEFINER) -------------
create or replace function public.usage_report(
  p_device_id text,
  p_state     jsonb default '{}'::jsonb,
  p_credits   jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_allowed  numeric;
  v_sum      numeric := 0;
  v_scale    numeric := 1.0;
  v_c        jsonb;
  v_inserted int := 0;
begin
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;

  insert into device_presence (device_id, last_seen_at, last_source, app_version,
    device_model, android_sdk, active_kind, active_wallpaper_id, daily_enabled,
    wallpaper_set_at, active_ringtone_id, active_ringtone_title,
    active_ringtone_type, ringtone_set_at, updated_at)
  values (p_device_id, now(), p_state->>'source', p_state->>'app_version',
    p_state->>'device_model', (p_state->>'android_sdk')::int,
    p_state->>'active_kind', p_state->>'active_wallpaper_id',
    coalesce((p_state->>'daily_enabled')::boolean, false),
    (p_state->>'wallpaper_set_at')::timestamptz,
    p_state->>'active_ringtone_id', p_state->>'active_ringtone_title',
    (p_state->>'active_ringtone_type')::smallint,
    (p_state->>'ringtone_set_at')::timestamptz, now())
  on conflict (device_id) do update set
    last_seen_at = now(),
    last_source  = coalesce(excluded.last_source, device_presence.last_source),
    app_version  = coalesce(excluded.app_version, device_presence.app_version),
    device_model = coalesce(excluded.device_model, device_presence.device_model),
    android_sdk  = coalesce(excluded.android_sdk, device_presence.android_sdk),
    active_kind         = case when p_state ? 'active_kind'
                            then excluded.active_kind else device_presence.active_kind end,
    active_wallpaper_id = case when p_state ? 'active_wallpaper_id'
                            then excluded.active_wallpaper_id else device_presence.active_wallpaper_id end,
    daily_enabled       = case when p_state ? 'daily_enabled'
                            then excluded.daily_enabled else device_presence.daily_enabled end,
    wallpaper_set_at    = coalesce(excluded.wallpaper_set_at, device_presence.wallpaper_set_at),
    active_ringtone_id    = case when p_state ? 'active_ringtone_id'
                            then excluded.active_ringtone_id else device_presence.active_ringtone_id end,
    active_ringtone_title = coalesce(excluded.active_ringtone_title, device_presence.active_ringtone_title),
    active_ringtone_type  = coalesce(excluded.active_ringtone_type, device_presence.active_ringtone_type),
    ringtone_set_at       = coalesce(excluded.ringtone_set_at, device_presence.ringtone_set_at),
    updated_at = now();

  -- Anti double-count clamp: credited seconds this call ≤ wall-clock since
  -- last credit (×1.1 + 120s slack). Two processes crediting the same → the
  -- second scales toward 0.
  select extract(epoch from (now() - credit_watermark)) * 1.10 + 120
    into v_allowed from device_presence where device_id = p_device_id;

  select coalesce(sum((c->>'seconds')::numeric), 0) into v_sum
    from jsonb_array_elements(p_credits) c;
  if v_sum > v_allowed and v_sum > 0 then
    v_scale := greatest(v_allowed, 0) / v_sum;
  end if;

  for v_c in select * from jsonb_array_elements(p_credits) loop
    begin
      insert into usage_credits (device_id, content_kind, content_id, is_daily,
        seconds, segment_start, client_entry_id)
      values (p_device_id, v_c->>'kind', v_c->>'content_id',
        coalesce((v_c->>'is_daily')::boolean, false),
        greatest(1, floor((v_c->>'seconds')::numeric * v_scale))::int,
        (v_c->>'segment_start')::timestamptz, v_c->>'entry_id');
      v_inserted := v_inserted + 1;
      insert into usage_totals (device_id, content_kind, content_id,
        total_seconds, daily_seconds, last_used_at)
      values (p_device_id, v_c->>'kind', v_c->>'content_id',
        floor((v_c->>'seconds')::numeric * v_scale)::bigint,
        case when coalesce((v_c->>'is_daily')::boolean,false)
          then floor((v_c->>'seconds')::numeric * v_scale)::bigint else 0 end, now())
      on conflict (device_id, content_kind, content_id) do update set
        total_seconds = usage_totals.total_seconds + excluded.total_seconds,
        daily_seconds = usage_totals.daily_seconds + excluded.daily_seconds,
        last_used_at  = now();
    exception when unique_violation then null;
             when others then null;
    end;
  end loop;

  if v_inserted > 0 then
    update device_presence set credit_watermark = now() where device_id = p_device_id;
  end if;

  return jsonb_build_object('inserted', v_inserted, 'scale', round(v_scale, 3));
end$$;

grant execute on function public.usage_report(text, jsonb, jsonb) to anon, authenticated;

-- 5. Admin views (service_role only) ------------------------------------
-- Live state joined with wallpaper metadata (real cols: name, preview_path).
create or replace view public.admin_live_devices
with (security_invoker = on) as
select dp.*,
  w.name as wallpaper_title,
  wp_storage_base() || w.preview_path as wallpaper_preview,
  coalesce((select sum(total_seconds) from usage_totals ut
    where ut.device_id = dp.device_id and ut.content_kind='wallpaper'),0) as wp_seconds_total,
  (select count(distinct wallpaper_id) from wallpaper_events we
    where we.device_id = dp.device_id and we.event_type='view') as wallpapers_seen,
  extract(epoch from (now() - dp.first_seen_at))::bigint as installed_seconds
from device_presence dp
left join wallpapers w on w.id = dp.active_wallpaper_id;

-- Bridge view: devices that only exist in app_events/wallpaper_events (no
-- heartbeat yet). Lets F0 show the panel before the AAB ships — flagged as
-- "estimated" by the endpoint.
create or replace view public.admin_presence_proxy
with (security_invoker = on) as
with ev as (
  select device_id, ts, app_version, null::text as wid, null::text as etype from app_events
  union all
  select device_id, ts, app_version, wallpaper_id, event_type from wallpaper_events
)
select
  device_id,
  max(ts) as last_seen_at,
  min(ts) as first_seen_at,
  (array_agg(app_version order by ts desc) filter (where app_version is not null))[1] as app_version,
  (array_agg(wid order by ts desc) filter (where etype = 'install'))[1] as est_wallpaper_id
from ev
where device_id is not null
group by device_id;

revoke all on public.admin_live_devices    from anon, authenticated;
revoke all on public.admin_presence_proxy  from anon, authenticated;

-- 6. admin_usage_stats — aggregate stats for the STATS page --------------
-- service_role calls this (server), NOT the app. Blocks fed by usage_* fill
-- in once F1 heartbeat ships; app_events/wallpaper_events blocks work now.
create or replace function public.admin_usage_stats(p_days int default 30)
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object(
    'dau_curve', coalesce((
      select jsonb_agg(row_to_json(t)) from (
        select date_trunc('day', ts)::date as day, count(distinct device_id) as devices
        from app_events where ts > now() - (p_days || ' days')::interval
        group by 1 order by 1) t), '[]'::jsonb),
    'top_viewed', coalesce((
      select jsonb_agg(row_to_json(t)) from (
        select wallpaper_id, count(*) as views, count(distinct device_id) as devices
        from wallpaper_events where event_type='view' and ts > now() - (p_days || ' days')::interval
        group by 1 order by 2 desc limit 15) t), '[]'::jsonb),
    'top_installed', coalesce((
      select jsonb_agg(row_to_json(t)) from (
        select wallpaper_id, count(*) as installs
        from wallpaper_events where event_type='install' and ts > now() - (p_days || ' days')::interval
        group by 1 order by 2 desc limit 15) t), '[]'::jsonb),
    'hours_per_day', coalesce((
      select jsonb_agg(row_to_json(t)) from (
        select date_trunc('day', created_at)::date as day, content_kind,
               round(sum(seconds)/3600.0, 2) as hours
        from usage_credits where created_at > now() - (p_days || ' days')::interval
        group by 1,2 order by 1) t), '[]'::jsonb),
    'top_wallpapers_time', coalesce((
      select jsonb_agg(row_to_json(t)) from (
        select content_id, round(sum(total_seconds)/3600.0,2) as hours,
               count(distinct device_id) as devices,
               round(avg(total_seconds)/3600.0,2) as avg_retention_hours
        from usage_totals where content_kind='wallpaper'
        group by 1 order by 2 desc limit 15) t), '[]'::jsonb),
    'kind_mix', coalesce((
      select jsonb_agg(row_to_json(t)) from (
        select active_kind, count(*) as devices
        from device_presence where active_kind is not null group by 1) t), '[]'::jsonb),
    'hour_dow_matrix', coalesce((
      select jsonb_agg(row_to_json(t)) from (
        select extract(dow from created_at)::int as dow,
               extract(hour from created_at)::int as hour,
               round(sum(seconds)/60.0,1) as minutes
        from usage_credits where created_at > now() - (p_days || ' days')::interval
        group by 1,2) t), '[]'::jsonb)
  );
$$;
-- admin RPC: NOT granted to anon (server uses service_role).
revoke all on function public.admin_usage_stats(int) from anon, authenticated;

COMMIT;
