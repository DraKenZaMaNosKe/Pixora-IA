-- Admin-only views for the Pixel Studio "Cuentas" sub-view (Usuarios tab).
-- Groups the population by the STABLE identity (email / auth account) instead
-- of by device_id, which can change on reinstall. Two read-only views:
--   admin_accounts       — one row per registered user (email), with device
--                          count, last activity, latest app version, whether
--                          they applied a wallpaper, and subscriber status.
--   admin_anon_devices   — devices that never logged in (no user_id in any
--                          event), i.e. anonymous population.
-- Both are SECURITY-plain views read via the service key from the local admin
-- server. Reversible: DROP VIEW admin_accounts, admin_anon_devices.

-- device_id -> user_id links, same source of truth as admin_device_email.
CREATE OR REPLACE VIEW admin_accounts AS
WITH dev_links AS (
    SELECT DISTINCT device_id, user_id
    FROM (
        SELECT device_id, user_id FROM app_events       WHERE user_id IS NOT NULL
        UNION ALL
        SELECT device_id, user_id FROM wallpaper_events WHERE user_id IS NOT NULL
    ) e
    WHERE device_id IS NOT NULL
),
dev_stats AS (
    SELECT dl.user_id,
           count(DISTINCT dl.device_id)                    AS device_count,
           max(dp.last_seen_at)                            AS last_seen_at,
           bool_or(dp.active_wallpaper_id IS NOT NULL)     AS applied_wallpaper
    FROM dev_links dl
    LEFT JOIN device_presence dp ON dp.device_id = dl.device_id
    GROUP BY dl.user_id
),
latest_ver AS (
    -- app_version from the most-recently-seen device (avoids lexical max bug).
    SELECT DISTINCT ON (dl.user_id) dl.user_id, dp.app_version
    FROM dev_links dl
    JOIN device_presence dp ON dp.device_id = dl.device_id
    WHERE dp.app_version IS NOT NULL
    ORDER BY dl.user_id, dp.last_seen_at DESC NULLS LAST
),
sub_agg AS (
    SELECT user_id,
           bool_or(status = 'active'
                   AND (expires_at IS NULL OR expires_at > now())) AS is_subscriber
    FROM user_subscriptions
    GROUP BY user_id
)
SELECT u.id                                   AS user_id,
       u.email,
       u.is_admin,
       u.created_at                           AS registered_at,
       COALESCE(ds.device_count, 0)           AS device_count,
       ds.last_seen_at,
       lv.app_version,
       COALESCE(ds.applied_wallpaper, false)  AS applied_wallpaper,
       COALESCE(sa.is_subscriber, false)      AS is_subscriber
FROM users u
LEFT JOIN dev_stats  ds ON ds.user_id = u.id
LEFT JOIN latest_ver lv ON lv.user_id = u.id
LEFT JOIN sub_agg    sa ON sa.user_id = u.id;

-- Anonymous devices: present in device_presence but never tied to a user_id.
CREATE OR REPLACE VIEW admin_anon_devices AS
SELECT dp.device_id,
       dp.first_seen_at,
       dp.last_seen_at,
       dp.app_version,
       dp.device_model,
       dp.active_kind,
       (dp.active_wallpaper_id IS NOT NULL) AS applied_wallpaper
FROM device_presence dp
WHERE dp.device_id NOT IN (
    SELECT device_id FROM (
        SELECT device_id FROM app_events       WHERE user_id IS NOT NULL
        UNION
        SELECT device_id FROM wallpaper_events WHERE user_id IS NOT NULL
    ) z
    WHERE device_id IS NOT NULL
);
