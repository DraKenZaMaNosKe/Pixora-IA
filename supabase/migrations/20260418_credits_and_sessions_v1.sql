-- Pixora: cloud-synced diamonds, audit log, user profile & session tracking
-- Applied via Supabase MCP on 2026-04-18 against project vzuwvsmlyigjtsearxym.
-- This file is the canonical source — if you change schema, update both here
-- and the live DB (via apply_migration MCP or the Supabase dashboard).

-- ---- 1. user_credits ----------------------------------------
CREATE TABLE IF NOT EXISTS public.user_credits (
  user_id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance          INT         NOT NULL DEFAULT 0 CHECK (balance >= 0),
  total_earned     INT         NOT NULL DEFAULT 0 CHECK (total_earned >= 0),
  total_spent      INT         NOT NULL DEFAULT 0 CHECK (total_spent >= 0),
  ads_watched      INT         NOT NULL DEFAULT 0 CHECK (ads_watched >= 0),
  earned_today     INT         NOT NULL DEFAULT 0 CHECK (earned_today >= 0),
  last_earn_day    DATE,
  last_earned_at   TIMESTAMPTZ,
  first_earned_at  TIMESTAMPTZ,
  first_spent_at   TIMESTAMPTZ,
  last_spent_at    TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_credits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_credits" ON public.user_credits;
CREATE POLICY "users_own_credits" ON public.user_credits
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---- 2. credits_audit ---------------------------------------
CREATE TABLE IF NOT EXISTS public.credits_audit (
  id           BIGSERIAL    PRIMARY KEY,
  user_id      UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  delta        INT          NOT NULL,
  new_balance  INT          NOT NULL,
  reason       TEXT         NOT NULL,
  metadata     JSONB,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_credits_audit_user ON public.credits_audit(user_id, created_at DESC);

ALTER TABLE public.credits_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_audit" ON public.credits_audit;
CREATE POLICY "users_read_own_audit" ON public.credits_audit
  FOR SELECT USING (auth.uid() = user_id);
-- NOTE: no INSERT/UPDATE/DELETE policy — only SECURITY DEFINER RPCs write here.

-- ---- 3. user_profile (aggregates) ---------------------------
CREATE TABLE IF NOT EXISTS public.user_profile (
  user_id           UUID         PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  first_login_at    TIMESTAMPTZ,
  last_login_at     TIMESTAMPTZ,
  last_active_at    TIMESTAMPTZ,
  login_count       INT          NOT NULL DEFAULT 0 CHECK (login_count >= 0),
  app_version       TEXT,
  device_platform   TEXT,
  locale            TEXT
);

ALTER TABLE public.user_profile ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_profile" ON public.user_profile;
CREATE POLICY "users_own_profile" ON public.user_profile
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---- 4. user_sessions (one row per login) -------------------
CREATE TABLE IF NOT EXISTS public.user_sessions (
  id               BIGSERIAL    PRIMARY KEY,
  user_id          UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  app_version      TEXT,
  device_model     TEXT,
  android_version  TEXT,
  locale           TEXT,
  metadata         JSONB
);
CREATE INDEX IF NOT EXISTS idx_sessions_user_time  ON public.user_sessions(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_time       ON public.user_sessions(started_at DESC);

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_sessions" ON public.user_sessions;
CREATE POLICY "users_read_own_sessions" ON public.user_sessions
  FOR SELECT USING (auth.uid() = user_id);
-- NOTE: writes only via log_session() RPC.

-- ---- 5. auto-updated_at trigger -----------------------------
CREATE OR REPLACE FUNCTION public.bump_updated_at() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_credits_updated_at ON public.user_credits;
CREATE TRIGGER user_credits_updated_at
  BEFORE UPDATE ON public.user_credits
  FOR EACH ROW EXECUTE FUNCTION public.bump_updated_at();

-- ---- 6. RPC: earn_credits ----------------------------------
-- Rate-limited (3s), daily-capped (500), atomic, audited.
CREATE OR REPLACE FUNCTION public.earn_credits(p_amount INT, p_metadata JSONB DEFAULT NULL)
RETURNS public.user_credits
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  result         public.user_credits;
  today          DATE := CURRENT_DATE;
  daily_cap      INT  := 500;
  min_earn       INT  := 1;
  now_ts         TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_amount < min_earn THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  INSERT INTO public.user_credits (user_id)
  VALUES (auth.uid())
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO result FROM public.user_credits
    WHERE user_id = auth.uid() FOR UPDATE;

  IF result.last_earned_at IS NOT NULL AND result.last_earned_at > now_ts - INTERVAL '3 seconds' THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  IF result.last_earn_day = today THEN
    IF result.earned_today + p_amount > daily_cap THEN
      RAISE EXCEPTION 'daily_cap_reached';
    END IF;
  END IF;

  UPDATE public.user_credits SET
    balance         = balance + p_amount,
    total_earned    = total_earned + p_amount,
    ads_watched     = ads_watched + 1,
    earned_today    = CASE WHEN last_earn_day = today THEN earned_today + p_amount ELSE p_amount END,
    last_earn_day   = today,
    last_earned_at  = now_ts,
    first_earned_at = COALESCE(first_earned_at, now_ts)
  WHERE user_id = auth.uid()
  RETURNING * INTO result;

  INSERT INTO public.credits_audit (user_id, delta, new_balance, reason, metadata)
  VALUES (auth.uid(), p_amount, result.balance, 'ad_earn', p_metadata);

  RETURN result;
END;
$$;

-- ---- 7. RPC: spend_credits ----------------------------------
CREATE OR REPLACE FUNCTION public.spend_credits(
  p_amount INT,
  p_reason TEXT,
  p_metadata JSONB DEFAULT NULL
)
RETURNS public.user_credits
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  result public.user_credits;
  now_ts TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_reason IS NULL OR length(p_reason) = 0 THEN
    RAISE EXCEPTION 'missing_reason';
  END IF;

  UPDATE public.user_credits SET
    balance        = balance - p_amount,
    total_spent    = total_spent + p_amount,
    first_spent_at = COALESCE(first_spent_at, now_ts),
    last_spent_at  = now_ts
  WHERE user_id = auth.uid()
    AND balance >= p_amount
  RETURNING * INTO result;

  IF result.user_id IS NULL THEN
    RAISE EXCEPTION 'insufficient_credits';
  END IF;

  INSERT INTO public.credits_audit (user_id, delta, new_balance, reason, metadata)
  VALUES (auth.uid(), -p_amount, result.balance, p_reason, p_metadata);

  RETURN result;
END;
$$;

-- ---- 8. RPC: sync_local_credits (MAX merge on first login) --
CREATE OR REPLACE FUNCTION public.sync_local_credits(
  p_balance INT,
  p_earned INT,
  p_ads INT
)
RETURNS public.user_credits
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  result public.user_credits;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_balance < 0 OR p_earned < 0 OR p_ads < 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  INSERT INTO public.user_credits (user_id, balance, total_earned, ads_watched)
  VALUES (auth.uid(), p_balance, p_earned, p_ads)
  ON CONFLICT (user_id) DO UPDATE SET
    balance      = GREATEST(public.user_credits.balance, EXCLUDED.balance),
    total_earned = GREATEST(public.user_credits.total_earned, EXCLUDED.total_earned),
    ads_watched  = GREATEST(public.user_credits.ads_watched, EXCLUDED.ads_watched)
  RETURNING * INTO result;

  INSERT INTO public.credits_audit (user_id, delta, new_balance, reason, metadata)
  VALUES (auth.uid(), 0, result.balance, 'login_sync',
          jsonb_build_object('local_balance', p_balance, 'merged_balance', result.balance));

  RETURN result;
END;
$$;

-- ---- 9. RPC: log_session (login event) ----------------------
CREATE OR REPLACE FUNCTION public.log_session(
  p_app_version TEXT DEFAULT NULL,
  p_device_model TEXT DEFAULT NULL,
  p_android_version TEXT DEFAULT NULL,
  p_locale TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  session_id BIGINT;
  now_ts     TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  INSERT INTO public.user_sessions (user_id, started_at, app_version, device_model, android_version, locale)
  VALUES (auth.uid(), now_ts, p_app_version, p_device_model, p_android_version, p_locale)
  RETURNING id INTO session_id;

  INSERT INTO public.user_profile
    (user_id, first_login_at, last_login_at, login_count, last_active_at, app_version, device_platform, locale)
  VALUES
    (auth.uid(), now_ts, now_ts, 1, now_ts, p_app_version, 'android', p_locale)
  ON CONFLICT (user_id) DO UPDATE SET
    last_login_at  = now_ts,
    login_count    = public.user_profile.login_count + 1,
    last_active_at = now_ts,
    app_version    = COALESCE(EXCLUDED.app_version, public.user_profile.app_version),
    locale         = COALESCE(EXCLUDED.locale, public.user_profile.locale);

  RETURN session_id;
END;
$$;

-- ---- 10. RPC: heartbeat (mark activity) ---------------------
CREATE OR REPLACE FUNCTION public.heartbeat() RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  UPDATE public.user_profile SET last_active_at = NOW() WHERE user_id = auth.uid();
END;
$$;

-- ---- 11. Grants ---------------------------------------------
GRANT EXECUTE ON FUNCTION public.earn_credits(INT, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.spend_credits(INT, TEXT, JSONB)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_local_credits(INT, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_session(TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.heartbeat()                       TO authenticated;

-- ---- 12. Realtime: enable on user_credits -------------------
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_credits;
