-- =============================================================================
-- Enviador de alertas de usuario nuevo — correo (Resend) + push (ntfy) vía pg_net
-- Migration: 20260802_002_new_user_alert_sender
-- Lee los secretos de Vault por NOMBRE (resend_api_key, ntfy_topic) — sin
-- valores en el repo. Optimista al marcar notified_at (doble canal reduce riesgo).
-- =============================================================================
create or replace function public.run_new_user_alert()
returns void
language plpgsql security definer set search_path = public, vault as $$
declare
  v_rows  new_user_alerts[];
  v_ids   text[];
  v_count int;
  v_resend text;
  v_ntfy   text;
  v_lines  text := '';
  v_title  text;
  v_html   text;
  r new_user_alerts;
begin
  -- 1. Detecta (inserta nuevos REAL, regresa los pendientes de notificar)
  select array_agg(x), array_agg(x.device_id) into v_rows, v_ids
  from public.detect_new_real_users() x;

  v_count := coalesce(array_length(v_ids, 1), 0);
  if v_count = 0 then return; end if;

  select decrypted_secret into v_resend from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into v_ntfy   from vault.decrypted_secrets where name = 'ntfy_topic';

  -- 2. Arma el resumen (máx 10 líneas)
  for r in select * from unnest(v_rows) limit 10 loop
    v_lines := v_lines || format('- %s (v%s) · %s%s' || E'\n',
      coalesce(r.payload->>'model', 'modelo aun no reportado'),
      coalesce(r.payload->>'version', '?'),
      coalesce(r.payload->>'wallpaper', 'sin wallpaper activo'),
      case when coalesce((r.payload->>'downloads')::int, 0) > 0 then ' [descargo]' else '' end);
  end loop;
  if v_count > 10 then v_lines := v_lines || format('...y %s mas', v_count - 10); end if;
  v_title := case when v_count = 1 then '🎉 Usuario nuevo en Pixora'
                  else format('🎉 %s usuarios nuevos en Pixora', v_count) end;

  -- 3a. Push al celular (ntfy — formato JSON publishing)
  perform net.http_post(
    url := 'https://ntfy.sh',
    body := jsonb_build_object('topic', v_ntfy, 'title', v_title,
      'message', v_lines, 'priority', 4, 'tags', jsonb_build_array('tada')),
    headers := '{"Content-Type":"application/json"}'::jsonb);

  -- 3b. Correo (Resend)
  v_html := format('<h2>%s 🎉</h2><pre style="font-family:sans-serif;font-size:14px">%s</pre>'
    || '<p style="color:#888;font-size:12px">Alerta automatica de Pixora · %s CST</p>',
    v_title, v_lines, to_char(now() at time zone 'America/Mexico_City', 'YYYY-MM-DD HH24:MI'));
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    body := jsonb_build_object(
      'from', 'Pixora Alertas <onboarding@resend.dev>',
      'to', jsonb_build_array('eduardojcr@gmail.com'),
      'subject', v_title, 'html', v_html),
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_resend));

  -- 4. Marcar notificados (optimista)
  update public.new_user_alerts set notified_at = now() where device_id = any(v_ids);
end $$;
revoke all on function public.run_new_user_alert() from public, anon, authenticated;
