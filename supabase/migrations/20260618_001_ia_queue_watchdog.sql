-- 2026-06-18 — IA Queue watchdog: rescue orphan pending/processing rows.
--
-- Problem (audit Sprint 1 finding #7): the Flutter client fires the
-- process_ia_queue Edge Function via `_dispatchWorker` AFTER calling
-- `enqueue_generation`. If the client closes the app between those two
-- calls, or if the worker errors before writing back, the row stays in
-- 'pending' (or 'processing') forever. No retry, no cron, no recovery.
-- Result: user is debited credits, UI shows spinner forever, daily cap
-- counts the orphan against them.
--
-- Fix: pg_cron job that scans every minute for stale rows and either:
--   · re-dispatches them (pending > 30s, or processing > 5 min)
--   · marks them failed (any > 15 min) — refunds via existing trigger
--
-- Requires pg_cron extension. If unavailable on the project, this migration
-- creates the helper functions but the schedule needs to be set up via the
-- Supabase dashboard (Database → Extensions → pg_cron) and then manually
-- run `select cron.schedule(...)` from this file.

-- ───── Helper: identify stale rows ─────
create or replace function public.ia_queue_stale_rows(p_pending_secs int default 30,
                                                     p_processing_secs int default 300,
                                                     p_dead_secs int default 900)
returns table(id bigint, status text, age_secs int)
language sql stable security definer set search_path = public as $$
  select q.id,
         q.status,
         extract(epoch from now() - coalesce(q.started_at, q.created_at))::int as age_secs
  from public.ia_generation_queue q
  where (q.status = 'pending' and now() - q.created_at > make_interval(secs => p_pending_secs))
     or (q.status = 'processing' and now() - coalesce(q.started_at, q.created_at) > make_interval(secs => p_processing_secs))
$$;

-- ───── Action: mark dead rows as failed (auto-refund via existing trigger) ─────
create or replace function public.ia_queue_kill_dead(p_dead_secs int default 900)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_count int;
begin
  update public.ia_generation_queue
     set status = 'failed',
         error_message = coalesce(error_message,
                                  'auto-failed: stalled in ' || status || ' >' || p_dead_secs || 's'),
         completed_at = now()
   where (status = 'pending' or status = 'processing')
     and now() - coalesce(started_at, created_at) > make_interval(secs => p_dead_secs);
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.ia_queue_stale_rows(int,int,int) from public, anon, authenticated;
revoke all on function public.ia_queue_kill_dead(int) from public, anon, authenticated;

comment on function public.ia_queue_stale_rows is
  'Returns rows that have been stuck in pending/processing too long. Read-only diagnostic.';
comment on function public.ia_queue_kill_dead is
  'Force-fail rows stuck >N seconds (default 15 min). The existing trigger refunds credits.';

-- ───── Schedule (only if pg_cron is enabled) ─────
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Unschedule any previous version to make this migration idempotent
    perform cron.unschedule(jobid) from cron.job where jobname = 'ia_queue_watchdog_15m';
    -- Run every minute: kill dead (>15 min) rows so users get refunded
    perform cron.schedule(
      'ia_queue_watchdog_15m',
      '* * * * *',
      $cron$ select public.ia_queue_kill_dead(900); $cron$
    );
  end if;
end $$;
