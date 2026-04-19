-- Pixora: subscriptions + IA generation queue + account deletion
-- Applied via Supabase MCP on 2026-04-18 against project vzuwvsmlyigjtsearxym.
-- Depends on: 20260418_credits_and_sessions_v1.sql
-- This file is the canonical source — if you change schema, update both here
-- and the live DB (via apply_migration MCP or the Supabase dashboard).

-- ---- 1. user_subscriptions ----------------------------------
CREATE TABLE IF NOT EXISTS public.user_subscriptions (
  id                  BIGSERIAL PRIMARY KEY,
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  product_id          TEXT NOT NULL,          -- Play Console SKU, e.g. 'pixora_monthly'
  tier                TEXT NOT NULL,          -- 'monthly' | 'quarterly' | 'yearly'

  status              TEXT NOT NULL DEFAULT 'trial'
                      CHECK (status IN (
                        'trial', 'active', 'in_grace_period', 'on_hold',
                        'paused', 'cancelled', 'expired', 'refunded'
                      )),

  started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  trial_ends_at       TIMESTAMPTZ,
  expires_at          TIMESTAMPTZ NOT NULL,
  cancelled_at        TIMESTAMPTZ,
  renewed_at          TIMESTAMPTZ,

  purchase_token      TEXT UNIQUE,
  order_id            TEXT,
  verified_at         TIMESTAMPTZ,

  generations_used    INT NOT NULL DEFAULT 0 CHECK (generations_used >= 0),
  generations_limit   INT NOT NULL DEFAULT 100,
  period_started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  auto_renew          BOOLEAN NOT NULL DEFAULT TRUE,
  cancel_reason       TEXT,
  metadata            JSONB,                   -- raw Google receipt + any extras

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_subs_active_user
  ON public.user_subscriptions(user_id)
  WHERE status IN ('trial','active','in_grace_period','cancelled');

CREATE INDEX IF NOT EXISTS idx_subs_expires
  ON public.user_subscriptions(expires_at)
  WHERE status IN ('trial','active');

ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_sub" ON public.user_subscriptions;
CREATE POLICY "users_read_own_sub" ON public.user_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

-- ---- 2. ia_generation_queue ---------------------------------
CREATE TABLE IF NOT EXISTS public.ia_generation_queue (
  id                BIGSERIAL PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  prompt            TEXT NOT NULL,
  style             TEXT,
  reference_url     TEXT,
  model             TEXT NOT NULL DEFAULT 'gemini_flash',

  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','processing','done','failed','cancelled')),

  result_url        TEXT,
  thumbnail_url     TEXT,
  error_code        TEXT,
  error_message     TEXT,

  prompt_safe       BOOLEAN,
  output_safe       BOOLEAN,

  credits_charged   INT NOT NULL DEFAULT 30 CHECK (credits_charged >= 0),
  source            TEXT NOT NULL
                    CHECK (source IN ('free_trial_gen','subscription_quota','credits_extra')),

  retention_until   TIMESTAMPTZ,              -- NULL = forever (subscribers); else 90d

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ,

  metadata          JSONB
);

CREATE INDEX IF NOT EXISTS idx_queue_pending
  ON public.ia_generation_queue(created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_queue_user
  ON public.ia_generation_queue(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_queue_retention
  ON public.ia_generation_queue(retention_until) WHERE retention_until IS NOT NULL;

ALTER TABLE public.ia_generation_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_queue" ON public.ia_generation_queue;
CREATE POLICY "users_read_own_queue" ON public.ia_generation_queue
  FOR SELECT USING (auth.uid() = user_id);

ALTER PUBLICATION supabase_realtime ADD TABLE public.ia_generation_queue;
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_subscriptions;

-- ---- 3. user_profile: free_gens_remaining -------------------
ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS free_gens_remaining INT NOT NULL DEFAULT 2
  CHECK (free_gens_remaining >= 0);

-- ---- 4. Moderation blocklist --------------------------------
CREATE TABLE IF NOT EXISTS public.moderation_blocklist (
  term        TEXT PRIMARY KEY,
  locale      TEXT,
  severity    TEXT NOT NULL DEFAULT 'block'
              CHECK (severity IN ('block','flag')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes       TEXT
);
ALTER TABLE public.moderation_blocklist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "authenticated_read_blocklist" ON public.moderation_blocklist;
CREATE POLICY "authenticated_read_blocklist" ON public.moderation_blocklist
  FOR SELECT USING (auth.uid() IS NOT NULL);

INSERT INTO public.moderation_blocklist (term, locale, severity, notes) VALUES
  ('child porn', 'en', 'block', 'obvious CSAM'),
  ('cp', 'en', 'block', 'CSAM abbreviation'),
  ('csam', 'en', 'block', 'CSAM abbreviation'),
  ('pornografia infantil', 'es', 'block', 'obvious CSAM'),
  ('menor de edad desnudo', 'es', 'block', 'CSAM'),
  ('loli', null, 'block', 'CSAM code'),
  ('shota', null, 'block', 'CSAM code'),
  ('nude child', 'en', 'block', 'CSAM'),
  ('niño desnudo', 'es', 'block', 'CSAM'),
  ('niña desnuda', 'es', 'block', 'CSAM'),
  ('bestiality', 'en', 'block', 'banned content'),
  ('zoofilia', 'es', 'block', 'banned content'),
  ('snuff', 'en', 'block', 'banned content'),
  ('gore extremo', 'es', 'flag', 'review'),
  ('explicit gore', 'en', 'flag', 'review')
ON CONFLICT (term) DO NOTHING;

-- ---- 5. Trigger ---------------------------------------------
DROP TRIGGER IF EXISTS user_subs_updated_at ON public.user_subscriptions;
CREATE TRIGGER user_subs_updated_at
  BEFORE UPDATE ON public.user_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.bump_updated_at();

-- ---- 6. RPC: subscription_status ----------------------------
CREATE OR REPLACE FUNCTION public.subscription_status()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  sub       public.user_subscriptions;
  free_gens INT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('authenticated', false);
  END IF;

  SELECT * INTO sub FROM public.user_subscriptions
  WHERE user_id = auth.uid()
    AND status IN ('trial','active','in_grace_period','cancelled')
    AND expires_at > NOW()
  ORDER BY expires_at DESC LIMIT 1;

  SELECT free_gens_remaining INTO free_gens FROM public.user_profile
  WHERE user_id = auth.uid();

  IF sub.id IS NULL THEN
    RETURN jsonb_build_object(
      'authenticated', true,
      'has_subscription', false,
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

-- ---- 7. Moderation helper -----------------------------------
CREATE OR REPLACE FUNCTION public.is_prompt_blocked(p_prompt TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  lower_prompt TEXT := lower(p_prompt);
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.moderation_blocklist
    WHERE severity = 'block'
      AND position(term IN lower_prompt) > 0
  );
END;
$$;

-- ---- 8. RPC: enqueue_generation -----------------------------
CREATE OR REPLACE FUNCTION public.enqueue_generation(
  p_prompt        TEXT,
  p_style         TEXT DEFAULT NULL,
  p_reference_url TEXT DEFAULT NULL,
  p_model         TEXT DEFAULT 'gemini_flash'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id        UUID := auth.uid();
  v_free_gens      INT;
  v_sub            public.user_subscriptions;
  v_credits        INT;
  v_source         TEXT;
  v_daily_count    INT;
  v_pending_count  INT;
  v_queue_id       BIGINT;
  v_cost_credits   INT := 30;
  v_retention      TIMESTAMPTZ;
  v_now            TIMESTAMPTZ := NOW();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_prompt IS NULL OR length(trim(p_prompt)) < 3 THEN RAISE EXCEPTION 'prompt_too_short'; END IF;
  IF length(p_prompt) > 1000 THEN RAISE EXCEPTION 'prompt_too_long'; END IF;

  IF public.is_prompt_blocked(p_prompt) THEN
    RAISE EXCEPTION 'prompt_blocked_moderation';
  END IF;

  SELECT COUNT(*) INTO v_pending_count FROM public.ia_generation_queue
  WHERE user_id = v_user_id AND status IN ('pending','processing');
  IF v_pending_count >= 5 THEN RAISE EXCEPTION 'too_many_pending'; END IF;

  SELECT COUNT(*) INTO v_daily_count FROM public.ia_generation_queue
  WHERE user_id = v_user_id
    AND created_at > v_now - INTERVAL '24 hours'
    AND status IN ('pending','processing','done');
  IF v_daily_count >= 20 THEN RAISE EXCEPTION 'daily_cap_reached'; END IF;

  SELECT free_gens_remaining INTO v_free_gens FROM public.user_profile
  WHERE user_id = v_user_id FOR UPDATE;

  IF v_free_gens > 0 THEN
    v_source := 'free_trial_gen';
    UPDATE public.user_profile
      SET free_gens_remaining = free_gens_remaining - 1
      WHERE user_id = v_user_id;
  ELSE
    SELECT * INTO v_sub FROM public.user_subscriptions
    WHERE user_id = v_user_id
      AND status IN ('trial','active','in_grace_period','cancelled')
      AND expires_at > v_now
    ORDER BY expires_at DESC LIMIT 1 FOR UPDATE;

    IF v_sub.id IS NOT NULL AND v_sub.generations_used < v_sub.generations_limit THEN
      v_source := 'subscription_quota';
      UPDATE public.user_subscriptions
        SET generations_used = generations_used + 1
        WHERE id = v_sub.id;
    ELSE
      IF v_sub.id IS NULL THEN RAISE EXCEPTION 'subscription_required'; END IF;

      v_source := 'credits_extra';
      SELECT balance INTO v_credits FROM public.user_credits
      WHERE user_id = v_user_id FOR UPDATE;

      IF v_credits IS NULL OR v_credits < v_cost_credits THEN
        RAISE EXCEPTION 'insufficient_credits';
      END IF;

      UPDATE public.user_credits SET
        balance = balance - v_cost_credits,
        total_spent = total_spent + v_cost_credits,
        first_spent_at = COALESCE(first_spent_at, v_now),
        last_spent_at = v_now
      WHERE user_id = v_user_id;

      INSERT INTO public.credits_audit (user_id, delta, new_balance, reason, metadata)
      VALUES (v_user_id, -v_cost_credits, v_credits - v_cost_credits,
              'ia_generation_extra', jsonb_build_object('model', p_model));
    END IF;
  END IF;

  IF v_sub.id IS NOT NULL THEN
    v_retention := NULL;
  ELSE
    v_retention := v_now + INTERVAL '90 days';
  END IF;

  INSERT INTO public.ia_generation_queue
    (user_id, prompt, style, reference_url, model, source, credits_charged, retention_until, prompt_safe)
  VALUES
    (v_user_id, p_prompt, p_style, p_reference_url, p_model, v_source,
     CASE WHEN v_source = 'credits_extra' THEN v_cost_credits ELSE 0 END,
     v_retention, true)
  RETURNING id INTO v_queue_id;

  RETURN jsonb_build_object(
    'queue_id', v_queue_id,
    'source', v_source,
    'status', 'pending',
    'free_gens_remaining', COALESCE(v_free_gens - CASE WHEN v_source='free_trial_gen' THEN 1 ELSE 0 END, 0)
  );
END;
$$;

-- ---- 9. RPC: cancel_generation ------------------------------
CREATE OR REPLACE FUNCTION public.cancel_generation(p_queue_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.ia_generation_queue;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  UPDATE public.ia_generation_queue
    SET status = 'cancelled', completed_at = v_now
    WHERE id = p_queue_id AND user_id = auth.uid() AND status = 'pending'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN RAISE EXCEPTION 'not_cancellable'; END IF;

  IF v_row.source = 'free_trial_gen' THEN
    UPDATE public.user_profile
      SET free_gens_remaining = free_gens_remaining + 1
      WHERE user_id = v_row.user_id;
  ELSIF v_row.source = 'subscription_quota' THEN
    UPDATE public.user_subscriptions
      SET generations_used = GREATEST(generations_used - 1, 0)
      WHERE user_id = v_row.user_id
        AND status IN ('trial','active','in_grace_period','cancelled')
        AND expires_at > v_now;
  ELSIF v_row.source = 'credits_extra' AND v_row.credits_charged > 0 THEN
    UPDATE public.user_credits SET
      balance = balance + v_row.credits_charged,
      total_spent = GREATEST(total_spent - v_row.credits_charged, 0)
    WHERE user_id = v_row.user_id;
    INSERT INTO public.credits_audit (user_id, delta, new_balance, reason, metadata)
    SELECT v_row.user_id, v_row.credits_charged, uc.balance, 'ia_generation_refund',
           jsonb_build_object('queue_id', v_row.id)
    FROM public.user_credits uc WHERE uc.user_id = v_row.user_id;
  END IF;

  RETURN jsonb_build_object('queue_id', v_row.id, 'refunded_source', v_row.source);
END;
$$;

-- ---- 10. RPC: delete_my_account (Play Store compliance) -----
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_has_active_sub BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_subscriptions
    WHERE user_id = v_user_id
      AND status IN ('trial','active','in_grace_period')
      AND expires_at > NOW()
  ) INTO v_has_active_sub;

  IF v_has_active_sub THEN
    RAISE EXCEPTION 'active_subscription_cancel_first';
  END IF;

  DELETE FROM auth.users WHERE id = v_user_id;

  RETURN jsonb_build_object('deleted', true);
END;
$$;

-- ---- 11. Grants ---------------------------------------------
GRANT EXECUTE ON FUNCTION public.subscription_status()                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_prompt_blocked(TEXT)                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_generation(TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_generation(BIGINT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_account()                        TO authenticated;
