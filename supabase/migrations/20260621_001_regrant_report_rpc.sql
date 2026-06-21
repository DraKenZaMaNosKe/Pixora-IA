-- 2026-06-21 — Re-aplicar GRANT EXECUTE sobre report_wallpaper.
-- El CREATE OR REPLACE FUNCTION del migration 20260620_002 reseteó los
-- grants previos del migration 20260620_001 (Postgres no preserva
-- permisos cuando recreas la función). Resultado: anon/authenticated
-- recibían 42501 al intentar reportar, y el client lo trataba como
-- "no se pudo enviar el reporte". Eduardo probó en device y vimos
-- 0 rows en la tabla aunque la APK era v1.7.30.

GRANT EXECUTE ON FUNCTION public.report_wallpaper(text, text, text, text, text, text, jsonb)
    TO anon, authenticated;
