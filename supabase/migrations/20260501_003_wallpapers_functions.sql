-- =============================================================================
-- Pixora Wallpapers — Functions & Views
-- Migration: 20260501_003_wallpapers_functions
-- Purpose:   Encapsulate analytics/search logic so the app calls high-level fns.
--
-- All functions are SECURITY DEFINER + revocable from anon/authenticated.
-- The app calls them via Supabase RPC; service_role can call directly.
-- =============================================================================

-- Resolve the storage base URL once. Edit here if Supabase project ever moves.
create or replace function public.wp_storage_base()
returns text language sql immutable as $$
  select 'https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-images/'::text
$$;
comment on function public.wp_storage_base() is
  'Single source of truth for storage URL. Update here when project URL changes.';

-- ---------------------------------------------------------------------------
-- Public view: wallpapers with computed full URLs
-- This is what the app reads.
-- ---------------------------------------------------------------------------
create or replace view public.wallpapers_v as
select
  w.id,
  w.name,
  w.description,
  w.type,
  w.category,
  w.tags,
  w.image_path,
  w.preview_path,
  w.image_size,
  w.preview_size,
  public.wp_storage_base() || w.image_path   as image_url,
  public.wp_storage_base() || w.preview_path as preview_url,
  w.glow_color,
  w.badge,
  w.sort_order,
  w.featured,
  w.trending_score,
  w.view_count,
  w.install_count,
  w.share_count,
  w.favorite_count,
  w.created_at,
  w.updated_at
from public.wallpapers w
where w.published = true;

comment on view public.wallpapers_v is
  'App-facing view: only published wallpapers, with full URLs computed.';

-- ---------------------------------------------------------------------------
-- increment_view(id) — bump view counter atomically
-- Safe to call from anon role via RPC.
-- ---------------------------------------------------------------------------
create or replace function public.wp_increment_view(p_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.wallpapers
    set view_count = view_count + 1,
        last_viewed_at = now()
    where id = p_id and published = true;
end$$;
comment on function public.wp_increment_view(text) is
  'Bump view_count for wallpaper. Anon-callable via RPC.';

-- ---------------------------------------------------------------------------
-- increment_install(id) — bump install counter
-- ---------------------------------------------------------------------------
create or replace function public.wp_increment_install(p_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.wallpapers
    set install_count = install_count + 1,
        last_installed_at = now()
    where id = p_id and published = true;
end$$;
comment on function public.wp_increment_install(text) is
  'Bump install_count when user applies wallpaper. Anon-callable via RPC.';

-- ---------------------------------------------------------------------------
-- increment_share(id) / increment_favorite(id, delta)
-- ---------------------------------------------------------------------------
create or replace function public.wp_increment_share(p_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.wallpapers
    set share_count = share_count + 1
    where id = p_id and published = true;
end$$;

create or replace function public.wp_adjust_favorite(p_id text, p_delta int)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.wallpapers
    set favorite_count = greatest(0, favorite_count + p_delta)
    where id = p_id and published = true;
end$$;
comment on function public.wp_adjust_favorite(text,int) is
  'Adjust favorite_count by delta (+1 / -1). Bottoms at 0.';

-- ---------------------------------------------------------------------------
-- recompute_trending_scores()
-- Formula: (views + installs*5 + shares*10 + favs*3) * exp(-days_since_view/14)
-- Run via cron every hour or after batch events.
-- ---------------------------------------------------------------------------
create or replace function public.wp_recompute_trending()
returns int language plpgsql security definer set search_path = public as $$
declare
  rows_updated int;
begin
  with scored as (
    select
      id,
      ((coalesce(view_count, 0)
        + coalesce(install_count, 0)  * 5.0
        + coalesce(share_count, 0)    * 10.0
        + coalesce(favorite_count, 0) * 3.0)
       * exp(
           -greatest(0,
             extract(epoch from (now() - coalesce(last_viewed_at, created_at))) / 86400.0
           ) / 14.0
         )
      )::real as score
    from public.wallpapers
    where published = true
  )
  update public.wallpapers w
    set trending_score = s.score
    from scored s
    where w.id = s.id;
  get diagnostics rows_updated = row_count;
  return rows_updated;
end$$;
comment on function public.wp_recompute_trending() is
  'Recompute trending_score for all published wallpapers. Returns row count.';

-- ---------------------------------------------------------------------------
-- search_wallpapers(query, category, limit, offset) — main app search
-- Combines tsvector + trigram for typo tolerance.
-- ---------------------------------------------------------------------------
create or replace function public.wp_search(
  p_query    text default null,
  p_category wallpaper_category default null,
  p_limit    int default 24,
  p_offset   int default 0
) returns setof public.wallpapers_v
language sql stable security definer set search_path = public as $$
  select v.*
  from public.wallpapers_v v
  where
    (p_category is null or v.category = p_category)
    and (
      p_query is null or p_query = ''
      or v.tsv @@ websearch_to_tsquery('simple', p_query)
      or v.name ilike '%' || p_query || '%'
    )
  order by
    case when p_query is null or p_query = '' then v.trending_score end desc nulls last,
    case when p_query is not null and p_query <> '' then ts_rank(v.tsv, websearch_to_tsquery('simple', p_query)) end desc nulls last,
    v.sort_order asc
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset);
$$;
comment on function public.wp_search(text, wallpaper_category, int, int) is
  'Main search/list function. Empty query = trending feed. Limit capped at 100.';

-- ---------------------------------------------------------------------------
-- Convenience: wp_stats() — quick health check
-- ---------------------------------------------------------------------------
create or replace function public.wp_stats()
returns table(
  total          bigint,
  published      bigint,
  unpublished    bigint,
  by_category    jsonb,
  total_views    bigint,
  total_installs bigint,
  most_viewed    jsonb
) language sql stable security definer set search_path = public as $$
  select
    (select count(*) from public.wallpapers),
    (select count(*) from public.wallpapers where published),
    (select count(*) from public.wallpapers where not published),
    (select jsonb_object_agg(category, n)
       from (select category::text, count(*) n from public.wallpapers where published group by category) sub),
    (select coalesce(sum(view_count), 0) from public.wallpapers),
    (select coalesce(sum(install_count), 0) from public.wallpapers),
    (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'views', view_count) order by view_count desc)
       from (select id, name, view_count from public.wallpapers where published order by view_count desc limit 10) t);
$$;
comment on function public.wp_stats() is
  'Health check: counts, top-10 most viewed. Useful for admin dashboards.';
