-- =============================================================================
-- Pixora Ad Events — track every ad impression for revenue analysis
-- Migration: 20260501_005_ad_events
-- Tier 4. Applied to production 2026-05-01.
-- =============================================================================

do $$ begin
  create type ad_kind as enum ('interstitial','rewarded','banner','native');
exception when duplicate_object then null; end $$;

create table if not exists public.ad_events (
  id            bigserial primary key,
  device_id     text not null check (length(device_id) between 1 and 80),
  user_id       uuid,
  ad_kind       ad_kind not null,
  network       text not null default 'admob',
  placement     text,                 -- wallpaper_apply, aura_play, etc.
  unit_id       text,                 -- AdMob ad unit id (no secret)
  wallpaper_id  text references public.wallpapers(id) on delete set null,
  shown         boolean not null default true,
  rewarded      boolean not null default false,
  ts            timestamptz not null default now(),
  app_version   text,
  metadata      jsonb not null default '{}'::jsonb
);

comment on table public.ad_events is
  'Granular ad impression log. Backbone of revenue analytics.';
comment on column public.ad_events.placement is
  'Where in the app the ad was triggered (wallpaper_apply, aura_play, etc.).';
comment on column public.ad_events.shown is
  'true if ad actually rendered. false if AdMob returned no-fill / error.';
comment on column public.ad_events.rewarded is
  'true if rewarded ad completed and user received reward (credits/diamond).';

create index if not exists idx_ae_device_ts on public.ad_events (device_id, ts desc);
create index if not exists idx_ae_user_ts   on public.ad_events (user_id, ts desc) where user_id is not null;
create index if not exists idx_ae_ts        on public.ad_events (ts desc);
create index if not exists idx_ae_kind      on public.ad_events (ad_kind, ts desc);
create index if not exists idx_ae_placement on public.ad_events (placement, ts desc);

alter table public.ad_events enable row level security;
-- No policies → service_role only (read AND write).

-- ───────── RPC: log a single ad event (anon-callable) ─────────
create or replace function public.wp_log_ad_event(
  p_device_id    text,
  p_ad_kind      text,
  p_placement    text   default null,
  p_unit_id      text   default null,
  p_wallpaper_id text   default null,
  p_shown        boolean default true,
  p_rewarded     boolean default false,
  p_app_version  text   default null,
  p_network      text   default 'admob',
  p_metadata     jsonb  default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if p_ad_kind not in ('interstitial','rewarded','banner','native') then
    raise exception 'Invalid ad_kind: %', p_ad_kind;
  end if;
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;
  insert into public.ad_events
    (device_id, user_id, ad_kind, network, placement, unit_id, wallpaper_id,
     shown, rewarded, app_version, metadata)
    values
    (p_device_id, v_uid, p_ad_kind::ad_kind, p_network, p_placement, p_unit_id, p_wallpaper_id,
     p_shown, p_rewarded, p_app_version, p_metadata);
end$$;
comment on function public.wp_log_ad_event(text,text,text,text,text,boolean,boolean,text,text,jsonb) is
  'Anon-callable. Logs 1 ad impression (interstitial/rewarded/banner/native).';

grant execute on function
  public.wp_log_ad_event(text,text,text,text,text,boolean,boolean,text,text,jsonb)
  to anon, authenticated;

-- ───────── Admin views (service_role only) ─────────
-- eCPM LATAM averages used: interstitial $2.50, rewarded $8.00, banner $0.60

create or replace view public.admin_ad_revenue_daily as
select
  date_trunc('day', ts)::date                                  as day,
  count(*)                                                     as total_ads,
  count(*) filter (where shown)                                as shown_ads,
  count(*) filter (where ad_kind='interstitial' and shown)     as interstitials,
  count(*) filter (where ad_kind='rewarded'     and shown)     as rewarded_shown,
  count(*) filter (where ad_kind='rewarded'     and rewarded)  as rewarded_completed,
  count(*) filter (where ad_kind='banner'       and shown)     as banners,
  count(distinct device_id)                                    as unique_devices,
  round(
    (count(*) filter (where ad_kind='interstitial' and shown) * 0.0025)::numeric +
    (count(*) filter (where ad_kind='rewarded'     and shown) * 0.0080)::numeric +
    (count(*) filter (where ad_kind='banner'       and shown) * 0.0006)::numeric,
    4
  ) as est_revenue_usd
from public.ad_events
group by 1
order by 1 desc;

create or replace view public.admin_ad_users as
select
  coalesce(user_id::text, device_id) as identity,
  case when user_id is not null then 'user' else 'device' end as identity_type,
  user_id, device_id,
  count(*)                                              as total_ads,
  count(*) filter (where ad_kind='interstitial')        as interstitials,
  count(*) filter (where ad_kind='rewarded')            as rewarded_shown,
  count(*) filter (where ad_kind='rewarded' and rewarded) as rewarded_completed,
  count(*) filter (where ad_kind='banner')              as banners,
  min(ts) as first_ad,
  max(ts) as last_ad,
  round(
    (count(*) filter (where ad_kind='interstitial' and shown) * 0.0025)::numeric +
    (count(*) filter (where ad_kind='rewarded'     and shown) * 0.0080)::numeric +
    (count(*) filter (where ad_kind='banner'       and shown) * 0.0006)::numeric,
    4
  ) as est_revenue_usd
from public.ad_events
group by user_id, device_id
order by total_ads desc;

create or replace function public.wp_ad_stats()
returns table(
  total_ads        bigint,
  total_shown      bigint,
  total_failed     bigint,
  unique_devices   bigint,
  by_kind          jsonb,
  by_placement     jsonb,
  est_total_usd    numeric,
  est_last_30d_usd numeric
) language sql stable security definer set search_path = public as $$
  select
    (select count(*) from public.ad_events),
    (select count(*) from public.ad_events where shown),
    (select count(*) from public.ad_events where not shown),
    (select count(distinct device_id) from public.ad_events),
    (select jsonb_object_agg(ad_kind, n)
       from (select ad_kind::text, count(*) n from public.ad_events where shown group by ad_kind) sub),
    (select jsonb_object_agg(coalesce(placement, '(none)'), n)
       from (select placement, count(*) n from public.ad_events where shown group by placement) sub),
    (select round(
       (count(*) filter (where ad_kind='interstitial' and shown) * 0.0025)::numeric +
       (count(*) filter (where ad_kind='rewarded'     and shown) * 0.0080)::numeric +
       (count(*) filter (where ad_kind='banner'       and shown) * 0.0006)::numeric, 4)
       from public.ad_events),
    (select round(
       (count(*) filter (where ad_kind='interstitial' and shown) * 0.0025)::numeric +
       (count(*) filter (where ad_kind='rewarded'     and shown) * 0.0080)::numeric +
       (count(*) filter (where ad_kind='banner'       and shown) * 0.0006)::numeric, 4)
       from public.ad_events where ts > now() - interval '30 days');
$$;
