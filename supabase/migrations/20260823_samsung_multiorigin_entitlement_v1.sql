-- Pixora: Samsung multi-origin entitlement (F2).
-- Applied via tools/apply_migration.py on 2026-08-23 against project vzuwvsmlyigjtsearxym.
-- Depends on: 20260418_subscriptions_and_ia_queue_v1.sql
-- Backward-compatible: adds columns/keys, extends subscription_status additively.
--
-- LIVE SCHEMA verified 2026-08-23 (schema had drifted from the 20260418 file):
--   * active-sub UNIQUE index is `idx_subs_entitled_user`
--       predicate: (trial, active, in_grace_period, on_hold, paused)  [NOT 'cancelled']
--   * subscription_status RPC == the 20260418 version (unchanged)
--   * purchase_token still UNIQUE (user_subscriptions_purchase_token_key)

BEGIN;

-- 1. store discriminator + generic cross-store transaction id
ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS store TEXT NOT NULL DEFAULT 'play'
    CHECK (store IN ('play','samsung'));
ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS store_transaction_id TEXT;

-- Backfill: existing rows are all Play; give them a generic transaction id
-- equal to their purchase_token so the (store, store_transaction_id) unique
-- applies uniformly. purchase_token stays the Play-specific key.
UPDATE public.user_subscriptions
  SET store_transaction_id = purchase_token
  WHERE store_transaction_id IS NULL AND purchase_token IS NOT NULL;

-- 2. store-aware active-subscription uniqueness (replaces the one-per-user index).
-- Recreate with the SAME predicate the live index uses — only adding `store`
-- to the key so a user may hold one active row PER store.
DROP INDEX IF EXISTS public.idx_subs_entitled_user;
DROP INDEX IF EXISTS public.idx_subs_active_user; -- legacy name, no-op if absent
CREATE UNIQUE INDEX IF NOT EXISTS idx_subs_entitled_user_store
  ON public.user_subscriptions(user_id, store)
  WHERE status IN ('trial','active','in_grace_period','on_hold','paused');

-- 3. cross-store transaction uniqueness (idempotency for client verifies)
CREATE UNIQUE INDEX IF NOT EXISTS idx_subs_store_txn
  ON public.user_subscriptions(store, store_transaction_id)
  WHERE store_transaction_id IS NOT NULL;

-- 4. raw billing events ledger (append-only, idempotent, service-role only)
CREATE TABLE IF NOT EXISTS public.billing_events (
  id           BIGSERIAL PRIMARY KEY,
  store        TEXT NOT NULL CHECK (store IN ('play','samsung')),
  event_id     TEXT NOT NULL,           -- Pub/Sub messageId | ISN JWT jti/notificationId
  raw          JSONB NOT NULL,
  processed_at TIMESTAMPTZ,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (store, event_id)
);
ALTER TABLE public.billing_events ENABLE ROW LEVEL SECURITY;
-- No policies = no anon/authenticated access. Only service_role (bypasses RLS)
-- reads/writes. Intentional: do NOT add a SELECT policy.

-- 5. subscription_status: additive multi-store fields (store, active_stores).
-- Body is the verified-live version + two additive keys. Access predicate
-- (trial,active,in_grace_period,cancelled) is UNCHANGED from live.
CREATE OR REPLACE FUNCTION public.subscription_status()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  sub             public.user_subscriptions;
  free_gens       INT;
  v_active_stores TEXT[];
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('authenticated', false);
  END IF;

  SELECT * INTO sub FROM public.user_subscriptions
  WHERE user_id = auth.uid()
    AND status IN ('trial','active','in_grace_period','cancelled')
    AND expires_at > NOW()
  ORDER BY expires_at DESC
  LIMIT 1;

  SELECT free_gens_remaining INTO free_gens FROM public.user_profile
  WHERE user_id = auth.uid();

  SELECT array_agg(DISTINCT s.store) INTO v_active_stores
  FROM public.user_subscriptions s
  WHERE s.user_id = auth.uid()
    AND s.status IN ('trial','active','in_grace_period','cancelled')
    AND s.expires_at > NOW();

  IF sub.id IS NULL THEN
    RETURN jsonb_build_object(
      'authenticated', true,
      'has_subscription', false,
      'active_stores', COALESCE(v_active_stores, ARRAY[]::text[]),
      'free_gens_remaining', COALESCE(free_gens, 0)
    );
  END IF;

  RETURN jsonb_build_object(
    'authenticated', true,
    'has_subscription', true,
    'sub_id', sub.id,
    'status', sub.status,
    'tier', sub.tier,
    'product_id', sub.product_id,
    'store', sub.store,
    'active_stores', COALESCE(v_active_stores, ARRAY[]::text[]),
    'trial_ends_at', sub.trial_ends_at,
    'expires_at', sub.expires_at,
    'auto_renew', sub.auto_renew,
    'generations_used', sub.generations_used,
    'generations_limit', sub.generations_limit,
    'generations_remaining', GREATEST(sub.generations_limit - sub.generations_used, 0),
    'period_started_at', sub.period_started_at,
    'free_gens_remaining', COALESCE(free_gens, 0)
  );
END;
$$;

COMMIT;
