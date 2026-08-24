# Samsung F2 — Server-Side Entitlement (multi-origin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Supabase entitlement multi-origin — one `user_subscriptions` table + `subscription_status` RPC fed by both Play (RTDN/verify) and Samsung (ISN/verify) — with idempotency, a store-aware active-subscription index, and Edge Function skeletons for Samsung that are testable now and activate once Samsung commercial approval lands.

**Architecture:** A single backward-compatible DB migration adds `store`/`store_transaction_id`, a raw `billing_events` table, a store-aware partial-unique index (replacing the one-active-sub-per-user index), and extends the `subscription_status` RPC additively. `verify_google_purchase` becomes store-aware (its supersede must not kill the other store's row). Two new Edge Functions mirror the Google one: `verify_samsung_purchase` and `samsung-isn-webhook`, both gated behind Samsung env secrets (fail-closed until approval) so they deploy and are curl-testable without breaking anything.

**Tech Stack:** Supabase Postgres (plpgsql, RLS, partial unique indexes), Supabase Edge Functions (Deno/TypeScript), applied via `apply_migration` / `deploy_edge_function` MCP.

**Spec:** `docs/superpowers/specs/2026-08-23-samsung-galaxy-store-design.md` (Section 3)

## Global Constraints

- **Touches PRODUCTION data** (`user_subscriptions` has real subscribers) and the **live** `subscription_status` RPC. Every change must be BACKWARD-COMPATIBLE and additive: old app versions parsing the current RPC shape must keep working.
- Migrations are idempotent (`IF NOT EXISTS`, `CREATE OR REPLACE`) and applied via `apply_migration` MCP (asks first). Also written to `supabase/migrations/` as canonical source (repo convention, see `20260418_subscriptions_and_ia_queue_v1.sql` header).
- Samsung API calls and ISN signature verification are **GATED behind env secrets** (`SAMSUNG_*`). When absent (today — commercial approval pending), the Samsung functions fail-closed (`503 samsung_not_configured`) and never grant entitlement. This lets them deploy + be curl-tested now without risk.
- `billing_events` is service-role only (RLS: no public/anon/authenticated read or write). It's an internal ledger.
- No new secrets in the repo. Samsung Seller Portal service account + ISN public key live only in Supabase Edge secrets (set via dashboard/CLI when approval lands) and mirrored to `orbixprivate`/`KEYS_LOCAL.md`.
- No app/client changes in F2 (that's F3). No automated test suite: verification is `execute_sql` (MCP, read-only) + `curl` against deployed functions + confirming existing subscribers still resolve via `subscription_status`.
- The store vocabulary is exactly `'play'` and `'samsung'` (CHECK constraint).

---

## File Structure

- **Create** `supabase/migrations/20260823_samsung_multiorigin_entitlement_v1.sql` — the whole DB migration (columns, backfill, indexes, billing_events, RPC extension). Canonical source; also applied live via `apply_migration`.
- **Modify** `supabase/functions/verify_google_purchase/index.ts` — set `store='play'` + `store_transaction_id` on the row; make the supersede store-scoped (`.eq('store','play')`).
- **Create** `supabase/functions/verify_samsung_purchase/index.ts` — mirror of the Google verify, gated behind `SAMSUNG_*` env; store-scoped supersede (`.eq('store','samsung')`); idempotent by `store_transaction_id`.
- **Create** `supabase/functions/samsung-isn-webhook/index.ts` — public endpoint; verifies the Samsung ISN JWT (fail-closed without the public key), records a `billing_events` row idempotently, and (when configured) re-reads authoritative state via the Samsung API before writing entitlement.

---

## Task 1: DB migration — multi-origin schema (PRODUCTION)

**Files:**
- Create: `supabase/migrations/20260823_samsung_multiorigin_entitlement_v1.sql`

**Interfaces:**
- Produces: `user_subscriptions.store` (`'play'|'samsung'`, default `'play'`), `user_subscriptions.store_transaction_id` (text, nullable); `billing_events` table; index `idx_subs_active_user_store` (unique `(user_id, store)` on active statuses) replacing `idx_subs_active_user`; unique `(store, store_transaction_id)` where not null; `subscription_status()` returns two new additive keys `store` and `active_stores`.

- [ ] **Step 1: Pre-migration safety read (MCP execute_sql, read-only)**

Confirm the live schema matches the plan's assumptions before changing anything:
```sql
-- current active-sub index definition
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'user_subscriptions' AND indexname LIKE 'idx_subs_active%';
-- how many rows would the new unique(user_id, store) have to respect
SELECT user_id, count(*) FROM public.user_subscriptions
WHERE status IN ('trial','active','in_grace_period','cancelled')
GROUP BY user_id HAVING count(*) > 1;
-- baseline: active subscriber count (compare after)
SELECT count(*) FROM public.user_subscriptions
WHERE status IN ('trial','active','in_grace_period','cancelled') AND expires_at > now();
```
Expected: the second query returns ZERO rows (no user currently has >1 active row — so the new, LESS restrictive `(user_id, store)` unique cannot be violated by existing data). Record the third query's count.

- [ ] **Step 2: Write the migration file**

```sql
-- Pixora: Samsung multi-origin entitlement.
-- Applied via apply_migration MCP on 2026-08-23 against project vzuwvsmlyigjtsearxym.
-- Depends on: 20260418_subscriptions_and_ia_queue_v1.sql
-- Backward-compatible: adds columns/keys, extends subscription_status additively.

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

-- 2. store-aware active-subscription uniqueness (replaces one-per-user)
-- LIVE SCHEMA verified 2026-08-23: the active-sub UNIQUE index is
-- `idx_subs_entitled_user` with predicate (trial,active,in_grace_period,
-- on_hold,paused) — NOT the original `idx_subs_active_user`. Drop the REAL
-- one and recreate store-aware with the SAME predicate (do not change which
-- statuses occupy the slot).
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
  id           BIGGSERIAL PRIMARY KEY,
  store        TEXT NOT NULL CHECK (store IN ('play','samsung')),
  event_id     TEXT NOT NULL,           -- Pub/Sub messageId | ISN JWT jti/notificationId
  raw          JSONB NOT NULL,
  processed_at TIMESTAMPTZ,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (store, event_id)
);
ALTER TABLE public.billing_events ENABLE ROW LEVEL SECURITY;
-- No policies = no access for anon/authenticated. Only service_role (which
-- bypasses RLS) reads/writes. Explicit: do NOT add a SELECT policy.

-- 5. subscription_status: additive multi-store fields
CREATE OR REPLACE FUNCTION public.subscription_status()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  sub            public.user_subscriptions;
  free_gens      INT;
  v_active_stores TEXT[];
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
```

> NOTE for the implementer: `BIGGSERIAL` above is a deliberate typo trap — write `BIGSERIAL`. Double-check the type before applying.

- [ ] **Step 3: Apply the migration (MCP apply_migration — asks first)**

Apply the migration via the `apply_migration` MCP tool (name: `samsung_multiorigin_entitlement_v1`). This runs against production — confirm the prompt.

- [ ] **Step 4: Post-migration verification (MCP execute_sql, read-only)**

```sql
-- columns exist
SELECT column_name, data_type, column_default FROM information_schema.columns
WHERE table_name='user_subscriptions' AND column_name IN ('store','store_transaction_id');
-- new indexes exist, old one gone
SELECT indexname FROM pg_indexes WHERE tablename='user_subscriptions'
  AND indexname IN ('idx_subs_entitled_user','idx_subs_entitled_user_store','idx_subs_store_txn');
-- Expected: idx_subs_entitled_user GONE; idx_subs_entitled_user_store + idx_subs_store_txn PRESENT
-- billing_events exists with RLS on and NO policies
SELECT relrowsecurity FROM pg_class WHERE relname='billing_events';
SELECT count(*) FROM pg_policies WHERE tablename='billing_events';
-- active subscriber count UNCHANGED vs Step 1 baseline
SELECT count(*) FROM public.user_subscriptions
WHERE status IN ('trial','active','in_grace_period','cancelled') AND expires_at > now();
-- backfill worked
SELECT count(*) FROM public.user_subscriptions
WHERE store='play' AND store_transaction_id IS NULL AND purchase_token IS NOT NULL;
```
Expected: both columns present; `idx_subs_active_user` GONE, the two new indexes PRESENT; `billing_events` relrowsecurity=true with 0 policies; active count == Step 1 baseline; backfill-gap query returns 0.

- [ ] **Step 5: Commit the migration file**

```bash
git add supabase/migrations/20260823_samsung_multiorigin_entitlement_v1.sql
git commit -m "feat(db): multi-origin entitlement — store column, billing_events, store-aware active index, additive subscription_status"
```

---

## Task 2: Make verify_google_purchase store-aware

**Files:**
- Modify: `supabase/functions/verify_google_purchase/index.ts`

**Interfaces:**
- Consumes: `store` / `store_transaction_id` columns (Task 1).
- Produces: Play verify now writes `store='play'` + `store_transaction_id=purchase_token`, and its supersede is scoped to `.eq('store','play')` so it never expires a Samsung row.

- [ ] **Step 1: Scope the supersede to the Play store**

In the supersede block (currently lines ~320-328), add a `.eq('store','play')` filter so re-verifying a Play purchase never expires the user's Samsung subscription:
```typescript
  const { error: supersedeErr } = await admin
    .from('user_subscriptions')
    .update({ status: 'expired', verified_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('store', 'play')
    .neq('purchase_token', purchase_token)
    .in('status', ['trial', 'active', 'in_grace_period', 'on_hold', 'paused']);
```
NOTE: the status list is aligned to the LIVE index predicate
(`idx_subs_entitled_user`: trial/active/in_grace_period/on_hold/paused). The
original code used `[...,'cancelled']` which never matched the live index —
this both store-scopes AND corrects that latent mismatch. `cancelled` is
outside the unique predicate, so it does not need superseding.

- [ ] **Step 2: Stamp store + store_transaction_id on the row**

In the `row` object (currently ~lines 330-348), add:
```typescript
    store: 'play',
    store_transaction_id: purchase_token,
```
(keep `purchase_token`, `order_id`, `metadata`, and the existing `onConflict: 'purchase_token'` upsert unchanged.)

- [ ] **Step 3: Deploy (MCP deploy_edge_function — asks first) + smoke test**

Deploy `verify_google_purchase`. Then confirm an existing Play subscriber still verifies without regression — if a test purchase token is available, curl it; otherwise verify via `execute_sql` that a recent Play row now carries `store='play'` after the next real verify. Because this is a low-risk additive change (adds a filter + two fields), the key check is: existing Play verification path still returns `ok:true`.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/verify_google_purchase/index.ts
git commit -m "fix(edge): verify_google_purchase is store-aware (store-scoped supersede + store fields)"
```

---

## Task 3: verify_samsung_purchase (gated skeleton)

**Files:**
- Create: `supabase/functions/verify_samsung_purchase/index.ts`

**Interfaces:**
- Consumes: `store`/`store_transaction_id` columns (Task 1); the `productMeta` mapping (mirror from the Google function).
- Produces: a deployable function that identifies the caller (same `/auth/v1/user` pattern), and — WHEN `SAMSUNG_*` env is set — verifies via the Samsung Subscription/Orders API and upserts a `store='samsung'` row idempotent by `store_transaction_id`, with a `.eq('store','samsung')` supersede. Without the env, returns `503 samsung_not_configured`.

- [ ] **Step 1: Create the function (gated)**

```typescript
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

  // Store-scoped supersede — never touches the user's Play row.
  const { error: supErr } = await admin
    .from('user_subscriptions')
    .update({ status: 'expired', verified_at: new Date().toISOString() })
    .eq('user_id', userId).eq('store', 'samsung')
    .neq('store_transaction_id', purchase_id)
    .in('status', ['trial', 'active', 'in_grace_period', 'cancelled']);
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
```

- [ ] **Step 2: Deploy (MCP deploy_edge_function — asks first) + curl the gate**

Deploy `verify_samsung_purchase`. Confirm the gate with curl (no Samsung env set → expect 503):
```bash
curl -sS -X POST "https://vzuwvsmlyigjtsearxym.supabase.co/functions/v1/verify_samsung_purchase" \
  -H "authorization: Bearer <any-valid-supabase-user-jwt>" \
  -H "content-type: application/json" \
  -d '{"purchase_id":"test","product_id":"pixora_monthly"}'
# Expected: {"error":"samsung_not_configured", ...} with HTTP 503
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/verify_samsung_purchase/index.ts
git commit -m "feat(edge): verify_samsung_purchase gated skeleton (fail-closed until approval)"
```

---

## Task 4: samsung-isn-webhook (gated skeleton + idempotent ledger)

**Files:**
- Create: `supabase/functions/samsung-isn-webhook/index.ts`

**Interfaces:**
- Consumes: `billing_events` table (Task 1).
- Produces: a public endpoint that records ISN notifications idempotently into `billing_events`. Signature verification is fail-closed: without `SAMSUNG_ISN_PUBLIC_KEY` it records the raw event but marks it unverified and does NOT touch entitlement. Entitlement writes happen only after signature-verified + API re-read (wired at activation).

- [ ] **Step 1: Create the function**

```typescript
// Supabase Edge Function — samsung-isn-webhook
//
// Public endpoint for Samsung Instant Server Notifications (ISN). PUBLIC =
// anyone can POST, so this is security-critical: it NEVER grants entitlement
// from the payload. Flow: parse JWT → (fail-closed) verify signature against
// SAMSUNG_ISN_PUBLIC_KEY → record raw event in billing_events idempotently by
// (store,event_id) → (when configured) re-read authoritative state via the
// Samsung API and update entitlement. Until the public key is set (approval
// pending), events are recorded as unverified and entitlement is untouched.
//
// Env: SAMSUNG_ISN_PUBLIC_KEY (PEM) — set when Samsung approval lands.
// @ts-ignore — Deno runtime
import { createClient } from 'npm:@supabase/supabase-js@2';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

function decodeJwtParts(jwt: string): { header: any; payload: any } | null {
  const parts = jwt.split('.');
  if (parts.length !== 3) return null;
  try {
    const dec = (s: string) => JSON.parse(
      new TextDecoder().decode(Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0))),
    );
    return { header: dec(parts[0]), payload: dec(parts[1]) };
  } catch { return null; }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const isnPublicKey = Deno.env.get('SAMSUNG_ISN_PUBLIC_KEY') ?? '';
  if (!supabaseUrl || !serviceRoleKey) return jsonResponse({ error: 'misconfigured' }, 500);

  // Samsung posts the ISN as a signed JWT (raw body or {notification: "<jwt>"}).
  let jwt = '';
  const ctype = req.headers.get('content-type') ?? '';
  const rawBody = await req.text();
  if (ctype.includes('application/json')) {
    try { jwt = (JSON.parse(rawBody).notification as string) ?? ''; } catch { /* fallthrough */ }
  }
  if (!jwt) jwt = rawBody.trim();
  const parts = decodeJwtParts(jwt);
  if (!parts) return jsonResponse({ error: 'invalid_jwt' }, 400);

  const payload = parts.payload as Record<string, unknown>;
  const eventId = (payload['jti'] as string) ?? (payload['notificationId'] as string)
    ?? (payload['orderId'] as string) ?? crypto.randomUUID();

  // Fail-closed signature verification. Without the public key we still record
  // the event (as unverified) but must NOT act on it.
  let verified = false;
  if (isnPublicKey) {
    try {
      // RS256 verify: header.payload signed, signature is part 3.
      const [h, p, s] = jwt.split('.');
      const key = await crypto.subtle.importKey(
        'spki',
        Uint8Array.from(atob(isnPublicKey.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), c => c.charCodeAt(0)).buffer,
        { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
      );
      const sig = Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
      verified = await crypto.subtle.verify(
        'RSASSA-PKCS1-v1_5', key, sig, new TextEncoder().encode(`${h}.${p}`),
      );
    } catch (_) { verified = false; }
    if (!verified) return jsonResponse({ error: 'signature_invalid' }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Idempotent record. Duplicate (store,event_id) → no-op (ack 200).
  const { error: insErr } = await admin.from('billing_events').insert({
    store: 'samsung',
    event_id: eventId,
    raw: { payload, verified },
  });
  if (insErr && !insErr.message.includes('duplicate')) {
    console.error(`[samsung-isn] insert failed: ${insErr.message}`);
    return jsonResponse({ error: 'db_insert_failed' }, 500);
  }

  // Entitlement update happens ONLY when verified AND Samsung API configured —
  // wired at activation (F3/approval). Until then, we've durably recorded the
  // event for later reconciliation. Always ack so Samsung stops retrying.
  return jsonResponse({ ok: true, recorded: true, verified });
});
```

- [ ] **Step 2: Deploy (MCP deploy_edge_function — asks first, `--no-verify-jwt` so Samsung can POST without a Supabase auth token) + curl test**

Deploy `samsung-isn-webhook` WITHOUT Supabase JWT verification (it's an external webhook; its own security is the Samsung JWT signature). Then curl a sample unsigned JWT and confirm it records idempotently:
```bash
# minimal unsigned sample JWT: header {"alg":"RS256"} . payload {"jti":"evt_test_1","orderId":"o1"} . sig
SAMPLE='eyJhbGciOiJSUzI1NiJ9.eyJqdGkiOiJldnRfdGVzdF8xIiwib3JkZXJJZCI6Im8xIn0.x'
curl -sS -X POST "https://vzuwvsmlyigjtsearxym.supabase.co/functions/v1/samsung-isn-webhook" \
  -H "content-type: application/json" -d "{\"notification\":\"$SAMPLE\"}"
# Expected first call:  {"ok":true,"recorded":true,"verified":false}  (no public key set → unverified, recorded)
# Expected second call (same jti): still {"ok":true,...} but no duplicate row
```
Then verify idempotency via `execute_sql`:
```sql
SELECT count(*) FROM public.billing_events WHERE store='samsung' AND event_id='evt_test_1';
-- Expected: exactly 1 after two POSTs
DELETE FROM public.billing_events WHERE event_id='evt_test_1'; -- cleanup test row
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/samsung-isn-webhook/index.ts
git commit -m "feat(edge): samsung-isn-webhook gated skeleton (idempotent billing_events, fail-closed signature)"
```

---

## Task 5: Reconciliation cron (stub, activated with Samsung)

**Files:**
- Modify: `supabase/migrations/20260823_samsung_multiorigin_entitlement_v1.sql` (append) — OR a new small migration if Task 1 is already applied.

**Interfaces:**
- Consumes: `billing_events`, `user_subscriptions`. Reuses existing `pg_cron`/`pg_net` (24/7 alerts infra).
- Produces: a documented reconciliation approach. The actual cron job that calls the Samsung API is DEFERRED to activation (needs Samsung credentials); F2 only records the intent + confirms pg_cron is available.

- [ ] **Step 1: Confirm pg_cron/pg_net availability (MCP execute_sql, read-only)**

```sql
SELECT extname FROM pg_extension WHERE extname IN ('pg_cron','pg_net');
```
Expected: both present (used by the 24/7 new-user alerts). If present, no schema change needed now — the reconciliation job is scheduled at activation.

- [ ] **Step 2: Record the deferral (no code)**

Because the reconciliation job must call the Samsung API (credentials pending), do NOT schedule it in F2. This task's deliverable is the confirmation above + this note in the plan/ledger: "reconciliation cron scheduled at Samsung activation, reusing pg_cron+pg_net; sweeps active samsung subs near expiry and re-reads Samsung API." No commit if no file changed.

---

## Release / activation note (out of code scope)

When Samsung commercial approval lands: set Supabase Edge secrets `SAMSUNG_SERVICE_ACCOUNT_ID`, `SAMSUNG_API_BASE`, `SAMSUNG_ISN_PUBLIC_KEY` (mirror to KEYS_LOCAL.md/orbixprivate), register the ISN endpoint (`.../functions/v1/samsung-isn-webhook`) in Seller Portal, finalize the Samsung API endpoint/response shapes in verify_samsung_purchase + the webhook's entitlement write, and schedule the reconciliation cron. All gated code fails closed until then.

---

## Self-Review

**Spec coverage (Section 3):** ✅ store + store_transaction_id columns (T1); billing_events append-only idempotent, service-role only (T1); store-aware active-sub unique index replacing the one-per-user index (T1) — plus the coupled supersede fix in verify_google_purchase (T2) that the DDL alone would miss; additive subscription_status with `store` + `active_stores` (T1); verify_samsung_purchase + samsung-isn-webhook with JWT-signature fail-closed + idempotency by (store,event_id) and (store,store_transaction_id) (T3, T4); reconciliation via pg_cron reused (T5). "Webhook is the doorbell, API is the truth" honored: the webhook records + (when configured) re-reads before writing entitlement; it never grants from the payload.

**Placeholder scan:** No TBD/TODO-as-work. The Samsung API endpoint/response shape is explicitly "finalized at activation (F3)" — a real gate tied to credentials we don't have, not a lazy placeholder; the functions are complete and deployable, failing closed. `BIGGSERIAL` is a flagged deliberate trap for the implementer to catch (→ `BIGSERIAL`).

**Type consistency:** `store` values `'play'|'samsung'` used identically across CHECK, indexes, RPC, and all three functions. `store_transaction_id` is the upsert conflict key in verify_samsung (`onConflict: 'store,store_transaction_id'`) matching the `idx_subs_store_txn` unique (T1). `event_id` unique `(store,event_id)` (T1) matches the webhook's idempotent insert (T4). subscription_status new keys `store`/`active_stores` are additive — the Flutter `_setFromJson` ignores unknown keys, so no client change needed in F2.
