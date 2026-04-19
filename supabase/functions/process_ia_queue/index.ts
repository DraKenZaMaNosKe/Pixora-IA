import { createClient } from 'npm:@supabase/supabase-js@2';

type ProcessBody = { queue_id?: number };

const GEMINI_IMAGE_MODEL = 'gemini-2.5-flash-image';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
function errorResponse(code: string, detail: string, status = 400): Response {
  console.error(`[process_ia_queue] ${code}: ${detail}`);
  return jsonResponse({ error: code, detail }, status);
}

async function callGemini(apiKey: string, prompt: string, style: string | null): Promise<Uint8Array> {
  const styledPrompt = style && style.length > 0
    ? `${prompt}. Art style: ${style}. High quality, detailed, vertical 9:16 phone wallpaper composition.`
    : `${prompt}. High quality, detailed, vertical 9:16 phone wallpaper composition.`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_IMAGE_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;
  console.log(`[gemini] POST ${GEMINI_IMAGE_MODEL} prompt.len=${styledPrompt.length}`);
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: styledPrompt }] }],
      generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
    }),
  });
  const text = await resp.text();
  console.log(`[gemini] status=${resp.status} bodyLen=${text.length}`);
  if (!resp.ok) {
    console.error(`[gemini] body: ${text.slice(0, 500)}`);
    throw new Error(`gemini_api_error: ${resp.status} ${text.slice(0, 300)}`);
  }
  const data = JSON.parse(text);
  const parts = data?.candidates?.[0]?.content?.parts ?? [];
  for (const p of parts) {
    if (p?.inlineData?.data && String(p.inlineData.mimeType ?? '').startsWith('image/')) {
      const base64: string = p.inlineData.data;
      const bin = atob(base64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      return bytes;
    }
  }
  throw new Error(`gemini_no_image: response had no inlineData image. parts=${JSON.stringify(parts).slice(0, 300)}`);
}

async function refundGeneration(
  admin: ReturnType<typeof createClient>,
  userId: string,
  queueId: number,
  source: string,
  creditsCharged: number,
): Promise<void> {
  try {
    if (source === 'free_trial_gen') {
      await admin.rpc('refund_free_gen', { p_user_id: userId });
    } else if (source === 'subscription_quota') {
      await admin.rpc('refund_subscription_gen', { p_user_id: userId });
    } else if (source === 'credits_extra' && creditsCharged > 0) {
      await admin.rpc('refund_credits', { p_user_id: userId, p_amount: creditsCharged, p_queue_id: queueId });
    }
    console.log(`[refund] ok user=${userId} source=${source} credits=${creditsCharged}`);
  } catch (e) {
    console.error(`[refund] failed user=${userId} source=${source}: ${e}`);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return errorResponse('method_not_allowed', 'Use POST', 405);
  const authHeader = req.headers.get('authorization') ?? '';
  const userJwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!userJwt) return errorResponse('missing_auth', 'Authorization header required', 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const geminiKey = Deno.env.get('GEMINI_API_KEY') ?? '';
  if (!supabaseUrl || !serviceRoleKey) return errorResponse('misconfigured', 'Supabase env missing', 500);
  if (!geminiKey) return errorResponse('misconfigured', 'GEMINI_API_KEY env missing', 500);

  let body: ProcessBody = {};
  try { body = await req.json(); } catch { /* optional body */ }
  const queueIdFromBody = body.queue_id;

  let userId: string;
  try {
    const authResp = await fetch(`${supabaseUrl}/auth/v1/user`, {
      method: 'GET',
      headers: { 'apikey': serviceRoleKey, 'authorization': `Bearer ${userJwt}` },
    });
    if (!authResp.ok) {
      const txt = await authResp.text();
      return errorResponse('not_authenticated', `auth/v1/user returned ${authResp.status}: ${txt.slice(0, 200)}`, 401);
    }
    const uJson = await authResp.json();
    userId = uJson.id as string;
    if (!userId) return errorResponse('not_authenticated', 'auth/v1/user returned no id', 401);
  } catch (e) { return errorResponse('not_authenticated', `auth fetch failed: ${e}`, 401); }

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

  let claimQuery = admin.from('ia_generation_queue')
    .update({ status: 'processing', started_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('status', 'pending');
  if (typeof queueIdFromBody === 'number') {
    claimQuery = claimQuery.eq('id', queueIdFromBody);
  }
  const { data: claimed, error: claimErr } = await claimQuery.select('id, prompt, style, model, source, credits_charged').order('id', { ascending: true }).limit(1);
  if (claimErr) return errorResponse('db_claim_failed', claimErr.message, 500);
  if (!claimed || claimed.length === 0) return errorResponse('no_pending_row', 'No pending row to process for this user', 404);

  const row = claimed[0] as { id: number; prompt: string; style: string | null; model: string; source: string; credits_charged: number };
  const queueId = row.id;
  console.log(`[proc] claimed queue_id=${queueId} prompt.len=${row.prompt.length} style=${row.style ?? '-'} source=${row.source}`);

  let imageBytes: Uint8Array;
  try {
    imageBytes = await callGemini(geminiKey, row.prompt, row.style);
  } catch (e) {
    const errMsg = String(e);
    await admin.from('ia_generation_queue').update({
      status: 'failed',
      error_code: 'gemini_failed',
      error_message: errMsg.slice(0, 500),
      completed_at: new Date().toISOString(),
      output_safe: false,
    }).eq('id', queueId);
    await refundGeneration(admin, userId, queueId, row.source, row.credits_charged);
    return errorResponse('gemini_failed', errMsg, 502);
  }

  const path = `${userId}/${queueId}.png`;
  console.log(`[storage] upload path=${path} bytes=${imageBytes.length}`);
  const { error: upErr } = await admin.storage.from('ia-generations').upload(path, imageBytes, {
    contentType: 'image/png',
    upsert: true,
  });
  if (upErr) {
    await admin.from('ia_generation_queue').update({
      status: 'failed',
      error_code: 'storage_upload_failed',
      error_message: upErr.message,
      completed_at: new Date().toISOString(),
    }).eq('id', queueId);
    await refundGeneration(admin, userId, queueId, row.source, row.credits_charged);
    return errorResponse('storage_upload_failed', upErr.message, 500);
  }

  const { data: urlData } = admin.storage.from('ia-generations').getPublicUrl(path);
  const publicUrl = urlData.publicUrl;

  const { error: doneErr } = await admin.from('ia_generation_queue').update({
    status: 'done',
    result_url: publicUrl,
    thumbnail_url: publicUrl,
    output_safe: true,
    completed_at: new Date().toISOString(),
  }).eq('id', queueId);
  if (doneErr) return errorResponse('db_finalize_failed', doneErr.message, 500);

  console.log(`[proc] done queue_id=${queueId} url=${publicUrl}`);
  return jsonResponse({ ok: true, queue_id: queueId, result_url: publicUrl });
});
