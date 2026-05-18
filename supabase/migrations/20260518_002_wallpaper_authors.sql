-- Wallpaper authors for the HUD Viewer feature (2026-05-18)
-- Spec: Eduardo's brainstorm 2026-05-17 + HUD Viewer concept #5
--
-- Adds two columns to wallpapers table:
-- - author_name: TEXT, display name (always present, default 'Pixora Studio')
-- - author_user_id: INT, optional FK to a future profiles table
--   (kept nullable for backward compat; not enforced FK until profiles are wired
--   for user-published wallpapers in Phase 2+)

ALTER TABLE public.wallpapers
  ADD COLUMN IF NOT EXISTS author_name TEXT NOT NULL DEFAULT 'Pixora Studio';

ALTER TABLE public.wallpapers
  ADD COLUMN IF NOT EXISTS author_user_id INT;

-- Index for filtering by author (future: show all wallpapers by an author)
CREATE INDEX IF NOT EXISTS idx_wallpapers_author_user_id
  ON public.wallpapers(author_user_id)
  WHERE author_user_id IS NOT NULL;
