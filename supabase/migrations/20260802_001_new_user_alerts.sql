-- =============================================================================
-- Alertas 24/7 de usuario nuevo real — Pixora IA
-- Migration: 20260802_001_new_user_alerts
-- Diseño: Fable 5 (revisado por Claude). Aditiva y reversible: SOLO lee
-- device_presence/wallpaper_events, no modifica tablas existentes.
-- =============================================================================
create extension if not exists pg_net;

-- Exclusiones: devices de Eduardo, testers conocidos, manuales.
create table if not exists public.alert_device_exclusions (
  device_id text primary key,
  reason    text not null,
  added_at  timestamptz not null default now()
);
alter table public.alert_device_exclusions enable row level security;

-- Log de decisiones = dedup (PK) + auditoría + cola de reintento (notified_at null).
create table if not exists public.new_user_alerts (
  device_id     text primary key,
  first_seen_at timestamptz not null,
  classified_as text not null,          -- 'REAL' | 'BOT_BATCH'
  detected_at   timestamptz not null default now(),
  notified_at   timestamptz,
  payload       jsonb
);
alter table public.new_user_alerts enable row level security;

-- BASELINE: marcar todos los devices EXISTENTES como ya procesados para que el
-- sistema SOLO alerte de usuarios que lleguen DESPUÉS del despliegue (evita
-- spam del histórico en el primer arranque). notified_at=now() => nunca alertan.
insert into public.new_user_alerts (device_id, first_seen_at, classified_as, notified_at, payload)
select device_id, first_seen_at, 'BASELINE', now(), '{}'::jsonb
from public.device_presence
on conflict (device_id) do nothing;

-- Seed de exclusiones (devices de Eduardo — 41 ids). idempotente.
insert into public.alert_device_exclusions (device_id, reason) values
  ('hh727rvhx2', 'eduardo'),
  ('hh9wn0faw8', 'eduardo'),
  ('hhrhuxc7el', 'eduardo'),
  ('hi3tfqe38t', 'eduardo'),
  ('hi4ffxn112', 'eduardo'),
  ('hi4ghcg56f', 'eduardo'),
  ('hi4zelvwjh', 'eduardo'),
  ('hi6m1ibe6b', 'eduardo'),
  ('hi911c7nn5', 'eduardo'),
  ('hi93a2nehy', 'eduardo'),
  ('hi93a5bab9', 'eduardo'),
  ('hi93as7vcy', 'eduardo'),
  ('hig80kaxl8', 'eduardo'),
  ('hii6pa5l2x', 'eduardo'),
  ('hii6pedblu', 'eduardo'),
  ('hii6pk97zf', 'eduardo'),
  ('hii6poo9x6', 'eduardo'),
  ('hii6ppz8ga', 'eduardo'),
  ('hiljctiry1', 'eduardo'),
  ('hiubydkqam', 'eduardo'),
  ('hjg5ndehii', 'eduardo'),
  ('hjk12xod2t', 'eduardo'),
  ('hjk133o9mp', 'eduardo'),
  ('hjk134699s', 'eduardo'),
  ('hjmucvnhk4', 'eduardo'),
  ('hjqfsc118e', 'eduardo'),
  ('hjsdab9oew', 'eduardo'),
  ('hjtnd4oufk', 'eduardo'),
  ('hk4gjvbj65', 'eduardo'),
  ('hk4h9g1ydcwfcaiz', 'eduardo'),
  ('hk4heom1mr', 'eduardo'),
  ('hkdmodrd7w', 'eduardo'),
  ('hkeo2bjnn7ekyq7z', 'eduardo'),
  ('hkgsuvsde514ptbi5', 'eduardo'),
  ('hkit1c8st0uxfxry', 'eduardo'),
  ('hkj94qyoky', 'eduardo'),
  ('hkjmoz71g3', 'eduardo'),
  ('hkmbmeydyz', 'eduardo'),
  ('hkrpclvioxiexp2c', 'eduardo'),
  ('hkruxtxtxh1yzujbz', 'eduardo'),
  ('hkrv8pcfg71n0auko', 'eduardo')
on conflict (device_id) do nothing;

-- ── Detector híbrido: rápido en general (madura 15 min) + INSTANTÁNEO si el
--    device ya descargó un wallpaper o hizo >=4 eventos (un bot casi nunca).
create or replace function public.detect_new_real_users()
returns setof public.new_user_alerts
language plpgsql security definer set search_path = public as $$
begin
  with ev as (
    select device_id,
           count(*) as n,
           count(*) filter (where event_type = 'download') as dl
    from wallpaper_events
    where ts > now() - interval '8 days'
    group by device_id
  ),
  candidates as (
    select dp.*, coalesce(ev.n,0) as n_ev, coalesce(ev.dl,0) as n_dl
    from device_presence dp
    left join ev on ev.device_id = dp.device_id
    where dp.first_seen_at between now() - interval '7 days' and now() - interval '30 seconds'
      and not exists (select 1 from new_user_alerts a where a.device_id = dp.device_id)
      and not exists (select 1 from alert_device_exclusions x where x.device_id = dp.device_id)
  ),
  -- Cohortes anti-bot: mismo día + versión, >=10 devices, promedio <=2 eventos.
  cohort as (
    select date(dp.first_seen_at) d, dp.app_version v,
           count(*) n_dev, avg(coalesce(ev.n,0)) avg_ev
    from device_presence dp
    left join ev on ev.device_id = dp.device_id
    where dp.first_seen_at > now() - interval '7 days'
    group by 1,2
  ),
  bot_cohorts as (select d, v from cohort where n_dev >= 10 and avg_ev <= 2.0)
  insert into new_user_alerts (device_id, first_seen_at, classified_as, payload)
  select c.device_id, c.first_seen_at,
         case
           when c.n_dl >= 1 or c.n_ev >= 4 then 'REAL'                        -- fast-path: señal fuerte
           when bc.d is not null then 'BOT_BATCH'                             -- ráfaga de bots
           else 'REAL'
         end,
         jsonb_build_object('model', c.device_model, 'sdk', c.android_sdk,
           'version', c.app_version, 'source', c.last_source,
           'wallpaper', c.active_wallpaper_id, 'daily', c.daily_enabled,
           'events', c.n_ev, 'downloads', c.n_dl)
  from candidates c
  left join bot_cohorts bc on bc.d = date(c.first_seen_at) and bc.v is not distinct from c.app_version
  -- Solo juzgar si: maduró 15 min, O ya tiene señal fuerte (download/>=4 ev).
  where c.first_seen_at <= now() - interval '15 minutes' or c.n_dl >= 1 or c.n_ev >= 4
  on conflict (device_id) do nothing;

  return query select * from new_user_alerts where classified_as='REAL' and notified_at is null;
end $$;
revoke all on function public.detect_new_real_users() from public, anon, authenticated;
