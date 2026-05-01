-- =============================================================================
-- Pixora Wallpapers — Core Schema
-- Migration: 20260501_001_wallpapers_schema
-- Author:    Pixora team
-- Purpose:   Replace catalog.json with a queryable, indexed Postgres table.
-- Reversible: yes (drop table cascade — see 20260501_999_rollback.sql)
--
-- Design principles:
--   1. Maintainability > cleverness. Every column/function has COMMENT ON.
--   2. Idempotent: safe to re-run (CREATE IF NOT EXISTS, ON CONFLICT).
--   3. Explicit constraints — Postgres rejects bad data, not the app.
--   4. RLS enforced — no sensitive ops without service_role.
--   5. Generated cols / triggers do the work the app shouldn't repeat.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions (Supabase has these but we're explicit)
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto;       -- gen_random_uuid()
create extension if not exists pg_trgm;        -- fuzzy substring search
-- pgvector added in Tier 2 migration (semantic search)

-- ---------------------------------------------------------------------------
-- Enums — type-safe categories & types
-- ---------------------------------------------------------------------------
do $$ begin
  create type wallpaper_type as enum (
    'static',         -- single static image (most common)
    'live_video',     -- mp4 live wallpaper
    'parallax',       -- canvas_scene 3D parallax (gyro-reactive)
    'shader',         -- shader-based (GLSL)
    'day_cycle',      -- 4-frame day cycle (morning/afternoon/evening/night)
    'story',          -- multi-frame story
    'panoramic'       -- ultra-wide (4192x1024)
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type wallpaper_category as enum (
    'WALLPAPERS','PANORAMIC','NATURE','ANIME','GAMING','MISC',
    'CALENDAR','ART','FANTASY','SCIFI','CULTURE','SCENES','SPECIAL',
    'CHRISTMAS','HORROR','ANIMALS','LIFESTYLE','UNIVERSE','DARK','AURA'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type wallpaper_badge as enum ('NEW','HOT','PRO','FREE','LIMITED','BETA');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Main table
-- ---------------------------------------------------------------------------
create table if not exists public.wallpapers (
  -- IDENTITY
  id              text primary key
                    check (id ~ '^[a-z0-9_-]+$' and length(id) between 2 and 80),

  -- CORE CONTENT
  name            text not null check (length(name) between 1 and 120),
  description     text not null check (length(description) between 1 and 500),
  type            wallpaper_type not null default 'static',
  category        wallpaper_category not null,
  tags            text[] not null default '{}'
                    check (cardinality(tags) <= 25),

  -- FILE REFERENCES (relative paths inside `wallpaper-images` bucket)
  image_path      text not null check (length(image_path) <= 200),
  preview_path    text not null check (length(preview_path) <= 200),
  image_size      int  check (image_size  > 0 and image_size  < 50_000_000),
  preview_size    int  check (preview_size > 0 and preview_size < 1_000_000),

  -- VISUAL METADATA
  glow_color      text check (glow_color ~ '^#[0-9A-Fa-f]{6}$'),
  badge           wallpaper_badge,

  -- RANKING / SORT
  sort_order      int  not null default 1000,
  featured        boolean not null default false,
  trending_score  real not null default 0.0,

  -- COUNTERS (incremented by Edge Function via SECURITY DEFINER fns)
  view_count      bigint not null default 0 check (view_count      >= 0),
  install_count   bigint not null default 0 check (install_count   >= 0),
  share_count     bigint not null default 0 check (share_count     >= 0),
  favorite_count  bigint not null default 0 check (favorite_count  >= 0),

  -- AUDIT / LIFECYCLE
  published       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  last_viewed_at      timestamptz,
  last_installed_at   timestamptz
);

-- ---------------------------------------------------------------------------
-- COMMENT ON for self-documentation (visible in Supabase Studio)
-- ---------------------------------------------------------------------------
comment on table  public.wallpapers is
  'Canonical catalog of wallpapers, live wallpapers, and parallax scenes shown in Pixora.';
comment on column public.wallpapers.id is
  'Snake-case slug (e.g. ryu_vs_ken). Stable forever — changing breaks favorites & analytics.';
comment on column public.wallpapers.name is
  'User-facing display name. Update freely; the id is the stable key.';
comment on column public.wallpapers.description is
  'Short copy shown on detail card. Must accurately describe visual content (audited 2026-04-30).';
comment on column public.wallpapers.tags is
  'Lowercase keywords for filtering & search. Max 25.';
comment on column public.wallpapers.image_path is
  'Relative path inside wallpaper-images bucket. Full URL = storage_base + image_path.';
comment on column public.wallpapers.preview_path is
  'Same as image_path but for low-res preview (<50KB).';
comment on column public.wallpapers.glow_color is
  'Hex accent color for card glow effect. Format: #RRGGBB.';
comment on column public.wallpapers.sort_order is
  'Lower = appears first inside its category. Override featured ordering.';
comment on column public.wallpapers.featured is
  'If true, appears in the home featured carousel.';
comment on column public.wallpapers.trending_score is
  'Computed by recompute_trending_scores() — see 003_functions.sql.';
comment on column public.wallpapers.published is
  'If false, hidden from the app entirely. Use to soft-delete duplicates without losing analytics.';

-- ---------------------------------------------------------------------------
-- updated_at trigger — automatic on every UPDATE
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end$$;

drop trigger if exists trg_wallpapers_updated_at on public.wallpapers;
create trigger trg_wallpapers_updated_at
  before update on public.wallpapers
  for each row execute function public.set_updated_at();

comment on function public.set_updated_at() is
  'Generic updated_at autosetter. Reusable for other tables.';
