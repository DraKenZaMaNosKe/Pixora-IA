-- device → human label helper. Maps a device_id to the email of the most
-- recent logged-in user seen on that device (most devices are signed-out, so
-- this only covers the ~29 with login). The dashboard falls back to a
-- deterministic memorable alias for anonymous devices, and F1's heartbeat
-- will add the phone MODEL (Build.MODEL) as the best label.
-- service_role only (security_invoker + revoked from anon).

BEGIN;

create or replace view public.admin_device_email
with (security_invoker = on) as
select distinct on (device_id) device_id, u.email
from (
  select device_id, user_id, ts from app_events      where user_id is not null
  union all
  select device_id, user_id, ts from wallpaper_events where user_id is not null
) dv
join users u on u.id = dv.user_id
order by device_id, ts desc;

revoke all on public.admin_device_email from anon, authenticated;

COMMIT;
