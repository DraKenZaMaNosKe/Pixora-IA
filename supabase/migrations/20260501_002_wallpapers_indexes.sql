-- =============================================================================
-- Pixora Wallpapers — Indexes & Search
-- Migration: 20260501_002_wallpapers_indexes
-- Purpose:   Make all common queries O(log n) or better.
--
-- Index strategy:
--   - Partial indexes (WHERE published = true) — most queries hit only published
--   - GIN for arrays (tags) and tsvector (full-text)
--   - btree for category / sort / trending
--   - trigram for fuzzy name search
-- =============================================================================

-- Category filter (homepage tabs) — partial index
create index if not exists idx_wallpapers_category
  on public.wallpapers (category)
  where published = true;

-- Tags lookup ('goku' = ANY(tags))
create index if not exists idx_wallpapers_tags_gin
  on public.wallpapers using gin(tags);

-- Sort order (within category)
create index if not exists idx_wallpapers_sort
  on public.wallpapers (category, sort_order)
  where published = true;

-- Trending feed (homepage hero)
create index if not exists idx_wallpapers_trending
  on public.wallpapers (trending_score desc)
  where published = true;

-- Featured carousel
create index if not exists idx_wallpapers_featured
  on public.wallpapers (sort_order)
  where featured = true and published = true;

-- Type filter (live, parallax, etc.)
create index if not exists idx_wallpapers_type
  on public.wallpapers (type)
  where published = true;

-- ---------------------------------------------------------------------------
-- Full-text search (tsvector) — name + description + tags weighted
-- Stored generated column means it's auto-maintained.
-- ---------------------------------------------------------------------------
alter table public.wallpapers
  add column if not exists tsv tsvector
    generated always as (
      setweight(to_tsvector('simple', coalesce(name, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(description, '')), 'B') ||
      setweight(to_tsvector('simple', array_to_string(coalesce(tags, '{}'), ' ')), 'C')
    ) stored;

create index if not exists idx_wallpapers_tsv
  on public.wallpapers using gin(tsv);

comment on column public.wallpapers.tsv is
  'Auto-generated full-text vector. name=A (highest), description=B, tags=C.';

-- ---------------------------------------------------------------------------
-- Trigram index for fuzzy substring search
-- Enables: SELECT * FROM wallpapers WHERE name ILIKE '%dragn%'  (typo-tolerant)
-- ---------------------------------------------------------------------------
create index if not exists idx_wallpapers_name_trgm
  on public.wallpapers using gin(name gin_trgm_ops);
