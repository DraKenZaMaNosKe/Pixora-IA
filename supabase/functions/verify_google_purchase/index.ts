// Supabase Edge Function — verify_google_purchase
//
// Called by SubscriptionService after a successful Google Play purchase.
// Validates the purchase_token with Google Play Developer API v3
// (subscriptionsv2 endpoint), then upserts the canonical subscription
// state into public.user_subscriptions.
//
// Client payload:
//   {
//     "purchase_token": "<token from Google Play>",
//     "product_id": "pixora_monthly"
//   }
//
// Required env vars (Supabase secrets):
//   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  — full JSON of a service account with
//                                       "Android Publisher (androidpublisher)"
//                                       role in Play Console.
//   GOOGLE_PLAY_PACKAGE_NAME          — e.g. "com.orbix.pixora"
//
// Auth: the request JWT is the caller's Supabase auth token. We use it to
// identify the user (auth.uid()) before writing to user_subscriptions.

// @ts-ignore — Deno runtime, types resolved at deploy
import { createClient } from 'npm:@supabase/supabase-js@2';

type PurchasePayload = {
  purchase_token: string;
  product_id: string;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  private_key_id?: string;
};

// ── Utilities ────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function errorResponse(code: string, detail: string, status = 400): Response {
  console.error(`[verify_google_purchase] ${code}: ${detail}`);
  return jsonResponse({ error: code, detail }, status);
}

// ── Google OAuth: Service account JWT -> access token ──────────────

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let str = '';
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function importPemKey(pem: string): Promise<CryptoKey> {
  // Strip PEM wrapping, decode base64.
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const bin = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    bin.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT', kid: sa.private_key_id };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`;
  const key = await importPemKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!resp.ok) {
    const t = await resp.text();
    throw new Error(`oauth_exchange_failed: ${resp.status} ${t}`);
  }
  const data = await resp.json();
  return data.access_token as string;
}

// ── Google Play Developer API: subscriptionsv2 get ─────────────────

