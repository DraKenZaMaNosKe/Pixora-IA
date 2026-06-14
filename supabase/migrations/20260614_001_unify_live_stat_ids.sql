-- 2026-06-14 — Unify wallpaper_stats IDs for LIVE wallpapers.
--
-- Bug: el live preview prefixaba "live_" al wallpaper.id mientras el
-- holocard estatico y otras pantallas usaban el id puro. Resultado: dos
-- filas distintas en wallpaper_stats para el mismo wallpaper (ej
-- bulma_live=0 likes y live_bulma_live=1 like) que nunca se reconcilian
-- en tiempo real porque son rows separadas.
--
-- Fix: 1) sumar contadores de live_X dentro de X (upsert ADD), 2) borrar
-- live_X, 3) reasignar wallpaper_likes.live_X -> X (skip si ya existe el
-- like del mismo device en X), 4) REPLICA IDENTITY FULL para que Realtime
-- entregue payloads completos (oldRecord + newRecord) y el cliente pueda
-- diffear sin perder valores.

-- 1) Merge stats: live_X -> X (sum, no replace)
INSERT INTO public.wallpaper_stats (wallpaper_id, likes, downloads, views)
SELECT substring(wallpaper_id from 6), likes, downloads, views
FROM public.wallpaper_stats
WHERE wallpaper_id LIKE 'live_%'
ON CONFLICT (wallpaper_id) DO UPDATE SET
  likes     = public.wallpaper_stats.likes     + EXCLUDED.likes,
  downloads = public.wallpaper_stats.downloads + EXCLUDED.downloads,
  views     = public.wallpaper_stats.views     + EXCLUDED.views;

-- 2) Drop legacy live_* rows
DELETE FROM public.wallpaper_stats WHERE wallpaper_id LIKE 'live_%';

-- 3) Reassign wallpaper_likes: live_X -> X, skip duplicates
INSERT INTO public.wallpaper_likes (device_id, wallpaper_id, user_id)
SELECT device_id, substring(wallpaper_id from 6), user_id
FROM public.wallpaper_likes
WHERE wallpaper_id LIKE 'live_%'
ON CONFLICT (device_id, wallpaper_id) DO NOTHING;

DELETE FROM public.wallpaper_likes WHERE wallpaper_id LIKE 'live_%';

-- 4) REPLICA IDENTITY FULL for wallpaper_stats so Realtime emits the
--    full new+old record on UPDATE. Without this, oldRecord arrives as
--    {pk only} and we cant diff which counter actually changed if the
--    client cache was stale.
ALTER TABLE public.wallpaper_stats REPLICA IDENTITY FULL;

-- Optional: same treatment for wallpaper_likes (in case we ever subscribe
-- to INSERT/DELETE on it for "someone liked it" badges)
ALTER TABLE public.wallpaper_likes REPLICA IDENTITY FULL;
