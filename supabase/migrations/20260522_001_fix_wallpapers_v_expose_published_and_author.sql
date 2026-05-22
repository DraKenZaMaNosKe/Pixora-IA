-- Bug: catalog_service.dart filtra `.eq('published', true)` y Wallpaper.fromSupabase
-- lee `author_name` / `author_user_id`, pero wallpapers_v no expone esas 3 columnas
-- (la migration 20260518_002_wallpaper_authors.sql las agrego a la tabla pero olvido
-- actualizar la vista). Resultado: PostgrestException 42703 -> app cae al JSON
-- legacy obsoleto y nuevos wallpapers (Saga de Geminis) son invisibles.
--
-- wp_search() devuelve SETOF wallpapers_v y debe recrearse en cascada.
DROP VIEW IF EXISTS public.wallpapers_v CASCADE;

CREATE VIEW public.wallpapers_v AS
SELECT
  id, name, description, type, category, tags,
  image_path, preview_path, image_size, preview_size,
  wp_storage_base() || image_path AS image_url,
  wp_storage_base() || preview_path AS preview_url,
  glow_color, badge, sort_order, featured,
  trending_score, view_count, install_count, share_count, favorite_count,
  published,
  author_name, author_user_id,
  tsv, created_at, updated_at, daily_eligible
FROM wallpapers
WHERE published = true;

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
