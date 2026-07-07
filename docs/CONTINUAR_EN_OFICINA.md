# Continuar en la oficina — pickup 2026-07-06

Handoff de la sesión de casa. Sigue estos pasos al llegar a la PC del trabajo
para retomar sin perder contexto (secretos, memorias, código).

## 1. Sincroniza secretos + memorias (orbixprivate)

`KEYS_LOCAL.md` NO vive en este repo (gitignored). Sin él, el pixora-admin y
el sprite editor NO arrancan (no leen el SERVICE_KEY). Restáuralo primero:

```bash
cd /d/Orbix/orbixprivate && git pull && bash scripts/bootstrap.sh
```

Esto deja `KEYS_LOCAL.md`, `settings.local.json` y las memorias en su lugar.

## 2. Trae el código nuevo (Pixora-IA)

```bash
cd /d/Orbix/Pixora-IA && git pull
flutter pub get
```

Rama de trabajo: `play-store-estable`. El último commit trae las descripciones
con color + typewriter autoscroll (v1.7.53).

## 3. Lanza pixora-admin / sprite editor

Los dos son el MISMO servidor (`tools/wallpapers/wp_admin_server.py`, puerto
**5758**). Formas de arrancarlo:

- **Sprite editor** (para afinar posiciones de sprites/parejas):
  doble click a `tools/wallpapers/launch_sprite_editor.vbs`
  → abre `http://127.0.0.1:5758/sprite-editor.html`
- **Admin dashboard** (RESUMEN, WALLPAPERS, INGRESOS, TEXTOS, etc.):
  doble click a `tools/wallpapers/launch_admin_silent.vbs`
  → abre `http://127.0.0.1:5758/`
- **Manual** (si prefieres consola):
  ```bash
  python tools/wallpapers/wp_admin_server.py
  # luego abre http://127.0.0.1:5758/  o  /sprite-editor.html
  ```

> Los `.lnk` del escritorio son locales de cada PC. En la oficina corre los
> `.vbs` directo (o créate accesos directos apuntando a ellos).

## 4. Estado del proyecto (dónde quedamos)

**v1.7.53+96 — lista, AAB construido, PENDIENTE de subir a Play Store.**

Hecho en esta sesión:
- 7 parejas anime parallax publicadas en la sección **Amor** (canvas_scene).
- Descripciones con **resaltado por colores** (name/place/power/emotion) en
  **451** wallpapers del catálogo. El markup vive en `description_rich`;
  `description` quedó en texto plano (las versiones viejas no se rompen).
- **TypewriterText** con **autoscroll** que sigue la lectura.
- Bump a `1.7.53+96`.

## 5. Pendientes (en orden)

1. **Subir el AAB** a Play Console:
   `build/app/outputs/bundle/release/app-release.aab` (144.9 MB, v1.7.53+96).
   Ojo: si haces `flutter clean`, tendrás que reconstruirlo (`flutter build
   appbundle`) — Windows necesita "Modo de desarrollador" activo para los
   symlinks de plugins.
2. **Invalidar cache FCM** del catálogo (broadcast a todos) para que los
   usuarios que actualicen vean los 451 textos con color sin esperar el TTL.
   Es un broadcast deliberado — confirmar antes de dispararlo.
3. **Doc maestro** §12 (Registro de Versiones): agregar v1.7.53.
4. (Opcional) Afinar en el **sprite editor** las posiciones de las 7 parejas
   si alguna no quedó bien centrada.

## 6. Rollback disponible (por si algo)

- `tools/wallpapers/_markup_backup_2026_07_05.json` — descripciones planas
  previas al markup (por id).
- `tools/wallpapers/_redesc_backup_2026_07_05.json` — nombres/descripciones
  previos a la re-descripción masiva.

## 7. Al cerrar la sesión de la oficina

```bash
cd /d/Orbix/orbixprivate && bash scripts/sync-to-private.sh
git add -A && git commit -m "sync: end-of-session 2026-07-XX from work PC" && git push
```
Y push de Pixora-IA si hiciste cambios de código.
