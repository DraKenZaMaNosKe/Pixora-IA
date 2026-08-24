// Supabase Edge Function — verify_samsung_purchase
//
// Mirror of verify_google_purchase for Samsung Galaxy Store IAP. Called by the
// samsung flavor's SamsungPurchaseGateway (F3) after a purchase. GATED: until
// SAMSUNG_SERVICE_ACCOUNT_ID + SAMSUNG_API_BASE are configured (commercial
// approval pending), it fails closed with 503 and never grants entitlement.
//
// Client payload: { "purchase_id": "<Samsung purchaseId>", "product_id": "pixora_monthly" }
//
// Env (Supabase secrets, set when Samsung commercial approval lands):
//   SAMSUNG_SERVICE_ACCOUNT_ID  — from Seller Portal > Assistance > API Service
//   SAMSUNG_API_BASE            — Samsung IAP server API base URL
// @ts-ignore — Deno runtime
import { createClient } from 'npm:@supabase/supabase-js@2';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
function errorResponse(code: string, detail: string, status = 400): Response {
  console.error(`[verify_samsung_purchase] ${code}: ${detail}`);
  return jsonResponse({ error: code, detail }, status);
}
function productMeta(productId: string): { tier: string; limit: number } {
  switch (productId) {
    case 'pixora_monthly': return { tier: 'monthly', limit: 100 };
    case 'pixora_quarterly': return { tier: 'quarterly', limit: 400 };
    case 'pixora_yearly': return { tier: 'yearly', limit: 2000 };
    default: return { tier: 'unknown', limit: 100 };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return errorResponse('method_not_allowed', 'Use POST', 405);

  const authHeader = req.headers.get('authorization') ?? '';
  const userJwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!userJwt) return errorResponse('missing_auth', 'Authorization header required', 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const samsungAccountId = Deno.env.get('SAMSUNG_SERVICE_ACCOUNT_ID') ?? '';
  const samsungApiBase = Deno.env.get('SAMSUNG_API_BASE') ?? '';
  if (!supabaseUrl || !serviceRoleKey) return errorResponse('misconfigured', 'Supabase env missing', 500);

  // GATE: fail-closed until Samsung commercial approval provides credentials.
  if (!samsungAccountId || !samsungApiBase) {
    return errorResponse('samsung_not_configured', 'Samsung IAP API not configured yet', 503);
  }

  let body: { purchase_id?: string; product_id?: string };
  try { body = await req.json(); } catch { return errorResponse('invalid_json', 'Body must be JSON'); }
  const { purchase_id, product_id } = body;
  if (!purchase_id || !product_id) return errorResponse('missing_fields', 'purchase_id and product_id required');

  // Identify caller (same pattern as verify_google_purchase).
  let userId: string;
  try {
    const authResp = await fetch(`${supabaseUrl}/auth/v1/user`, {
      method: 'GET', headers: { apikey: serviceRoleKey, authorization: `Bearer ${userJwt}` },
    });
    if (!authResp.ok) return errorResponse('not_authenticated', `auth returned ${authResp.status}`, 401);
    userId = (await authResp.json()).id as string;
    if (!userId) return errorResponse('not_authenticated', 'no id', 401);
  } catch (e) { return errorResponse('not_authenticated', `auth fetch failed: ${e}`, 401); }

  // Verify with Samsung IAP server API (authoritative state).
  // NOTE: exact endpoint/response shape finalized at activation (F3) against
  // Samsung's Subscription API docs; this calls the server and expects a
  // status + expiry. Fail-closed on any error.
  let samsung: Record<string, unknown>;
  try {
    const url = `${samsungApiBase.replace(/\/$/, '')}/subscriptions/${encodeURIComponent(purchase_id)}`;
    const resp = await fetch(url, { headers: { authorization: `Bearer ${samsungAccountId}` } });
    const text = await resp.text();
    if (!resp.ok) throw new Error(`samsung_api_error: ${resp.status} ${text}`);
    samsung = JSON.parse(text);
  } catch (e) { return errorResponse('samsung_verify_failed', String(e), 502); }

  const expiresAtRaw = samsung['expiryTime'] as string | undefined;
  const statusRaw = samsung['status'] as string | undefined; // finalized at F3
  const expiresAt = expiresAtRaw ? new Date(expiresAtRaw).toISOString() : null;
  if (!expiresAt) return errorResponse('missing_expiry', 'Samsung did not return expiry', 502);
  const status = statusRaw === 'CANCELLED' ? 'cancelled'
    : statusRaw === 'EXPIRED' ? 'expired' : 'active';
  const { tier, limit } = productMeta(product_id);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Idempotency by (store, store_transaction_id): reject rebinding someone
  // else's transaction.
  const { data: existing, error: existErr } = await admin
    .from('user_subscriptions')
    .select('id, user_id')
    .eq('store', 'samsung').eq('store_transaction_id', purchase_id)
    .maybeSingle();
  if (existErr) return errorResponse('db_select_failed', existErr.message, 500);
  if (existing && existing.user_id !== userId) {
    return errorResponse('txn_belongs_to_other_user', 'Refusing to rebind', 403);
  }

  // Store-scoped supersede — never touches the user's Play row. Aligned to the
  // live active-sub index predicate (trial/active/in_grace_period/on_hold/paused).
  const { error: supErr } = await admin
    .from('user_subscriptions')
    .update({ status: 'expired', verified_at: new Date().toISOString() })
    .eq('user_id', userId).eq('store', 'samsung')
    .neq('store_transaction_id', purchase_id)
    .in('status', ['trial', 'active', 'in_grace_period', 'on_hold', 'paused']);
  if (supErr) return errorResponse('db_supersede_failed', supErr.message, 500);

  const now = new Date().toISOString();
  const { error: upErr } = await admin.from('user_subscriptions').upsert({
    user_id: userId, product_id, tier, status,
    store: 'samsung', store_transaction_id: purchase_id,
    started_at: now, expires_at: expiresAt,
    trial_ends_at: null, auto_renew: true, verified_at: now,
    generations_limit: limit, period_started_at: now,
    metadata: { raw_response: samsung },
  }, { onConflict: 'store,store_transaction_id' });
  if (upErr) return errorResponse('db_upsert_failed', upErr.message, 500);

  return jsonResponse({ ok: true, status, tier, expires_at: expiresAt });
});
