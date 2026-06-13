-- 2026-06-13 — Fix complementario al 20260613_001.
--
-- El primer fix otorgo SELECT/INSERT/DELETE a anon sobre wallpaper_likes,
-- pero el cliente usa .upsert() que internamente requiere UPDATE tambien.
-- Sintoma observado: el RPC increment_likes SI actualizo wallpaper_stats
-- (likes=1 en aquarium_betta_paradise a las 19:09 UTC) pero la tabla
-- wallpaper_likes seguia sin nuevos inserts.
--
-- Fix: anadir UPDATE al GRANT.

GRANT UPDATE ON public.wallpaper_likes TO anon;

-- Verificacion post-aplicacion:
-- SELECT grantee, privilege_type FROM information_schema.table_privileges
-- WHERE table_name = 'wallpaper_likes' AND grantee = 'anon';
-- Debe mostrar 4 filas: SELECT, INSERT, UPDATE, DELETE.
