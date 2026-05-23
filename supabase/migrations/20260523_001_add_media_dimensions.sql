-- Fase 1 del "dimension-agnostic system" — Pixora ya no fuerza dimensiones
-- específicas (1080x2340 / 4192x1024). Cualquier imagen con cualquier ratio
-- se acepta y la UI se adapta dinámicamente.
--
-- Esta migración solo agrega los CAMPOS para guardar las dimensiones reales.
-- El cambio en la UI (isPanoramic calculado del ratio, etc.) viene en Fase 2.
--
-- Después de correr esto, ejecutar el script de backfill para llenar las
-- dimensiones de los 282 wallpapers existentes:
--   python tools/wallpapers/_backfill_media_dimensions.py
--
-- Lección aprendida 2026-05-22 (aa7fbde): cuando ALTER TABLE agrega
-- columnas, hay que recrear la view en CASCADE para que las exponga.

ALTER TABLE public.wallpapers
  ADD COLUMN IF NOT EXISTS media_width  int CHECK (media_width  IS NULL OR (media_width  > 0 AND media_width  <= 16384)),
  ADD COLUMN IF NOT EXISTS media_height int CHECK (media_height IS NULL OR (media_height > 0 AND media_height <= 16384));

COMMENT ON COLUMN public.wallpapers.media_width  IS 'Pixel width of the source image/video. Filled by upload pipeline or backfill script. NULL = unknown (legacy items pending backfill).';
COMMENT ON COLUMN public.wallpapers.media_height IS 'Pixel height of the source image/video. Same caveat as media_width.';

-- Recreate view CASCADE (drops wp_search which depends on it)
DROP VIEW IF EXISTS public.wallpapers_v CASCADE;

CREATE VIEW public.wallpapers_v AS
SELECT
  id, name, description, type, category, tags,
  image_path, preview_path, image_size, preview_size,
  media_width, media_height,
  wp_storage_base() || image_path AS image_url,
  wp_storage_base() || preview_path AS preview_url,
  glow_color, badge, sort_order, featured,
  trending_score, view_count, install_count, share_count, favorite_count,
  published,
  author_name, author_user_id,
  tsv, created_at, updated_at, daily_eligible
FROM public.wallpapers
WHERE published = true;

COMMENT ON VIEW public.wallpapers_v IS
  'App-facing view: only published wallpapers, with full URLs computed. Includes media_width/media_height for dimension-agnostic UI rendering (Fase 2).';

CREATE OR REPLACE FUNCTION public.wp_search(
  p_query text DEFAULT NULL::text,
  p_category wallpaper_category DEFAULT NULL::wallpaper_category,
  p_limit integer DEFAULT 24,
  p_offset integer DEFAULT 0
)
RETURNS SETOF wallpapers_v
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT v.*
  FROM public.wallpapers_v v
  WHERE
    (p_category IS NULL OR v.category = p_category)
    AND (
      p_query IS NULL OR p_query = ''
      OR v.tsv @@ websearch_to_tsquery('simple', p_query)
      OR v.name ILIKE '%' || p_query || '%'
    )
  ORDER BY
    CASE WHEN p_query IS NULL OR p_query = '' THEN v.trending_score END DESC NULLS LAST,
    CASE WHEN p_query IS NOT NULL AND p_query <> '' THEN ts_rank(v.tsv, websearch_to_tsquery('simple', p_query)) END DESC NULLS LAST,
    v.sort_order ASC
  LIMIT GREATEST(1, LEAST(p_limit, 100))
  OFFSET GREATEST(0, p_offset);
$function$;
