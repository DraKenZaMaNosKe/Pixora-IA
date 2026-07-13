# Continuar en la oficina — pickup 2026-07-13

Handoff de la sesión de casa (madrugada 13 jul). Sigue estos pasos al llegar a
la PC del trabajo para retomar sin perder contexto (secretos, memorias, código).

## 0. LO ÚLTIMO que estábamos haciendo (retomar aquí) 👈

Llegó el **reporte de QA de PrimeTestLab** (testearon v1.7.55; ya vamos en v1.7.58).
Veredicto: **0 críticos, app APROBADA** para seguir en closed testing. 5 hallazgos de
pulido que se arreglan en UN solo release (Google pide 1 update en los 14 días):

- **#1+#2 Status bar** (Major): la barra de Android se encima con la UI, y en el
  onboarding los íconos no se ven. Fix: `SafeArea` + `statusBarIconBrightness` dinámico
  según el fondo de cada pantalla (hoy está hardcodeado a `light` en `home_page.dart:~622`).
- **#3+#4 Bottom nav sobrecargado** (Major): tiene **14 tabs** (máx UX = 5); rompe el
  tutorial (#4 es consecuencia de #3). Fix: rediseño a 5 tabs (abajo).
- **#5 Spacing de listas** (Minor): definir una constante de spacing compartida (8/12dp).
- **+ HUDs off por default** (decisión de Eduardo, NO es del reporte): reloj/ecualizador/
  monitores apagados al aplicar wallpaper; se prenden en Settings→Overlays. Respetar a
  quien YA los tiene encendidos (solo cambiar el default de instalaciones nuevas).

**Rediseño de navegación (EN CURSO):** elegimos la **Opción A** — bottom nav de 5 tabs
`[Fondos · Aura · Crear · Favoritos · Más]` donde **Fondos** es un hub con chips grandes
scrollables (Estáticos·Live·3D·Amor·Cultura·Eventos·Arcano·Día). "Más" = Stories·Tonos·Ajustes.

Hice **6 variantes visuales** en `docs/design/nav_redesign_variants.html` (ábrelo o mándaselo
a Eduardo con SendUserFile — ojo: si está en sesión remota, NO abras Chrome local, mándale el
archivo). **Fable 5 eligió la #6 "Marquesina"**: estructura de cintillo de cine (V5) + píldora
de oro sólido activa (V1) + **Space Grotesk uppercase** (NO Cinzel, que es cliché de AI).
Correcciones de Fable a aplicar al construir en Flutter: tap targets **48dp**, separadores
hairline dorados, el relleno dorado se **DESLIZA** entre secciones + micro-flicker de
"encendido" (no loop), rombo ◆ como indicador del tab activo, **CERO blur** (jank en Samsung
gama media).

**PENDIENTE inmediato:** Eduardo escoge la variante final (revisando el HTML) → construir el
nav elegido en Flutter (`home_page.dart` → `_buildBottomNav` + el hub de Fondos con chips y el
menú "Más") → juntarlo con los fixes de status bar + HUDs off + spacing en el release **v1.7.59**.
Se recomienda frontend-design skill + think hard (o delegar diseño a Fable 5 y revisar).

## 1. Sincroniza secretos + memorias (orbixprivate) — PRIMERO

`KEYS_LOCAL.md` NO vive en este repo (gitignored). Sin él, el cuarto obscuro
(pixora-admin) y el sprite editor NO arrancan (no leen el SERVICE_KEY ni el
password de Postgres). Restáuralo primero:

```bash
cd /d/Orbix/orbixprivate && git pull && bash scripts/bootstrap.sh
```

Esto deja `KEYS_LOCAL.md`, `settings.local.json`, el agente y las memorias en
su lugar (`~/.claude/...` y `D:/Orbix/Pixora-IA/`).

## 2. Trae el código nuevo (Pixora-IA)

```bash
cd /d/Orbix/Pixora-IA && git pull
flutter pub get
```

Rama de trabajo: `play-store-estable`. Último commit del día trae el uploader
de Thanos (`tools/wallpapers/_upload_thanos.py`) + la Hora Free con reloj del
servidor.

## 3. Recrear el CUARTO OBSCURO (pixora-admin + sprite editor)

Los dos son el MISMO servidor: `tools/wallpapers/wp_admin_server.py`, Python
stdlib, puerto **5758**. NO es un repo aparte — vive dentro de Pixora-IA. Lee
`SERVICE_KEY` de `KEYS_LOCAL.md`, así que el paso 1 es obligatorio antes.

Formas de arrancarlo:

- **Admin dashboard** (RESUMEN, WALLPAPERS, INGRESOS, USUARIOS, EVENTOS,
  ENGAGEMENT, TEXTOS, y el panel de **Hora Free**):
  doble click a `tools/wallpapers/launch_admin_silent.vbs`
  → abre `http://127.0.0.1:5758/`
- **Sprite editor** (afinar posición/escala/timings de sprites y cycles):
  doble click a `tools/wallpapers/launch_sprite_editor.vbs`
  → abre `http://127.0.0.1:5758/sprite-editor.html`
- **Manual** (consola, si prefieres ver logs):
  ```bash
  python tools/wallpapers/wp_admin_server.py
  # luego abre http://127.0.0.1:5758/  o  /sprite-editor.html
  ```

> Los `.lnk`/accesos del escritorio son locales de cada PC. En la oficina corre
> los `.vbs` directo, o créate accesos directos apuntando a ellos.
> El puerto es configurable con la env `PIXORA_PORT` si el 5758 está ocupado.

## 4. Flujo de trabajo con Grok (el que funcionó bien — repítelo igual)

Grok corre en SU propia terminal; Claude (aquí) NO le habla directo. El puente
eres tú (copiar/pegar). Reparto que quedó chido:

1. **Claude redacta el prompt** para Grok (reglas de chroma-key, consistencia,
   nombres de archivo, carpeta destino). Clave: pedirle a Grok que use
   `imagine-edit` sobre UNA base para que el cuerpo quede pixel-locked y solo
   cambien ojos/mano → así la animación NO salta.
2. **Tú pegas el prompt en Grok**, Grok genera/guarda/renombra en la carpeta
   que le indicaste (ej. `C:/Users/lalo/Desktop/wallPapers_repo/nuevos/<tema>`).
3. **Tú limpias el chroma verde** (CapCut) O Claude lo hace con un chroma
   automático en Python (PIL) desde las versiones verdes — quedó igual de limpio
   que CapCut y ahorra trabajo. Ver `_upload_thanos.py` (función `chroma`).
4. **Claude arma el canvas_scene** (fondo + frames + cycle) y lo sube: imágenes
   a Storage, spec a `wallpaper-scenes`, entrada en `catalog_index.json`, filas
   en Postgres, y FCM `wallpapers` para invalidar cache.

Plantillas de uploader: `_upload_marvin.py` (blink + sprite cohete) y
`_upload_thanos.py` (cycle ping-pong sin sprite). Copia una y ajústala.

**Tip de alineación cross-aspect**: si el personaje viene en 720x1280 y el
fondo en 1080x1920 (ambos 9:16), pre-escala el personaje a 1080x1920 ANTES del
cover-fit para que ambos escalen por el mismo factor y el personaje caiga en su
lugar (si no, queda gigante/corrido). Ver comentario en `_upload_thanos.py`.

## 5. Estado del proyecto (dónde quedamos)

**v1.7.58+101 — AAB construido, Eduardo lo está subiendo a Play Store (prueba
cerrada).** Ruta: `build/app/outputs/bundle/release/app-release.aab` (145 MB).

Hecho en esta sesión (13 jul madrugada):
- **Hora Free** (happy hour diario 7 min sin ads, 8PM CST fija) — ships
  DORMANT (default OFF, cero riesgo). Reloj del SERVIDOR anti-trampa: cambiar la
  hora del celular ya no la mueve; countdown idéntico en todos los devices
  (validado Samsung vs Huawei). Control on/off en el darkroom (panel Hora Free).
- **Sprites**: rotación + `orient_to_motion` + `art_angle` en px físicos +
  draw-route A→B en el sprite editor. (Requirió AAB nuevo; el contenido no.)
- **Marvin el Marciano** — static + canvas_scene 3D (parpadeo + cohete).
- **Thanos** (`thanos_infinito`) — static + canvas_scene 3D. Cycle del
  guantelete abriéndose/cerrándose con las gemas (6s ping-pong). Frames
  limpiados con chroma automático. Categoría `movies`.
- **Tono Mario 1-UP** (`mario_1up`) subido al pack Gaming (contenido remoto,
  sin release).

## 6. Pendientes (en orden)

1. **Terminar de subir el AAB v1.7.58** a Play Console (Eduardo en eso).
   Notas de versión en el chat (ES + EN, sin mencionar Hora Free porque va
   dormida).
2. **PRODUCCIÓN con ads REALES (martes/miércoles)** — cuando Google autorice
   producción hay que preparar una versión NUEVA (1.7.59+102) con:
   - `ad_service.dart:31` → cambiar el ad unit de TEST
     (`ca-app-pub-3940256099942544/1033173712`) al REAL
     (`ca-app-pub-6734758230109098/6687118537`).
   - **CRÍTICO**: agregar el **Huawei** a `_testDeviceIds` (`ad_service.dart:155`)
     — hoy solo está el Samsung. Sin esto, un tap tuyo en un ad real desde el
     Huawei = self-click = suspensión de AdMob (2da ofensa = ban permanente).
     Falta capturar el device-id de AdMob del Huawei (sale en logcat como
     `setTestDeviceIds(...)` al correr un ad).
   - Bump versión, rebuild AAB, subir a producción.
   - Es difícil de revertir → hacerlo con calma + checklist (proponer think hard).
3. **Activar Hora Free** después de que el lanzamiento respire:
   `python tools/wallpapers/_free_hour_config.py on`  (kill-switch: `off`).
4. **Probar Thanos** en device (3D LIVE → pull-to-refresh → aplicar). Si el
   personaje quedó grande/corrido, afinar en el sprite editor (sin resubir).
5. **Doc maestro** §12: ya se agregó v1.7.58 (§12.53). Sync del board GitHub si
   se shippeó a producción.

## 7. Rollback disponible (por si algo)

- `tools/wallpapers/_markup_backup_2026_07_05.json` — descripciones planas
  previas al markup (por id).
- `tools/wallpapers/_redesc_backup_2026_07_05.json` — nombres/descripciones
  previos a la re-descripción masiva.
- Assets de Thanos originales (verdes + limpios) en
  `C:/Users/lalo/Desktop/wallPapers_repo/nuevos/thanos_new/` (esa carpeta es
  LOCAL, no se sincroniza — cópiala a un USB/Drive si la quieres en la oficina).

## 8. Al cerrar la sesión de la oficina

```bash
cd /d/Orbix/orbixprivate && bash scripts/sync-to-private.sh
git add -A && git commit -m "sync: end-of-session 2026-07-XX from work PC" && git push
```
Y push de Pixora-IA si hiciste cambios de código.
