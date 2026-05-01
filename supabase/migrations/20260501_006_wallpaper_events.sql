-- =============================================================================
-- Pixora Wallpaper Events — granular event log + admin views
-- Migration: 20260501_006_wallpaper_events
-- Tier 4. Applied to production 2026-05-01.
-- =============================================================================

create table if not exists public.wallpaper_events (
  id           bigserial primary key,
  device_id    text not null check (length(device_id) between 1 and 80),
  user_id      uuid,
  wallpaper_id text references public.wallpapers(id) on delete set null,
  event_type   text not null check (event_type in
                  ('view','preview','install','share','favorite','unfavorite','download')),
  ts           timestamptz not null default now(),
  ts_minute    bigint,  -- populated by trigger (anti-fraud dedupe key)
  app_version  text,
  metadata     jsonb not null default '{}'::jsonb
);

comment on table public.wallpaper_events is
  '1 row per view/install/share/etc. Source of truth for admin analytics.';

create or replace function public.we_set_ts_minute()
returns trigger language plpgsql as $$
begin
  new.ts_minute := (extract(epoch from new.ts) / 60)::bigint;
  return new;
end$$;

drop trigger if exists trg_we_ts_minute on public.wallpaper_events;
create trigger trg_we_ts_minute
  before insert or update of ts on public.wallpaper_events
  for each row execute function public.we_set_ts_minute();

create index if not exists idx_we_device_ts on public.wallpaper_events (device_id, ts desc);
create index if not exists idx_we_user_ts   on public.wallpaper_events (user_id, ts desc) where user_id is not null;
create index if not exists idx_we_wallpaper_event on public.wallpaper_events (wallpaper_id, event_type);
create index if not exists idx_we_ts on public.wallpaper_events (ts desc);
create index if not exists idx_we_event_type on public.wallpaper_events (event_type, ts desc);

-- Anti-fraud: same device cannot log same VIEW twice in same minute.
create unique index if not exists idx_we_dedupe_view
  on public.wallpaper_events (device_id, wallpaper_id, ts_minute)
  where event_type = 'view';

alter table public.wallpaper_events enable row level security;
-- No policies → service_role only.

