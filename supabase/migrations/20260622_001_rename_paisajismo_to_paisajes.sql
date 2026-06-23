-- 2026-06-22 — Bug fix: Pixora Daily category "PAISAJES" no funcionaba
-- porque el código Flutter filtra por `w.category == 'PAISAJES'` pero
-- el enum Postgres tenía el valor 'PAISAJISMO'. Renombramos el valor
-- (operación in-place, no afecta filas existentes — postgres mantiene
-- las refs por OID interno).
--
-- Afecta a 30 wallpapers publicados hoy + cualquier otro previo con
-- esta categoría. Después del rename, el Daily mode "PAISAJES" en
-- v1.7.30 (Play Store) jalará sin necesidad de update de app.

ALTER TYPE wallpaper_category RENAME VALUE 'PAISAJISMO' TO 'PAISAJES';
