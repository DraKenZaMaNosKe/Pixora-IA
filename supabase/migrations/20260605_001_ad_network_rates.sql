-- Move hardcoded eCPM rates from views/RPC to a config table so Eduardo
-- can update them via SQL editor without rewriting the views every time.
-- Original rates lived inline in admin_ad_revenue_daily, admin_ad_users
-- and wp_ad_stats (* 0.0025 / 0.0080 / 0.0006 — see 20260501_005_ad_events.sql).

create table if not exists public.ad_network_rates (
  ad_kind     text primary key,
  ecpm_usd    numeric not null,
  region      text default 'LATAM',
  updated_at  timestamptz not null default now(),
  notes       text
);

-- Seed with the previously-hardcoded values + new 'native' for our
-- in-grid native ads shipped in v1.7.18.
insert into public.ad_network_rates (ad_kind, ecpm_usd, region, notes)
values
  ('interstitial', 2.50, 'LATAM', 'Default seed from 2026-05-08 hardcoded'),
  ('rewarded',     8.00, 'LATAM', 'Default seed from 2026-05-08 hardcoded'),
  ('banner',       0.60, 'LATAM', 'Default seed from 2026-05-08 hardcoded'),
  ('native',       1.80, 'LATAM', 'New in v1.7.18 — native ads in feed')
on conflict (ad_kind) do nothing;

-- Anon read access — needed by dashboard /api/ad-rates endpoint
do $$ begin
  alter table public.ad_network_rates enable row level security;
exception when others then null; end $$;
do $$ begin
  create policy "ad_network_rates anon read"
    on public.ad_network_rates for select
    using (true);
exception when duplicate_object then null; end $$;

-- Per-show rate helper: eCPM is dollars per 1000 shows, so per-show rate
-- is eCPM / 1000. Returns 0 when kind missing (defensive — older clients
-- may log an unrecognized ad_kind).
create or replace function public.ad_rate_per_show(kind text)
returns numeric language sql stable as $$
  select coalesce(
    (select ecpm_usd from public.ad_network_rates where ad_kind = kind) / 1000.0,
    0
  );
$$;

-- Drop + recreate views (CREATE OR REPLACE is too strict — refuses any
-- column change including additions in the middle).
drop view if exists public.admin_ad_revenue_daily cascade;
drop view if exists public.admin_ad_users cascade;

create view public.admin_ad_revenue_daily as
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
    (count(*) filter (where ad_kind='interstitial' and shown) * public.ad_rate_per_show('interstitial')) +
    (count(*) filter (where ad_kind='rewarded'     and shown) * public.ad_rate_per_show('rewarded')) +
    (count(*) filter (where ad_kind='banner'       and shown) * public.ad_rate_per_show('banner')) +
    (count(*) filter (where ad_kind='native'       and shown) * public.ad_rate_per_show('native')),
    4
  ) as est_revenue_usd,
  count(*) filter (where ad_kind='native'       and shown)     as natives
from public.ad_events
group by 1
order by 1 desc;

create view public.admin_ad_users as
select
  coalesce(user_id::text, device_id) as identity,
  case when user_id is not null then 'user' else 'device' end as identity_type,
  user_id, device_id,
  count(*)                                                as total_ads,
  count(*) filter (where ad_kind='interstitial')          as interstitials,
  count(*) filter (where ad_kind='rewarded')              as rewarded_shown,
  count(*) filter (where ad_kind='rewarded' and rewarded) as rewarded_completed,
  count(*) filter (where ad_kind='banner')                as banners,
  min(ts) as first_ad,
  max(ts) as last_ad,
  round(
    (count(*) filter (where ad_kind='interstitial' and shown) * public.ad_rate_per_show('interstitial')) +
    (count(*) filter (where ad_kind='rewarded'     and shown) * public.ad_rate_per_show('rewarded')) +
    (count(*) filter (where ad_kind='banner'       and shown) * public.ad_rate_per_show('banner')) +
    (count(*) filter (where ad_kind='native'       and shown) * public.ad_rate_per_show('native')),
    4
  ) as est_revenue_usd,
  count(*) filter (where ad_kind='native')                as natives
from public.ad_events
group by user_id, device_id
order by total_ads desc;

-- Rebuild wp_ad_stats using the function (drop and recreate because of
-- the new 'native' jsonb breakdown — old signature didn't include it but
-- by_kind is jsonb so it auto-adapts).
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
       (count(*) filter (where ad_kind='interstitial' and shown) * public.ad_rate_per_show('interstitial')) +
       (count(*) filter (where ad_kind='rewarded'     and shown) * public.ad_rate_per_show('rewarded')) +
       (count(*) filter (where ad_kind='banner'       and shown) * public.ad_rate_per_show('banner')) +
       (count(*) filter (where ad_kind='native'       and shown) * public.ad_rate_per_show('native')), 4)
       from public.ad_events),
    (select round(
       (count(*) filter (where ad_kind='interstitial' and shown) * public.ad_rate_per_show('interstitial')) +
       (count(*) filter (where ad_kind='rewarded'     and shown) * public.ad_rate_per_show('rewarded')) +
       (count(*) filter (where ad_kind='banner'       and shown) * public.ad_rate_per_show('banner')) +
       (count(*) filter (where ad_kind='native'       and shown) * public.ad_rate_per_show('native')), 4)
       from public.ad_events where ts > now() - interval '30 days');
$$;
