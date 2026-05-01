-- =============================================================================
-- ROLLBACK script for the wallpapers schema (Tier 1)
-- Run only if you need to revert to the catalog.json era.
-- Order matters: drop dependents first.
-- =============================================================================

drop view if exists public.wallpapers_v cascade;

drop function if exists public.wp_search(text, wallpaper_category, int, int);
drop function if exists public.wp_increment_view(text);
drop function if exists public.wp_increment_install(text);
drop function if exists public.wp_increment_share(text);
drop function if exists public.wp_adjust_favorite(text, int);
drop function if exists public.wp_recompute_trending();
drop function if exists public.wp_stats();
drop function if exists public.wp_storage_base();
drop function if exists public.set_updated_at() cascade;

drop table if exists public.wallpapers cascade;

drop type if exists wallpaper_badge;
drop type if exists wallpaper_category;
drop type if exists wallpaper_type;

-- pg_trgm and pgcrypto extensions are left in place (used by Supabase).
