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
Copia `KEYS_LOCAL.md` (Postgres password + service_role JWT + Firebase
service account JSON) a `D:/Orbix/Pixora-IA/KEYS_LOCAL.md`.

### 3. Dependencias Python (una vez por PC)
```bash
pip install psycopg2-binary requests python-docx google-auth
```
⚠️ `google-auth` es fácil de olvidar y **falla en silencio**: sin él,
`_fcm_push.py` no importa y el server cae a un stub que devuelve `False`.
Los cambios de catálogo se guardan bien pero **nunca invalidan el cache de
los devices** — se quedan esperando el TTL de 6 h. Si ves
`FCM push helper unavailable` en el arranque, es esto.

### 4. Crear shortcut de escritorio
```bash
powershell -ExecutionPolicy Bypass -File "D:\Orbix\Pixora-IA\tools\wallpapers\install_admin_shortcut.ps1"
```
Pone "Pixora Admin.lnk" en `OneDrive\Escritorio` apuntando al `.vbs`
que lanza pythonw silencioso.

### 5. Lanzar
Doble click al icono **Pixora Admin** del escritorio. Server arranca
en `http://127.0.0.1:5758/` y abre el browser solo.

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
| Cambios de código del server que "no toman efecto" | **Varios servers en el 5758 a la vez** — Windows deja bindear el puerto a más de un proceso y el viejo contesta | `powershell -Command "Get-NetTCPConnection -LocalPort 5758 -State Listen \| Select -Expand OwningProcess -Unique \| ForEach { Stop-Process -Id $_ -Force }"` y relanzar |
| `fcm_pushed: false` en las respuestas | Falta `google-auth` (ver paso 3) o hay un server viejo sin la lib | Instalar + relanzar server limpio |
| `Tenant or user not found` | IPv4 apagado en Supabase | Reactivar en dashboard de Supabase |
| Browser abre `localhost:5758` y no `127.0.0.1` | DNS resuelve a IPv6 sin escuchar IPv4 | Editar URL a 127.0.0.1 manualmente o dejar que el .vbs lo abra correctamente |
| Error `22P02 invalid_text_representation` al guardar wallpaper | Categoría no existe en el enum `wallpaper_category` | Ver §"Agregar categorías nuevas" abajo |
| Modal del wallpaper muestra nombre viejo | Cache del browser | Ctrl+Shift+R |

## Endpoints disponibles

Una vez corriendo, el dashboard tiene 6 tabs:
- **Resumen** (KPIs hero + actividad diaria + categorías)
- **Wallpapers** (top, search, modal con installers/audience + **CRUD edit**)
- **Ingresos** (AdMob revenue daily + top users)
- **Usuarios** (signed-in users con cross-tab name cache)
- **Eventos** (feed live de wallpaper_events)
- **Engagement** (analytics nuevos: tabs visitadas, AURA top, pitch funnel, terms acceptance)

API endpoints en `wp_admin_server.py`:

**Read-only (proxy a Supabase)**
- `/api/stats`, `/api/daily`, `/api/top-wallpapers`, `/api/top-users`
- `/api/recent-events`, `/api/wallpaper-installers`, `/api/wallpaper-audience`
- `/api/ad-stats`, `/api/ad-revenue-daily`, `/api/ad-top-users`
- `/api/user-lookup?email=X` (forensic cross-table)
- `/api/engagement/*` (8 endpoints — tabs/funnel/aura/events/tutorial/terms/etc.)
- `/api/search?q=&category=` — legacy postgres RPC (solo wallpapers con eventos)

**CRUD (agregado 2026-05-13)**
- `GET /api/catalog/<kind>` — devuelve el JSON catalog de Storage. Kinds: `live`, `static`, `stories`, `day_cycle`, `ringtones`.
- `PUT /api/catalog/<kind>` — upserts el JSON completo a Storage. Valida `items_key` top-level (`wallpapers` / `stories` / `scenes` / `ringtones`).
- `GET /api/catalog-search?q=&category=&kinds=live,static&limit=24&offset=0` — busqueda unificada. Lee del Storage JSON, enriquece con stats + `published` flag desde Postgres. **Esto es lo que alimenta el grid del tab Wallpapers.**
- `POST /api/wallpaper-edit` — body `{kind, id, fields: {...}}`. Para STATIC: UPDATE en Postgres `wallpapers` table + sync al JSON Storage en una operación atómica. Para LIVE: solo JSON Storage. Es el endpoint que llama el botón Guardar del modal.

## Cómo usar el CRUD

Desde el grid del tab Wallpapers:

1. **Buscar**: top searchbar + filtro de categoría (28 categorías válidas en Postgres enum).
2. **Ver detalle**: click en cualquier card → modal con stats + installers + eventos.
3. **Editar**: dentro del modal, botón **✏️ Editar** (aparece si el wallpaper está en el catálogo). Panel desplega con:
   - Nombre, descripción, categoría, sortOrder, badge, glowColor, tags
   - Toggle **"Publicado en la app"** — desmarca para ocultarlo del catálogo público sin eliminarlo
4. **Guardar**: persiste a Postgres (si STATIC) + Storage JSON. Cambios llegan al app cuando expire el cache (TTL 30 min) o cuando el usuario haga pull-to-refresh.
5. **Eliminar del catálogo**: botón rojo. Quita la entry del JSON Storage. No borra archivos en Storage.

