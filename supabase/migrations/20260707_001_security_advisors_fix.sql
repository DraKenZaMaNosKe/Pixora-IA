-- Security advisors remediation (2026-07-07)
-- Fixes all CRITICAL advisors reported by Supabase for project vzuwvsmlyigjtsearxym.
--
-- Root causes:
--   1. rls_disabled_in_public: policies/profiles/tianguis_items had correct
--      policies defined but RLS was never enabled -> policies never applied,
--      anon could read/write everything (incl. PII: profiles.full_name/phone).
--   2. security_definer_view + auth_users_exposed: all 17 public views run as
--      SECURITY DEFINER and were granted to anon/authenticated. admin_user_stats
--      reaches auth.users. The admin dashboard uses service_role (bypasses RLS),
--      so switching to security_invoker + revoking anon does NOT break it.
--
-- wallpapers_v is intentionally KEPT granted to anon (the Flutter app reads it),
-- but switched to security_invoker so it honors wallpapers RLS
-- (wallpapers_read_published: published = true). 449 published rows remain
-- visible; 5 unpublished drafts become correctly hidden.

BEGIN;

-- 1. Enable RLS where policies already exist ---------------------------------
ALTER TABLE public.policies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tianguis_items ENABLE ROW LEVEL SECURITY;

-- 2. Make every view honor the caller's RLS/permissions ---------------------
ALTER VIEW public.wallpapers_v                 SET (security_invoker = on);
ALTER VIEW public.admin_user_stats             SET (security_invoker = on);
ALTER VIEW public.admin_ad_revenue_daily       SET (security_invoker = on);
ALTER VIEW public.admin_ad_users               SET (security_invoker = on);
ALTER VIEW public.admin_app_event_counts_24h   SET (security_invoker = on);
ALTER VIEW public.admin_app_events_daily       SET (security_invoker = on);
ALTER VIEW public.admin_aura_top_tracks_30d    SET (security_invoker = on);
ALTER VIEW public.admin_content_breakdown      SET (security_invoker = on);
ALTER VIEW public.admin_daily_activity         SET (security_invoker = on);
ALTER VIEW public.admin_event_followers_30d    SET (security_invoker = on);
ALTER VIEW public.admin_pitch_funnel_30d       SET (security_invoker = on);
ALTER VIEW public.admin_tab_views_30d          SET (security_invoker = on);
ALTER VIEW public.admin_terms_acceptance_30d   SET (security_invoker = on);
ALTER VIEW public.admin_top_users_30d          SET (security_invoker = on);
ALTER VIEW public.admin_tutorial_completion_30d SET (security_invoker = on);
ALTER VIEW public.admin_wallpaper_breakdown    SET (security_invoker = on);
ALTER VIEW public.v_reports_pending            SET (security_invoker = on);

-- 3. Revoke anon/authenticated on admin-only views (dashboard uses service_role)
--    wallpapers_v is deliberately NOT revoked (the app needs it).
REVOKE ALL ON
  public.admin_user_stats,
  public.admin_ad_revenue_daily,
  public.admin_ad_users,
  public.admin_app_event_counts_24h,
  public.admin_app_events_daily,
  public.admin_aura_top_tracks_30d,
  public.admin_content_breakdown,
  public.admin_daily_activity,
  public.admin_event_followers_30d,
  public.admin_pitch_funnel_30d,
  public.admin_tab_views_30d,
  public.admin_terms_acceptance_30d,
  public.admin_top_users_30d,
  public.admin_tutorial_completion_30d,
  public.admin_wallpaper_breakdown,
  public.v_reports_pending
  FROM anon, authenticated;

COMMIT;
