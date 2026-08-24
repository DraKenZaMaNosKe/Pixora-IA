// Supabase Edge Function — samsung-isn-webhook
//
// Public endpoint for Samsung Instant Server Notifications (ISN). PUBLIC =
// anyone can POST, so this is security-critical: it NEVER grants entitlement
// from the payload. Flow: parse JWT -> (fail-closed) verify signature against
// SAMSUNG_ISN_PUBLIC_KEY -> record raw event in billing_events idempotently by
// (store,event_id) -> (when configured) re-read authoritative state via the
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

  // Idempotent record. Duplicate (store,event_id) -> no-op (ack 200).
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