**Wallpapers ocultos** muestran en el grid con:
- Filtro grayscale 85% + brightness 60%
- Overlay rojizo con icono 👁❌ y texto "OCULTO"
- Nombre con tachado rojo

## Agregar categorías nuevas

`wallpapers.category` es un enum Postgres llamado `wallpaper_category`. Para
agregar valores nuevos:

```python
import psycopg2
conn = psycopg2.connect(
    host='db.vzuwvsmlyigjtsearxym.supabase.co', port=5432,
    user='postgres', password='<KEYS_LOCAL §Postgres>',
    dbname='postgres', connect_timeout=15
)
conn.autocommit = True  # ALTER TYPE ADD VALUE requiere su propia tx
cur = conn.cursor()
cur.execute("ALTER TYPE wallpaper_category ADD VALUE IF NOT EXISTS 'NUEVA_CAT'")
cur.close(); conn.close()
```

Después, agregar la opción en `tools/wallpapers/dashboard/index.html`:
1. `<select id="me-category">` (modal de edit) — agregar `<option>NUEVA_CAT</option>`
2. Array `CATEGORIES` (filtro del search) — agregar al array

**Valores actuales del enum** (28, al 2026-05-13):
- "Tuyas": PAISAJISMO, TV, ARTE, VARIOS
- Estándar: ANIMALS, ANIME, ARCANO, ART, AURA, CALENDAR, CHILL, CHRISTMAS, CULTURE, DARK, FANTASY, GAMING, HEROES, HORROR, LIFESTYLE, MISC, NATURE, PANORAMIC, PIXEL, SCENES, SCIFI, SPECIAL, UNIVERSE, WALLPAPERS

⚠️ `ALTER TYPE ADD VALUE` es **permanente** — los valores no se pueden borrar (solo renombrar).

## Estructura del catalog (source of truth)

| Kind | Storage bucket | File | Postgres? | Top-level key JSON |
|---|---|---|---|---|
| `static` | `wallpaper-images` | `dynamic_catalog.json` | ✅ tabla `wallpapers` | `wallpapers` |
| `live` | `wallpaper-videos` | `live_wallpaper_catalog.json` | ❌ solo Storage | `wallpapers` |
| `stories` | `wallpaper-images` | `stories_catalog.json` | ❌ solo Storage | `stories` |
| `day_cycle` | `wallpaper-images` | `day_cycle_catalog.json` | ❌ solo Storage | `scenes` |
| `ringtones` | `wallpaper-images` | `ringtones_catalog.json` | ❌ solo Storage | `ringtones` |

**STATIC es especial**: el app lee de la tabla Postgres `wallpapers` (via view `wallpapers_v`). El JSON Storage es **backup/legacy**. Por eso el endpoint `/api/wallpaper-edit` para `kind=static` escribe a AMBOS lados — sin la escritura a Postgres, los cambios no llegan al app.

**Otros catálogos**: el app lee directo del JSON Storage. Editar JSON = cambio inmediato (módulo cache TTL del cliente).

## Standalone dashboard (sin server local)

Si el `wp_admin_server.py` está caído o trabajas desde otra PC sin Python,
existe `tools/wallpapers/dashboard_crud.html` que hace lo básico (CRUD del
catalog live) escribiendo directo a Supabase Storage con SERVICE_KEY:

1. Crear `tools/wallpapers/dashboard_crud_key.local.js` (gitignored):
   ```javascript
   window.SUPABASE_SERVICE_KEY = "eyJ...";  // de KEYS_LOCAL.md §Supabase
   ```
2. Abrir `dashboard_crud.html` directamente en el browser (no necesita server).

**Limitaciones del standalone**:
- Solo edita `live_wallpaper_catalog.json` (no static, no stories)
- No escribe a Postgres → si pruebas en STATIC, los cambios solo llegarán como fallback cuando Postgres falle (raro). No usar para STATIC.

## Scripts de reconciliación (one-shot)

En `tools/wallpapers/`:

- `_reconcile_static_catalog.py` — detecta wallpapers donde el JSON Storage difiere de Postgres y sincroniza **Storage → Postgres**. Útil después de edits manuales al JSON.
- `_reverse_sync_pg_to_storage.py` — el inverso: toma Postgres como fuente de verdad y sobrescribe el JSON Storage. Útil cuando hay desfase y no se sabe qué edit ya llegó.

Ambos scripts leen credenciales de `KEYS_LOCAL.md` automáticamente.

## Migrations

Aplicar nuevos archivos `.sql` en `supabase/migrations/`:
```bash
cd /d/Orbix/Pixora-IA
python tools/apply_migration.py supabase/migrations/YYYYMMDD_NNN_name.sql
```
Lee password de `KEYS_LOCAL.md` automáticamente.

## Backups & cierre de sesión productiva

Antes de apagar la PC al terminar de trabajar:
```bash
cd /d/Orbix/orbixprivate && bash scripts/sync-to-private.sh
# Revisar el diff:
git add -A && git commit -m "sync: end-of-session YYYY-MM-DD from <home|work> PC" && git push
```

Esto respalda:
- KEYS_LOCAL.md actualizado
- Settings locales de Claude Code
- Service account JSONs de Firebase
- Memorias de Claude
- Master doc HTML sanitizado

En la otra PC al iniciar sesión:
```bash
cd /d/Orbix/orbixprivate && git pull && bash scripts/bootstrap.sh
```