-- ───────── RPC: log a single event (anon-callable) ─────────
create or replace function public.wp_log_event(
  p_wallpaper_id text,
  p_event_type   text,
  p_device_id    text,
  p_app_version  text default null,
  p_metadata     jsonb default '{}'::jsonb
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_inserted boolean := false;
  v_user_id  uuid := auth.uid();
begin
  if p_event_type not in ('view','preview','install','share','favorite','unfavorite','download') then
    raise exception 'Invalid event_type: %', p_event_type;
  end if;
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;

  begin
    insert into public.wallpaper_events
      (device_id, user_id, wallpaper_id, event_type, app_version, metadata)
      values (p_device_id, v_user_id, p_wallpaper_id, p_event_type, p_app_version, p_metadata);
    v_inserted := true;
  exception
    when unique_violation then
      v_inserted := false;
  end;

  if v_inserted then
    case p_event_type
      when 'view' then
        update public.wallpapers set view_count = view_count + 1, last_viewed_at = now()
          where id = p_wallpaper_id and published = true;
      when 'install' then
        update public.wallpapers set install_count = install_count + 1, last_installed_at = now()
          where id = p_wallpaper_id and published = true;
      when 'share' then
        update public.wallpapers set share_count = share_count + 1
          where id = p_wallpaper_id and published = true;
      when 'favorite' then
        update public.wallpapers set favorite_count = favorite_count + 1
          where id = p_wallpaper_id and published = true;
      when 'unfavorite' then
        update public.wallpapers set favorite_count = greatest(0, favorite_count - 1)
          where id = p_wallpaper_id and published = true;
      else null;
    end case;
  end if;
  return v_inserted;
end$$;

grant execute on function public.wp_log_event(text,text,text,text,jsonb) to anon, authenticated;

-- ───────── Admin views (service_role only) ─────────

create or replace view public.admin_user_stats as
select
  coalesce(user_id::text, device_id) as identity,
  case when user_id is not null then 'user' else 'device' end as identity_type,
  user_id, device_id,
  count(*)                                       as total_events,
  count(*) filter (where event_type='view')      as views,
  count(*) filter (where event_type='install')   as installs,
  count(*) filter (where event_type='share')     as shares,
  count(*) filter (where event_type='favorite')  as favorites,
  count(*) filter (where event_type='download')  as downloads,
  count(distinct wallpaper_id)                   as unique_wallpapers,
  min(ts) as first_seen,
  max(ts) as last_seen,
  count(distinct date_trunc('day', ts)) as active_days
from public.wallpaper_events
group by user_id, device_id;

create or replace view public.admin_wallpaper_breakdown as
select
  w.id, w.name, w.category, w.featured,
  coalesce(e.views, 0) as views,
  coalesce(e.installs, 0) as installs,
  coalesce(e.shares, 0) as shares,
  coalesce(e.unique_devices, 0) as unique_devices,
  case when coalesce(e.views, 0) > 0
    then round(coalesce(e.installs, 0) * 100.0 / e.views, 2)
    else 0 end as install_rate_pct,
  w.trending_score
from public.wallpapers w
left join lateral (
  select count(*) filter (where event_type='view') as views,
         count(*) filter (where event_type='install') as installs,
         count(*) filter (where event_type='share') as shares,
         count(distinct device_id) as unique_devices
  from public.wallpaper_events we where we.wallpaper_id = w.id
) e on true
where w.published = true
order by w.trending_score desc;

create or replace view public.admin_top_users_30d as
select * from public.admin_user_stats
where last_seen > now() - interval '30 days'
order by total_events desc
limit 200;

create or replace view public.admin_daily_activity as
select
  date_trunc('day', ts)::date as day,
  count(*) as total_events,
  count(distinct device_id) as unique_devices,
  count(distinct wallpaper_id) as unique_wallpapers_touched,
  count(*) filter (where event_type='view') as views,
  count(*) filter (where event_type='install') as installs,
  count(*) filter (where event_type='share') as shares
from public.wallpaper_events
group by 1
order by 1 desc;

-- Helper: lookup events for a single device (admin debug)
create or replace function public.admin_user_history(p_identity text, p_limit int default 100)
returns table(
  ts timestamptz, event_type text, wallpaper_id text, wallpaper_name text, app_version text
) language sql stable security definer set search_path = public as $$
  select e.ts, e.event_type, e.wallpaper_id, w.name, e.app_version
  from public.wallpaper_events e
  left join public.wallpapers w on w.id = e.wallpaper_id
  where e.device_id = p_identity or e.user_id::text = p_identity
  order by e.ts desc
  limit greatest(1, least(p_limit, 1000));
$$;
revoke all on function public.admin_user_history(text, int) from public, anon, authenticated;

-- Per-wallpaper installers (modal)
create or replace function public.admin_wallpaper_installers(p_wallpaper_id text, p_limit int default 50)
returns table(
  identity text, identity_type text,
  install_count bigint, first_install timestamptz, last_install timestamptz,
  view_count bigint, share_count bigint
) language sql stable security definer set search_path = public as $$
  select
    coalesce(user_id::text, device_id),
    case when user_id is not null then 'user' else 'device' end,
    count(*) filter (where event_type='install'),
    min(ts)  filter (where event_type='install'),
    max(ts)  filter (where event_type='install'),
    count(*) filter (where event_type='view'),
    count(*) filter (where event_type='share')
  from public.wallpaper_events
  where wallpaper_id = p_wallpaper_id
  group by user_id, device_id
  having count(*) filter (where event_type='install') > 0
  order by max(ts) filter (where event_type='install') desc nulls last
  limit greatest(1, least(p_limit, 500));
$$;

create or replace function public.admin_wallpaper_audience(p_wallpaper_id text, p_limit int default 100)
returns table(
  identity text, identity_type text,
  views bigint, installs bigint, shares bigint, favorites bigint,
  first_seen timestamptz, last_seen timestamptz
) language sql stable security definer set search_path = public as $$
  select
    coalesce(user_id::text, device_id),
    case when user_id is not null then 'user' else 'device' end,
    count(*) filter (where event_type='view'),
    count(*) filter (where event_type='install'),
    count(*) filter (where event_type='share'),
    count(*) filter (where event_type='favorite'),
    min(ts), max(ts)
  from public.wallpaper_events
  where wallpaper_id = p_wallpaper_id
  group by user_id, device_id
  order by max(ts) desc
  limit greatest(1, least(p_limit, 500));
$$;
