-- 2026-06-13 — Fix sistema de likes roto desde 2026-05-27.
--
-- ROOT CAUSE: las RPCs y la tabla wallpaper_likes no tienen GRANT al role
-- 'anon'. Pixora permite uso sin login (anonymous), por lo que el cliente
-- Flutter (que usa la anon key) recibe `permission denied` ANTES de llegar
-- a la RLS policy. El try/catch en WallpaperStatsService.toggleLike() lo
-- silencia con un debugPrint, dejando al usuario sin feedback de error.
--
-- SINTOMA observado por usuarios: dan like al wallpaper, el contador NO
-- cambia. La tabla wallpaper_stats no recibe nuevos datos desde 2026-05-27
-- (el dia que probablemente alguien revoco accidentalmente los grants, o
-- el dia que se recrearon las funciones sin re-aplicar grants).
--
-- FIX: permitir a anon ejecutar las 3 RPCs de tracking + insertar/borrar
-- en wallpaper_likes. Las policies RLS existentes ya filtran apropiadamente.
--
-- ROLLBACK: revoke en lugar de grant (ver al final del archivo).

-- ── RPCs de likes ──────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.increment_likes(text) TO anon;
GRANT EXECUTE ON FUNCTION public.decrement_likes(text) TO anon;

-- ── RPC universal de eventos (view/install/share/favorite/etc.) ──
-- wp_log_event tiene SECURITY DEFINER asi que internamente puede update
-- wallpapers, pero el caller necesita poder INVOCARLA.
GRANT EXECUTE ON FUNCTION public.wp_log_event(text, text, text, text, jsonb)
    TO anon;

-- ── Tabla wallpaper_likes ──────────────────────────────────────
-- El cliente hace .upsert() y .delete() directamente. Las policies RLS
-- ya permiten "anyone insert/delete/select" (verificado 2026-06-13).
GRANT SELECT, INSERT, DELETE ON public.wallpaper_likes TO anon;

-- ── Verificacion post-migracion ────────────────────────────────
-- Despues de aplicar, correr este SELECT debe mostrar 'EXECUTE' para anon:
--
-- SELECT grantee, privilege_type
-- FROM information_schema.routine_privileges
-- WHERE routine_schema = 'public'
--   AND routine_name IN ('increment_likes','decrement_likes','wp_log_event')
--   AND grantee = 'anon';

-- ── ROLLBACK (no ejecutar a menos que algo se rompa) ──────────
-- REVOKE EXECUTE ON FUNCTION public.increment_likes(text) FROM anon;
-- REVOKE EXECUTE ON FUNCTION public.decrement_likes(text) FROM anon;
-- REVOKE EXECUTE ON FUNCTION public.wp_log_event(text,text,text,text,jsonb) FROM anon;
-- REVOKE SELECT, INSERT, DELETE ON public.wallpaper_likes FROM anon;
