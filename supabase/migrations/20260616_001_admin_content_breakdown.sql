-- 2026-06-16 — admin_content_breakdown view: stats para TODO el contenido.
--
-- Problema: admin_wallpaper_breakdown arranca con `FROM wallpapers w`,
-- entonces solo trae rows que existen en la tabla wallpapers (que es
-- exclusiva para wallpapers static + canvas_scene + panoramic, etc).
-- Los IDs `tone_<x>`, `tone_pack_<x>`, `aura_<x>`, `story_<x>`,
-- `daycycle_<id>` viven en sus catálogos JSON en Storage (NO Postgres),
-- pero sus contadores SÍ se registran en wallpaper_stats + wallpaper_events.
-- Resultado: aunque la app trackea views/downloads de tonos, stories, etc,
-- el admin no los muestra en ningún ranking ni breakdown.
--
-- Fix: nueva vista que arranca de wallpaper_stats (incluye todos los IDs)
-- y LEFT JOIN a wallpapers para enriquecer cuando aplique. Agrega columna
-- `content_type` derivada del prefijo del ID (tone_/tone_pack_/aura_/
-- story_/daycycle_) o 'wallpaper' como default.
--
-- Mantenemos admin_wallpaper_breakdown viva por backwards-compat — el
-- nuevo endpoint /api/top-content del server apunta a esta nueva vista.

create or replace view public.admin_content_breakdown as
with stats_with_type as (
  select
    s.wallpaper_id as id,
    case
      when s.wallpaper_id like 'tone_pack_%' then 'ringtone_pack'
      when s.wallpaper_id like 'tone_%'      then 'ringtone'
      when s.wallpaper_id like 'aura_%'      then 'aura'
      when s.wallpaper_id like 'story_%'     then 'story'
      when s.wallpaper_id like 'daycycle_%'  then 'day_cycle'
      else 'wallpaper'
    end as content_type,
    s.likes, s.downloads, s.views, s.updated_at
  from public.wallpaper_stats s
)
select
  st.id,
  st.content_type,
  coalesce(w.name, st.id)        as name,
  w.category,
  w.featured,
  st.likes,
  st.downloads,
  st.views,
  -- Event counters from wallpaper_events (deeper than the aggregate
  -- counters in wallpaper_stats: gives us installs vs raw downloads,
  -- shares, and unique_devices).
  coalesce(e.installs, 0)         as installs,
  coalesce(e.shares, 0)           as shares,
  coalesce(e.unique_devices, 0)   as unique_devices,
  case when coalesce(st.views, 0) > 0
    then round(coalesce(e.installs, 0) * 100.0 / st.views, 2)
    else 0 end                    as install_rate_pct,
  w.trending_score,
  -- TRUE only when the row backing the id actually exists in wallpapers
  -- (i.e. content_type='wallpaper'). UI uses this to know if modal opens
  -- with rich metadata or just stats-only fallback.
  (w.id is not null)              as has_metadata,
  st.updated_at                   as last_stat_update
from stats_with_type st
left join public.wallpapers w on w.id = st.id
left join lateral (
  select count(*) filter (where event_type='install')  as installs,
         count(*) filter (where event_type='share')    as shares,
         count(distinct device_id)                     as unique_devices
  from public.wallpaper_events we where we.wallpaper_id = st.id
) e on true;

comment on view public.admin_content_breakdown is
  'Stats unificadas de TODO el contenido (wallpapers + ringtones + stories + day_cycle + aura). Arranca de wallpaper_stats para no perder IDs huérfanos (que viven en catálogos JSON, no en tabla wallpapers). Reemplaza admin_wallpaper_breakdown para el ranking del admin dashboard.';
