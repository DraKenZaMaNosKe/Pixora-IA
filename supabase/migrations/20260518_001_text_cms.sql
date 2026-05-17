-- Pixora Admin Text CMS — Phase 1 tables (2026-05-18)
-- Spec: docs/superpowers/specs/2026-05-17-text-cms-design.md
--
-- Three normalized tables for the editable string registry.
-- The Flutter app reads via the anon key (RLS allows read).
-- pixora-admin writes via service_role key (no INSERT/UPDATE/DELETE policies,
-- so anon is implicitly blocked from mutating).

CREATE TABLE IF NOT EXISTS public.app_sections (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  order_index INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.app_components (
  id           SERIAL PRIMARY KEY,
  section_id   INT NOT NULL REFERENCES public.app_sections(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  file_path    TEXT,
  description  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(section_id, name)
);

CREATE TABLE IF NOT EXISTS public.app_strings (
  id            SERIAL PRIMARY KEY,
  component_id  INT NOT NULL REFERENCES public.app_components(id) ON DELETE CASCADE,
  key           TEXT NOT NULL UNIQUE,
  es            TEXT NOT NULL,
  en            TEXT NOT NULL,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_strings_component_id ON public.app_strings(component_id);
CREATE INDEX IF NOT EXISTS idx_app_strings_key          ON public.app_strings(key);

ALTER TABLE public.app_sections   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_strings    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon can read sections"   ON public.app_sections;
DROP POLICY IF EXISTS "anon can read components" ON public.app_components;
DROP POLICY IF EXISTS "anon can read strings"    ON public.app_strings;

CREATE POLICY "anon can read sections"
  ON public.app_sections   FOR SELECT TO anon USING (true);
CREATE POLICY "anon can read components"
  ON public.app_components FOR SELECT TO anon USING (true);
CREATE POLICY "anon can read strings"
  ON public.app_strings    FOR SELECT TO anon USING (true);

CREATE OR REPLACE FUNCTION public.bump_app_strings_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_strings_updated_at ON public.app_strings;
CREATE TRIGGER trg_app_strings_updated_at
BEFORE UPDATE ON public.app_strings
FOR EACH ROW EXECUTE FUNCTION public.bump_app_strings_updated_at();
