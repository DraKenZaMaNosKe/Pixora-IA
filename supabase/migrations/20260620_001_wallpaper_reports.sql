-- 2026-06-20 — Wallpaper Reports (Google Play AI content policy compliance)
--
-- Google Play rejected v1.7.28 by "Política de contenido generado por IA"
-- because the app didn't include a way for users to flag offensive content.
-- This migration adds the backend so the in-app "Reportar contenido"
-- button (added in v1.7.30) can persist a report.
--
-- Schema:
--   wallpaper_reports  — one row per user report
--   v_reports_pending  — admin view (joins wallpaper meta + count)
--   public.report_wallpaper(...)  — RPC the Flutter app calls
--   public.resolve_report(...)    — RPC the admin dashboard calls

-- ─────────────────────────────────────────────────────────────────────
-- TABLE
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.wallpaper_reports (
    id              uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    wallpaper_id    text NOT NULL,
    wallpaper_kind  text NOT NULL,            -- static | live | canvas_scene | ai_generated | panoramic | story | tone
    reason          text NOT NULL,            -- sexual | violence | hate | copyright | drugs | spam | other
    description     text,                     -- optional free-text from user
    reporter_id     text,                     -- supabase user_id if signed-in, else device_id
    reporter_email  text,                     -- only when signed-in
    wallpaper_meta  jsonb,                    -- snapshot of name/url/category so we can evaluate even if wallpaper is later removed
    status          text NOT NULL DEFAULT 'pending'  -- pending | reviewed | removed | dismissed
                    CHECK (status IN ('pending', 'reviewed', 'removed', 'dismissed')),
    reported_at     timestamptz NOT NULL DEFAULT now(),
    resolved_at     timestamptz,
    admin_notes     text
);

CREATE INDEX IF NOT EXISTS idx_wallpaper_reports_status
    ON public.wallpaper_reports (status, reported_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallpaper_reports_wallpaper
    ON public.wallpaper_reports (wallpaper_id);

-- Anti-spam: same reporter cannot report the same wallpaper twice within 24h.
-- Plain unique on (wallpaper_id, reporter_id) would block ALL repeats; the
-- 24h gate gives the user a chance to flag again if the content changes.
-- Enforced in RPC, not as constraint, so admin moderation isn't restricted.

-- ─────────────────────────────────────────────────────────────────────
-- RPC: report_wallpaper — called from the Flutter app
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.report_wallpaper(
    p_wallpaper_id    text,
    p_wallpaper_kind  text,
    p_reason          text,
    p_description     text DEFAULT NULL,
    p_reporter_id     text DEFAULT NULL,
    p_reporter_email  text DEFAULT NULL,
    p_wallpaper_meta  jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recent_count int;
    v_id uuid;
BEGIN
    -- Validate reason against allowed enum
    IF p_reason NOT IN ('sexual', 'violence', 'hate', 'copyright', 'drugs', 'spam', 'other') THEN
        RAISE EXCEPTION 'invalid reason: %', p_reason;
    END IF;

    -- Validate kind
    IF p_wallpaper_kind NOT IN ('static', 'live', 'canvas_scene', 'ai_generated', 'panoramic', 'story', 'tone') THEN
        RAISE EXCEPTION 'invalid wallpaper_kind: %', p_wallpaper_kind;
    END IF;

    -- Anti-spam: same reporter cannot report the same wallpaper twice in 24h.
    -- Silently return existing report id so the UI can show "ya lo reportaste".
    IF p_reporter_id IS NOT NULL THEN
        SELECT id INTO v_id
        FROM public.wallpaper_reports
        WHERE wallpaper_id = p_wallpaper_id
          AND reporter_id  = p_reporter_id
          AND reported_at > now() - interval '24 hours'
        LIMIT 1;

        IF v_id IS NOT NULL THEN
            RETURN v_id;
        END IF;
    END IF;

    INSERT INTO public.wallpaper_reports (
        wallpaper_id, wallpaper_kind, reason, description,
        reporter_id, reporter_email, wallpaper_meta
    ) VALUES (
        p_wallpaper_id, p_wallpaper_kind, p_reason, p_description,
        p_reporter_id, p_reporter_email, p_wallpaper_meta
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- RPC: resolve_report — called from admin dashboard
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.resolve_report(
    p_report_id   uuid,
    p_status      text,                 -- reviewed | removed | dismissed
    p_admin_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_status NOT IN ('reviewed', 'removed', 'dismissed') THEN
        RAISE EXCEPTION 'invalid status: %', p_status;
    END IF;

    UPDATE public.wallpaper_reports
    SET status      = p_status,
        admin_notes = p_admin_notes,
        resolved_at = now()
    WHERE id = p_report_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- VIEW: v_reports_pending (admin dashboard)
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_reports_pending AS
SELECT
    r.id,
    r.wallpaper_id,
    r.wallpaper_kind,
    r.reason,
    r.description,
    r.reporter_id,
    r.reporter_email,
    r.wallpaper_meta,
    r.status,
    r.reported_at,
    r.resolved_at,
    r.admin_notes,
    -- How many distinct reporters flagged this same wallpaper (any reason)
    (SELECT count(DISTINCT reporter_id)
       FROM public.wallpaper_reports r2
       WHERE r2.wallpaper_id = r.wallpaper_id
         AND r2.status IN ('pending', 'reviewed')) AS distinct_reporter_count
FROM public.wallpaper_reports r
WHERE r.status = 'pending'
ORDER BY r.reported_at DESC;

-- ─────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.wallpaper_reports ENABLE ROW LEVEL SECURITY;

-- Anyone (including anon) can INSERT through the RPC. The table itself
-- stays locked for direct SELECT — only the RPC + admin (service role)
-- can read. This prevents users from scraping which wallpapers others
-- flagged and for what reason.

DROP POLICY IF EXISTS reports_no_direct_select ON public.wallpaper_reports;
DROP POLICY IF EXISTS reports_no_direct_insert ON public.wallpaper_reports;

-- No direct insert/select from anon or authenticated — must go through RPC.
-- Service role bypasses RLS so the admin dashboard sees everything.

GRANT EXECUTE ON FUNCTION public.report_wallpaper(text, text, text, text, text, text, jsonb)
    TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.resolve_report(uuid, text, text)
    TO service_role;

GRANT SELECT ON public.v_reports_pending TO service_role;
