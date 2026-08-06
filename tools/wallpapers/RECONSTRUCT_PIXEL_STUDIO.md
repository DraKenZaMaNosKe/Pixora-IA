# 🛠️ Reconstruir Pixel Studio + ambiente de trabajo (otra PC)

Guía para levantar en **otra computadora** (p. ej. la del trabajo) el mismo
ambiente que tenemos en casa: **Pixel Studio** (el dashboard de administración
en `http://127.0.0.1:5758/`) + los scripts de contenido y estadísticas.

> **Prompt rápido para pegarle a Claude en la PC del trabajo:**
>
> *"Voy a reconstruir el ambiente de Pixora IA en esta PC. Lee
> `tools/wallpapers/RECONSTRUCT_PIXEL_STUDIO.md` del repo Pixora-IA y guíame /
> ejecútalo paso a paso: clonar repos, restaurar secretos desde orbixprivate,
> instalar dependencias de Python y levantar Pixel Studio en el puerto 5758."*

---

## Qué es Pixel Studio

Servidor web local (Python stdlib, sin framework) que administra el contenido y
las métricas de Pixora IA. **NO es un repo aparte** — vive dentro de Pixora-IA en
`tools/wallpapers/`:

- **Server:** `tools/wallpapers/wp_admin_server.py` (HTTP en `127.0.0.1:5758`)
- **Frontend:** `tools/wallpapers/dashboard/darkroom.html`
- **Editor de sprites:** `tools/wallpapers/dashboard/sprite-editor.html`
- **Tabs:** Resumen · Revelado · Ingresos · Usuarios (incl. Cuentas por correo) ·
  Eventos · Escenas · Textos · Tonos · En Vivo · Estadísticas

Lee secretos de `KEYS_LOCAL.md` (SERVICE_KEY de Supabase, password de Postgres).

## Requisitos previos

- **Python 3.12+** (el launcher busca Python 3.12/3.13/3.14)
- **git** + acceso a los repos privados en GitHub (cuenta DraKenZaMaNosKe)
- (Solo si vas a compilar la app) **Flutter** + **Android SDK** + Java 11

## Paso 1 — Clonar los dos repos

```bash
# El repo principal (código de la app + tooling + Pixel Studio)
git clone https://github.com/DraKenZaMaNosKe/Pixora-IA.git D:/Orbix/Pixora-IA

# El repo privado (secretos, memorias, agentes, service accounts)
git clone https://github.com/DraKenZaMaNosKe/orbixprivate.git D:/Orbix/orbixprivate
```

## Paso 2 — Restaurar secretos y memorias

```bash
cd /d/Orbix/orbixprivate && git pull && bash scripts/bootstrap.sh
```

Esto restaura a sus ubicaciones:
- `KEYS_LOCAL.md` → `D:/Orbix/Pixora-IA/KEYS_LOCAL.md` (lo que lee Pixel Studio)
- `settings.local.json`, memorias (`~/.claude/...`), agentes user-scope
- Service account de Firebase → `D:/Orbix/orbixprivate/secrets/pixora-firebase/`

⚠️ Sin este paso, Pixel Studio arranca pero **no puede leer datos** (le falta la
SERVICE_KEY / password de Postgres).

## Paso 3 — Instalar dependencias de Python

```bash
pip install -r D:/Orbix/Pixora-IA/tools/requirements.txt
```

(psycopg2-binary, requests, google-auth, Pillow, openpyxl, python-docx)

## Paso 4 — Levantar Pixel Studio

**Opción A (recomendada, silenciosa):** doble clic al acceso directo de
`tools/wallpapers/launch_admin_silent.vbs` (mata instancias viejas, libera el
puerto 5758 y abre el navegador solo).

**Opción B (manual, para ver logs):**
```bash
cd /d/Orbix/Pixora-IA/tools/wallpapers && python wp_admin_server.py
# luego abrir http://127.0.0.1:5758/
```

El puerto es configurable con la variable `PIXORA_PORT` (default 5758).

## Paso 5 — Sincronizar al terminar (para no perder el trabajo)

```bash
cd /d/Orbix/orbixprivate && bash scripts/sync-to-private.sh
git add -A && git commit -m "sync: end-of-session from work PC" && git push
```

Y en Pixora-IA, commitear/pushear los cambios de código/tooling como siempre
(rama `desarrollo` para trabajo diario).

---

## Notas

- **La base de datos (Supabase) es la misma** desde cualquier PC — es en la nube.
  Pixel Studio solo necesita la SERVICE_KEY para leerla. No hay que "migrar datos".
- **Los archivos de estadísticas** viven en Google Drive
  (`.../claude_compartido/tiktok/stadistics/`) — se sincronizan solos con Drive.
  Su copia versionada va en orbixprivate (ver `sync-to-private.sh`).
- **Las vistas SQL** (`admin_accounts`, `admin_anon_devices`, etc.) ya están en
  Supabase (nube) — no hay que recrearlas por PC. Su definición queda respaldada
  en `supabase/migrations/`.
