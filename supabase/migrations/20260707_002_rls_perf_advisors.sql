-- Performance advisors remediation (2026-07-07)
-- 1. auth_rls_initplan: wrap volatile auth.* / is_claims_admin() calls in a
--    scalar subquery so Postgres evaluates them once per query instead of once
--    per row. ALTER POLICY only rewrites the expression; roles/cmd untouched.
-- 2. multiple_permissive_policies: users had two PERMISSIVE SELECT policies for
--    the same role -> consolidate into one with OR (same effective access).

BEGIN;

-- auth_rls_initplan --------------------------------------------------------
ALTER POLICY users_read_own_audit ON public.credits_audit
  USING ((select auth.uid()) = user_id);

ALTER POLICY "Allow admins to manage all tickets" ON public.service_tickets
  USING ((select is_claims_admin()) = true);

ALTER POLICY "Allow authenticated users to create tickets" ON public.service_tickets
  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY "Allow users to view their own tickets" ON public.service_tickets
  USING ((select auth.uid()) = user_id);

ALTER POLICY users_own_credits ON public.user_credits
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY users_own_profile ON public.user_profile
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY users_read_own_sessions ON public.user_sessions
  USING ((select auth.uid()) = user_id);

-- multiple_permissive_policies on users ------------------------------------
DROP POLICY "Allow admins to see all users" ON public.users;
DROP POLICY "Allow users to see their own data" ON public.users;
CREATE POLICY users_select_self_or_admin ON public.users
  FOR SELECT
  USING ((select is_claims_admin()) = true OR (select auth.uid()) = id);

COMMIT;
