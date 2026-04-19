-- Refund RPCs + ia-generations storage bucket
-- Shipped 2026-04-19 alongside process_ia_queue Edge Function.
-- These RPCs are called by the worker when Gemini / storage fails, so the
-- user isn't charged for broken generations.

CREATE OR REPLACE FUNCTION public.refund_free_gen(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
BEGIN
  UPDATE public.user_profile
    SET free_gens_remaining = free_gens_remaining + 1
    WHERE user_id = p_user_id;
END; $$;

CREATE OR REPLACE FUNCTION public.refund_subscription_gen(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
BEGIN
  UPDATE public.user_subscriptions
    SET generations_used = GREATEST(generations_used - 1, 0)
    WHERE user_id = p_user_id
      AND status IN ('trial','active','in_grace_period','cancelled')
      AND expires_at > NOW();
END; $$;

CREATE OR REPLACE FUNCTION public.refund_credits(p_user_id uuid, p_amount int, p_queue_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE v_new_balance INT;
BEGIN
  UPDATE public.user_credits SET
    balance = balance + p_amount,
    total_spent = GREATEST(total_spent - p_amount, 0)
    WHERE user_id = p_user_id
    RETURNING balance INTO v_new_balance;
  INSERT INTO public.credits_audit (user_id, delta, new_balance, reason, metadata)
  VALUES (p_user_id, p_amount, v_new_balance, 'ia_generation_refund',
          jsonb_build_object('queue_id', p_queue_id));
END; $$;

-- Only service_role (via Edge Function) should call these; revoke from
-- anon/authenticated so clients can't self-refund arbitrary rows.
REVOKE EXECUTE ON FUNCTION public.refund_free_gen(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.refund_subscription_gen(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.refund_credits(uuid, int, bigint) FROM anon, authenticated;

-- Public bucket for AI-generated images. Public read so <Image.network> in
-- Flutter can hit result_url directly. Writes are restricted to service_role
-- via the Edge Function.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('ia-generations', 'ia-generations', true, 10485760,
        ARRAY['image/png','image/jpeg','image/webp'])
ON CONFLICT (id) DO NOTHING;
