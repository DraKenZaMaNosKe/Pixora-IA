-- =============================================================================
-- Device identity unification: alias table + one-shot merge RPC + alias-aware
-- wp_log_event. Safe to apply BEFORE the app release (inert without it).
-- Migration: 20260726_001_device_identity_unify
-- =============================================================================
BEGIN;

-- ── 1) alias mapping (old stats id → canonical analytics id) ──
create table if not exists public.device_aliases (
  old_id      text primary key check (length(old_id) between 1 and 80),
  new_id      text not null       check (length(new_id) between 1 and 80),
  migrated_at timestamptz not null default now()
);
create index if not exists idx_device_aliases_new on public.device_aliases (new_id);
alter table public.device_aliases enable row level security;
-- no policies → service_role only

-- ── 2) one-shot idempotent merge (anon-callable) ──
create or replace function public.migrate_device_identity(p_old text, p_new text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_old is null or p_new is null or length(p_old) = 0 or length(p_new) = 0 then
    raise exception 'both ids required';
  end if;
  if length(p_old) > 80 or length(p_new) > 80 then
    raise exception 'id too long';
  end if;
  if p_old = p_new then
    return true;
  end if;
  -- idempotent: already migrated → success, no-op
  if exists (select 1 from device_aliases where old_id = p_old) then
    return true;
  end if;
  -- anti-chain / anti-cycle
  if exists (select 1 from device_aliases where new_id = p_old)
     or exists (select 1 from device_aliases where old_id = p_new) then
    raise exception 'id already part of an alias mapping';
  end if;
  -- guard: a legacy id that already emits heartbeats is somebody's canonical id
  if exists (select 1 from device_presence where device_id = p_old) then
    raise exception 'old id has presence; refusing to remap';
  end if;

  -- likes: delete would-be duplicates under the new id first, then repoint
  delete from wallpaper_likes l
   where l.device_id = p_old
     and exists (select 1 from wallpaper_likes k
                  where k.device_id = p_new and k.wallpaper_id = l.wallpaper_id);
  update wallpaper_likes set device_id = p_new where device_id = p_old;

  -- events: delete view-dedupe collisions first, then repoint
  delete from wallpaper_events e
   where e.device_id = p_old and e.event_type = 'view'
     and exists (select 1 from wallpaper_events x
                  where x.device_id = p_new and x.event_type = 'view'
                    and x.wallpaper_id = e.wallpaper_id and x.ts_minute = e.ts_minute);
  update wallpaper_events set device_id = p_new where device_id = p_old;

  insert into device_aliases (old_id, new_id) values (p_old, p_new);
  return true;
end$$;
grant execute on function public.migrate_device_identity(text,text) to anon, authenticated;

-- ── 3) alias-aware wp_log_event (staged rollout: old app keeps sending old id) ──
create or replace function public.wp_log_event(
  p_wallpaper_id text,
  p_event_type   text,
  p_device_id    text,
  p_app_version  text default null,
  p_metadata     jsonb default '{}'::jsonb
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_inserted boolean := false;
  v_user_id  uuid := auth.uid();
  v_canon    text;
begin
  if p_event_type not in ('view','preview','install','share','favorite','unfavorite','download') then
    raise exception 'Invalid event_type: %', p_event_type;
  end if;
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;

  -- repoint legacy id → canonical, if an alias exists
  select new_id into v_canon from device_aliases where old_id = p_device_id;
  if v_canon is not null then
    p_device_id := v_canon;
  end if;

  begin
    insert into public.wallpaper_events
      (device_id, user_id, wallpaper_id, event_type, app_version, metadata)
      values (p_device_id, v_user_id, p_wallpaper_id, p_event_type, p_app_version, p_metadata);
    v_inserted := true;
  exception
    when unique_violation then
      v_inserted := false;
  end;

  if v_inserted then
    case p_event_type
      when 'view' then
        update public.wallpapers set view_count = view_count + 1, last_viewed_at = now()
          where id = p_wallpaper_id and published = true;
      when 'install' then
        update public.wallpapers set install_count = install_count + 1, last_installed_at = now()
          where id = p_wallpaper_id and published = true;
      when 'share' then
        update public.wallpapers set share_count = share_count + 1
          where id = p_wallpaper_id and published = true;
      when 'favorite' then
        update public.wallpapers set favorite_count = favorite_count + 1
          where id = p_wallpaper_id and published = true;
      when 'unfavorite' then
        update public.wallpapers set favorite_count = greatest(0, favorite_count - 1)
          where id = p_wallpaper_id and published = true;
      else null;
    end case;
  end if;
  return v_inserted;
end$$;
grant execute on function public.wp_log_event(text,text,text,text,jsonb) to anon, authenticated;

COMMIT;
