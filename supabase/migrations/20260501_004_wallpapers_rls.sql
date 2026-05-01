-- =============================================================================
-- Pixora Wallpapers — Row Level Security
-- Migration: 20260501_004_wallpapers_rls
-- Purpose:   Lock down writes; allow public reads only of published rows.
-- =============================================================================

alter table public.wallpapers enable row level security;

-- ---------------------------------------------------------------------------
-- READ: anyone (anon + authenticated) can SELECT published wallpapers.
-- ---------------------------------------------------------------------------
drop policy if exists "wallpapers_read_published" on public.wallpapers;
create policy "wallpapers_read_published"
  on public.wallpapers for select
  using (published = true);

-- ---------------------------------------------------------------------------
-- WRITE: only service_role (admin scripts, Edge Functions w/ secret).
-- The app NEVER has write access — counters bump via SECURITY DEFINER fns.
-- ---------------------------------------------------------------------------
drop policy if exists "wallpapers_admin_write" on public.wallpapers;
create policy "wallpapers_admin_write"
  on public.wallpapers for insert with check ( (auth.jwt()->>'role') = 'service_role' );

drop policy if exists "wallpapers_admin_update" on public.wallpapers;
create policy "wallpapers_admin_update"
  on public.wallpapers for update using ( (auth.jwt()->>'role') = 'service_role' );

drop policy if exists "wallpapers_admin_delete" on public.wallpapers;
create policy "wallpapers_admin_delete"
  on public.wallpapers for delete using ( (auth.jwt()->>'role') = 'service_role' );

-- ---------------------------------------------------------------------------
-- Grants for the analytics functions (anon can call counter bumps)
-- ---------------------------------------------------------------------------
grant execute on function public.wp_increment_view(text)    to anon, authenticated;
grant execute on function public.wp_increment_install(text) to anon, authenticated;
grant execute on function public.wp_increment_share(text)   to anon, authenticated;
grant execute on function public.wp_adjust_favorite(text, int) to anon, authenticated;
grant execute on function public.wp_search(text, wallpaper_category, int, int) to anon, authenticated;
grant execute on function public.wp_storage_base() to anon, authenticated;
-- recompute_trending and stats: admin-only (default — no grant)

-- View access
grant select on public.wallpapers_v to anon, authenticated;
