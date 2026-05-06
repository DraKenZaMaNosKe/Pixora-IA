# Pixora Admin Dashboard — Setup en máquina nueva

Procedimiento para reconstruir el dashboard local de admin en una PC nueva
o en otra máquina (ej: trabajo ↔ casa).

## Pre-requisitos

- Windows con Git + GitHub CLI (`gh auth login` ya hecho)
- Python 3.x instalado
- Repos clonados en estas rutas exactas:
  - `D:\Orbix\Pixora-IA\` (público)
  - `D:\Orbix\orbixprivate\` (privado, con secretos)

Si los repos no existen aún:
```bash
cd /d
mkdir Orbix && cd Orbix
gh repo clone DraKenZaMaNosKe/Pixora-IA
gh repo clone DraKenZaMaNosKe/orbixprivate
```

## Pasos (en orden)

### 1. Pull último estado
```bash
cd /d/Orbix/Pixora-IA && git pull
cd /d/Orbix/orbixprivate && git pull
```

### 2. Bootstrap secretos
```bash
cd /d/Orbix/orbixprivate && bash scripts/bootstrap.sh
```
Copia `KEYS_LOCAL.md` (Postgres password + service_role JWT) a
`D:/Orbix/Pixora-IA/KEYS_LOCAL.md`.

### 3. Dependencias Python (una vez por PC)
```bash
pip install psycopg2-binary requests
```

### 4. Crear shortcut de escritorio
```bash
powershell -ExecutionPolicy Bypass -File "D:\Orbix\Pixora-IA\tools\wallpapers\install_admin_shortcut.ps1"
```
Pone "Pixora Admin.lnk" en `OneDrive\Escritorio` apuntando al `.vbs`
que lanza pythonw silencioso.

### 5. Lanzar
Doble click al icono **Pixora Admin** del escritorio. Server arranca
en `http://127.0.0.1:5757/` y abre el browser solo.

## Pre-requisito Supabase

El proyecto requiere el add-on **Dedicated IPv4** activo (~$4 USD/mes) para
que `tools/apply_migration.py` pueda conectar via psycopg2 desde una PC
sin IPv6 outbound. Ya está activo desde 2026-05-05.

Verificar:
https://supabase.com/dashboard/project/vzuwvsmlyigjtsearxym/settings/addons

## Troubleshooting

| Error | Causa | Fix |
|---|---|---|
| `KEYS_LOCAL.md not found` en logs | Bootstrap no corrió | Repetir paso 2 |
| `psycopg2 module not found` | Python sin libs | Repetir paso 3 |
| `ERR_EMPTY_RESPONSE` en browser | Server no arrancó / atorado | `tail tools/wallpapers/admin_server.log` |
| `Tenant or user not found` | IPv4 apagado en Supabase | Reactivar en dashboard de Supabase |
| Browser abre `localhost:5757` y no `127.0.0.1` | DNS resuelve a IPv6 sin escuchar IPv4 | Editar URL a 127.0.0.1 manualmente o dejar que el .vbs lo abra correctamente |

## Endpoints disponibles

Una vez corriendo, el dashboard tiene 6 tabs:
- **Resumen** (KPIs hero + actividad diaria + categorías)
- **Wallpapers** (top, search, modal con installers/audience)
- **Ingresos** (AdMob revenue daily + top users)
- **Usuarios** (signed-in users con cross-tab name cache)
- **Eventos** (feed live de wallpaper_events)
- **Engagement** (analytics nuevos: tabs visitadas, AURA top, pitch funnel, terms acceptance)

API endpoints en `wp_admin_server.py`:
- `/api/stats`, `/api/daily`, `/api/top-wallpapers`, `/api/top-users`
- `/api/recent-events`, `/api/wallpaper-installers`, `/api/wallpaper-audience`
- `/api/ad-stats`, `/api/ad-revenue-daily`, `/api/ad-top-users`
- `/api/user-lookup?email=X` (forensic cross-table)
- `/api/engagement/*` (8 endpoints — tabs/funnel/aura/events/tutorial/terms/etc.)

## Migrations

Aplicar nuevos archivos `.sql` en `supabase/migrations/`:
```bash
cd /d/Orbix/Pixora-IA
python tools/apply_migration.py supabase/migrations/YYYYMMDD_NNN_name.sql
```
Lee password de `KEYS_LOCAL.md` automáticamente.
