-- =============================================================================
-- Pixora User Terms Acceptance — legal evidence trail
-- Migration: 20260505_008_user_terms_acceptance
--
-- Records every user/device acceptance of the Terms & Privacy version. This
-- is the row that legal stands on if a dispute arises about whether the user
-- consented. Local Hive is the UX source of truth; this table is the audit log.
-- =============================================================================

create table if not exists public.user_terms_acceptance (
  id              bigserial primary key,
  user_id         uuid,
  device_id       text not null check (length(device_id) between 1 and 80),
  terms_version   int not null check (terms_version > 0),
  accepted_at     timestamptz not null default now(),
  app_version     text,
  ip_hint         text,                              -- optional, only set if we capture
  created_at      timestamptz not null default now()
);

comment on table public.user_terms_acceptance is
  'Audit log of Terms & Privacy acceptances. One row per device per terms version.';

-- One acceptance row per (device, version) — re-tapping doesn't duplicate.
create unique index if not exists idx_uta_dedupe
  on public.user_terms_acceptance (device_id, terms_version);

create index if not exists idx_uta_user
  on public.user_terms_acceptance (user_id, accepted_at desc)
  where user_id is not null;

create index if not exists idx_uta_version_time
  on public.user_terms_acceptance (terms_version, accepted_at desc);

alter table public.user_terms_acceptance enable row level security;
-- No policies → service_role only. Reads happen through admin tools.

-- ───────── RPC: log a single acceptance (anon-callable) ─────────
create or replace function public.log_terms_acceptance(
  p_terms_version int,
  p_device_id     text,
  p_app_version   text default null,
  p_accepted_at   timestamptz default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid := auth.uid();
begin
  if p_terms_version is null or p_terms_version <= 0 then
    raise exception 'terms_version must be a positive integer';
  end if;
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;

  begin
    insert into public.user_terms_acceptance
      (user_id, device_id, terms_version, app_version, accepted_at)
      values (
        v_user_id,
        p_device_id,
        p_terms_version,
        p_app_version,
        coalesce(p_accepted_at, now())
      );
    return true;
  exception
    when unique_violation then
      -- Already accepted this version on this device — that's fine, idempotent.
      -- If the user signed in after a device-only acceptance, link the user_id.
      update public.user_terms_acceptance
        set user_id = coalesce(user_id, v_user_id)
        where device_id = p_device_id
          and terms_version = p_terms_version;
      return false;
  end;
end$$;

grant execute on function public.log_terms_acceptance(int, text, text, timestamptz)
  to anon, authenticated;

-- ───────── Admin views (service_role only) ─────────

-- Acceptance funnel by version — last 30 days
create or replace view public.admin_terms_acceptance_30d as
select
  terms_version,
  count(*) as total_acceptances,
  count(distinct device_id) as unique_devices,
  count(distinct user_id) filter (where user_id is not null) as unique_users,
  min(accepted_at) as first_accepted,
  max(accepted_at) as last_accepted
from public.user_terms_acceptance
where accepted_at > now() - interval '30 days'
group by 1
order by 1 desc;

-- Devices that haven't yet accepted the current version (we discover these
-- via app_events 'terms_gate_shown' minus user_terms_acceptance) — useful
-- for measuring conversion.
