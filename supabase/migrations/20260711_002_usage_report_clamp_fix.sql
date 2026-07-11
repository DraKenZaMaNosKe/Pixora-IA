-- Fix: the anti-cheat clamp read credit_watermark AFTER the presence upsert set
-- it to now(), so a device's FIRST credit batch was clamped to the 120s slack
-- (scale 0.4 on a 300s report). Now we snapshot the PREVIOUS watermark before
-- the upsert; a brand-new device gets a generous 1-day allowance (still bounded
-- by the per-row seconds<=86400 check), so the first real flush isn't truncated.

BEGIN;

create or replace function public.usage_report(
  p_device_id text,
  p_state     jsonb default '{}'::jsonb,
  p_credits   jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_prev_watermark timestamptz;
  v_allowed  numeric;
  v_sum      numeric := 0;
  v_scale    numeric := 1.0;
  v_c        jsonb;
  v_inserted int := 0;
begin
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;

  -- Snapshot the watermark BEFORE the upsert overwrites it.
  select credit_watermark into v_prev_watermark
    from device_presence where device_id = p_device_id;

  insert into device_presence (device_id, last_seen_at, last_source, app_version,
    device_model, android_sdk, active_kind, active_wallpaper_id, daily_enabled,
    wallpaper_set_at, active_ringtone_id, active_ringtone_title,
    active_ringtone_type, ringtone_set_at, updated_at)
  values (p_device_id, now(), p_state->>'source', p_state->>'app_version',
    p_state->>'device_model', (p_state->>'android_sdk')::int,
    p_state->>'active_kind', p_state->>'active_wallpaper_id',
    coalesce((p_state->>'daily_enabled')::boolean, false),
    (p_state->>'wallpaper_set_at')::timestamptz,
    p_state->>'active_ringtone_id', p_state->>'active_ringtone_title',
    (p_state->>'active_ringtone_type')::smallint,
    (p_state->>'ringtone_set_at')::timestamptz, now())
  on conflict (device_id) do update set
    last_seen_at = now(),
    last_source  = coalesce(excluded.last_source, device_presence.last_source),
    app_version  = coalesce(excluded.app_version, device_presence.app_version),
    device_model = coalesce(excluded.device_model, device_presence.device_model),
    android_sdk  = coalesce(excluded.android_sdk, device_presence.android_sdk),
    active_kind         = case when p_state ? 'active_kind'
                            then excluded.active_kind else device_presence.active_kind end,
    active_wallpaper_id = case when p_state ? 'active_wallpaper_id'
                            then excluded.active_wallpaper_id else device_presence.active_wallpaper_id end,
    daily_enabled       = case when p_state ? 'daily_enabled'
                            then excluded.daily_enabled else device_presence.daily_enabled end,
    wallpaper_set_at    = coalesce(excluded.wallpaper_set_at, device_presence.wallpaper_set_at),
    active_ringtone_id    = case when p_state ? 'active_ringtone_id'
                            then excluded.active_ringtone_id else device_presence.active_ringtone_id end,
    active_ringtone_title = coalesce(excluded.active_ringtone_title, device_presence.active_ringtone_title),
    active_ringtone_type  = coalesce(excluded.active_ringtone_type, device_presence.active_ringtone_type),
    ringtone_set_at       = coalesce(excluded.ringtone_set_at, device_presence.ringtone_set_at),
    updated_at = now();

  -- Clamp against the PREVIOUS watermark. New device (null) → 1-day allowance.
  v_allowed := extract(epoch from
    (now() - coalesce(v_prev_watermark, now() - interval '1 day'))) * 1.10 + 120;

  select coalesce(sum((c->>'seconds')::numeric), 0) into v_sum
    from jsonb_array_elements(p_credits) c;
  if v_sum > v_allowed and v_sum > 0 then
    v_scale := greatest(v_allowed, 0) / v_sum;
  end if;

  for v_c in select * from jsonb_array_elements(p_credits) loop
    begin
      insert into usage_credits (device_id, content_kind, content_id, is_daily,
        seconds, segment_start, client_entry_id)
      values (p_device_id, v_c->>'kind', v_c->>'content_id',
        coalesce((v_c->>'is_daily')::boolean, false),
        greatest(1, floor((v_c->>'seconds')::numeric * v_scale))::int,
        (v_c->>'segment_start')::timestamptz, v_c->>'entry_id');
      v_inserted := v_inserted + 1;
      insert into usage_totals (device_id, content_kind, content_id,
        total_seconds, daily_seconds, last_used_at)
      values (p_device_id, v_c->>'kind', v_c->>'content_id',
        floor((v_c->>'seconds')::numeric * v_scale)::bigint,
        case when coalesce((v_c->>'is_daily')::boolean,false)
          then floor((v_c->>'seconds')::numeric * v_scale)::bigint else 0 end, now())
      on conflict (device_id, content_kind, content_id) do update set
        total_seconds = usage_totals.total_seconds + excluded.total_seconds,
        daily_seconds = usage_totals.daily_seconds + excluded.daily_seconds,
        last_used_at  = now();
    exception when unique_violation then null;
             when others then null;
    end;
  end loop;

  if v_inserted > 0 then
    update device_presence set credit_watermark = now() where device_id = p_device_id;
  end if;

  return jsonb_build_object('inserted', v_inserted, 'scale', round(v_scale, 3));
end$$;

COMMIT;