async function getSubscriptionV2(
  accessToken: string,
  packageName: string,
  token: string,
): Promise<Record<string, unknown>> {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(
    packageName,
  )}/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`;
  console.log(`[play] calling GET ${url.substring(0, 120)}... tokenLen=${token.length} accessTokenLen=${accessToken.length}`);
  const resp = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const bodyText = await resp.text();
  console.log(`[play] response status=${resp.status} bodyLen=${bodyText.length}`);
  if (!resp.ok) {
    console.error(`[play] full body: ${bodyText}`);
    throw new Error(`play_api_error: ${resp.status} ${bodyText}`);
  }
  return JSON.parse(bodyText);
}

// ── Map Google's subscriptionState → our user_subscriptions.status ──

function mapStatus(state: string | undefined): string {
  // Google returns values like SUBSCRIPTION_STATE_ACTIVE,
  // SUBSCRIPTION_STATE_IN_GRACE_PERIOD, etc.
  switch (state) {
    case 'SUBSCRIPTION_STATE_ACTIVE':
      return 'active';
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
      return 'in_grace_period';
    case 'SUBSCRIPTION_STATE_ON_HOLD':
      return 'on_hold';
    case 'SUBSCRIPTION_STATE_PAUSED':
    case 'SUBSCRIPTION_STATE_PAUSE_DEFERRED':
      return 'paused';
    case 'SUBSCRIPTION_STATE_CANCELED':
      return 'cancelled';
    case 'SUBSCRIPTION_STATE_EXPIRED':
      return 'expired';
    default:
      // SUBSCRIPTION_STATE_UNSPECIFIED, SUBSCRIPTION_STATE_PENDING, etc.
      return 'trial';
  }
}

// Product -> (tier, generations_limit). Keep in sync with what we sell.
function productMeta(productId: string): { tier: string; limit: number } {
  switch (productId) {
    case 'pixora_monthly':
      return { tier: 'monthly', limit: 100 };
    case 'pixora_quarterly':
      return { tier: 'quarterly', limit: 400 };
    case 'pixora_yearly':
      return { tier: 'yearly', limit: 2000 };
    default:
      return { tier: 'unknown', limit: 100 };
  }
}

// ── Main handler ───────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return errorResponse('method_not_allowed', 'Use POST', 405);
  }

  // Extract caller identity from the Supabase auth JWT.
  const authHeader = req.headers.get('authorization') ?? '';
  const userJwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!userJwt) {
    return errorResponse('missing_auth', 'Authorization header required', 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const serviceAccountJson = Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON') ?? '';
  const packageName = Deno.env.get('GOOGLE_PLAY_PACKAGE_NAME') ?? '';

  if (!supabaseUrl || !serviceRoleKey) {
    return errorResponse('misconfigured', 'Supabase env missing', 500);
  }
  if (!serviceAccountJson || !packageName) {
    return errorResponse('misconfigured', 'Google Play env missing', 500);
  }

  // Parse payload.
  let body: PurchasePayload;
  try {
    body = await req.json();
  } catch {
    return errorResponse('invalid_json', 'Body must be JSON');
  }
  const { purchase_token, product_id } = body;
  if (!purchase_token || !product_id) {
    return errorResponse(
      'missing_fields',
      'purchase_token and product_id required',
    );
  }

  // Identify the caller via a direct fetch to /auth/v1/user instead of
  // supabase-js's auth.getUser — the npm:@supabase/supabase-js@2 package has
  // compatibility quirks in Deno edge runtime that made getUser() receive
  // HTML from somewhere and throw a JSON parse error. Direct fetch is simpler
  // and immune to library compatibility issues.
  let userId: string;
  try {
    const authResp = await fetch(`${supabaseUrl}/auth/v1/user`, {
      method: 'GET',
      headers: {
        'apikey': serviceRoleKey,
        'authorization': `Bearer ${userJwt}`,
      },
    });
    if (!authResp.ok) {
      const txt = await authResp.text();
      return errorResponse(
        'not_authenticated',
        `auth/v1/user returned ${authResp.status}: ${txt.substring(0, 200)}`,
        401,
      );
    }
    const userJson = await authResp.json();
    userId = userJson.id as string;
    if (!userId) {
      return errorResponse('not_authenticated', 'auth/v1/user returned no id', 401);
    }
  } catch (e) {
    return errorResponse('not_authenticated', `auth fetch failed: ${e}`, 401);
  }

  // Parse service account.
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(serviceAccountJson);
  } catch (e) {
    return errorResponse('bad_service_account', String(e), 500);
  }

  // Verify with Google.
  let play: Record<string, unknown>;
  try {
    const accessToken = await getAccessToken(sa);
    play = await getSubscriptionV2(accessToken, packageName, purchase_token);
  } catch (e) {
    return errorResponse('play_verify_failed', String(e), 502);
  }

  // Extract relevant fields from subscriptionsv2 response.
  // See: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2
  const state = play['subscriptionState'] as string | undefined;
  const lineItems = (play['lineItems'] ?? []) as Array<Record<string, unknown>>;
  const firstLine = lineItems[0] ?? {};
  const expiryTimeRaw = firstLine['expiryTime'] as string | undefined;
  const autoRenewEnabled = Boolean(
    (firstLine['autoRenewingPlan'] as Record<string, unknown> | undefined)
      ?.autoRenewEnabled,
  );
  const offerDetails =
    (firstLine['offerDetails'] as Record<string, unknown> | undefined) ?? {};
  const basePlanId = offerDetails['basePlanId'] as string | undefined;
  const latestOrderId = play['latestOrderId'] as string | undefined;
  const startTimeRaw = play['startTime'] as string | undefined;

  // SECURITY: tier/limit MUST derive from the product Google CONFIRMS in the
  // verified lineItem, never from the client-supplied product_id alone — a
  // client could claim pixora_yearly while buying pixora_monthly and
  // over-grant themselves (entitlement tampering). Reject a mismatch.
  const verifiedProductId = firstLine['productId'] as string | undefined;
  if (verifiedProductId && verifiedProductId !== product_id) {
    return errorResponse('product_mismatch', `client ${product_id} != verified ${verifiedProductId}`, 400);
  }
  const effectiveProductId = verifiedProductId ?? product_id;

  const status = mapStatus(state);
  const { tier, limit } = productMeta(effectiveProductId);
  const expiresAt = expiryTimeRaw ? new Date(expiryTimeRaw).toISOString() : null;
  const startedAt = startTimeRaw ? new Date(startTimeRaw).toISOString() : new Date().toISOString();

  if (!expiresAt) {
    return errorResponse('missing_expiry', 'Play did not return expiryTime', 502);
  }

  // Service-role client for writing user_subscriptions (bypasses RLS).
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Idempotent upsert by purchase_token (unique).
  const { data: existing, error: existErr } = await admin
    .from('user_subscriptions')
    .select('id, user_id, purchase_token')
    .eq('purchase_token', purchase_token)
    .maybeSingle();
  if (existErr) {
    return errorResponse('db_select_failed', existErr.message, 500);
  }
  if (existing && existing.user_id !== userId) {
    // Someone else's purchase_token being verified by this user — refuse.
    return errorResponse(
      'purchase_token_belongs_to_other_user',
      'Refusing to rebind token',
      403,
    );
  }

  // Free the "one active subscription per user" slot before writing the new
  // row. idx_subs_active_user is a partial UNIQUE index on (user_id) WHERE
  // status IN ('trial','active','in_grace_period','cancelled'). A user who
  // re-subscribes after a prior (refunded/cancelled/expired-but-still-flagged)
  // purchase has a DIFFERENT purchase_token, so a plain insert of the new
  // active row collides with the stale one. Supersede any other blocking row
  // for this user first. 'expired' is outside the index predicate, so the
  // stale row leaves the unique slot while its history is preserved.
  const { error: supersedeErr } = await admin
    .from('user_subscriptions')
    .update({ status: 'expired', verified_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('store', 'play')
    .neq('purchase_token', purchase_token)
    .in('status', ['trial', 'active', 'in_grace_period', 'on_hold', 'paused']);
  if (supersedeErr) {
    return errorResponse('db_supersede_failed', supersedeErr.message, 500);
  }

  const row = {
    user_id: userId,
    product_id: effectiveProductId,
    tier,
    status,
    started_at: startedAt,
    expires_at: expiresAt,
    trial_ends_at: status === 'trial' ? expiresAt : null,
    auto_renew: autoRenewEnabled,
    purchase_token,
    store: 'play',
    store_transaction_id: purchase_token,
    order_id: latestOrderId ?? null,
    verified_at: new Date().toISOString(),
    generations_limit: limit,
    period_started_at: startedAt,
    metadata: {
      base_plan_id: basePlanId,
      raw_response: play,
    },
  };

  const { error: upsertErr } = await admin
    .from('user_subscriptions')
    .upsert(row, { onConflict: 'purchase_token' });
  if (upsertErr) {
    return errorResponse('db_upsert_failed', upsertErr.message, 500);
  }

  return jsonResponse({
    ok: true,
    status,
    tier,
    expires_at: expiresAt,
    auto_renew: autoRenewEnabled,
  });
});
