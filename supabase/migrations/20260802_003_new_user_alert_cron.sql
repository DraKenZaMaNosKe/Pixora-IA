-- =============================================================================
-- Cron de alertas de usuario nuevo — cada 5 min llama run_new_user_alert()
-- Migration: 20260802_003_new_user_alert_cron
-- Apagar: select cron.unschedule('new-user-alert');
-- =============================================================================
select cron.schedule('new-user-alert', '*/5 * * * *', $$select public.run_new_user_alert()$$);
