# 🎯 Pixora IA · Producto Terminado

**Fecha de declaración:** 2026-05-05
**Versión cerrada:** v1.7.5+47
**Decisión tomada por:** Eduardo Javier Contreras Román (Orbix Studio)

---

## ⚖️ El pacto

A partir de hoy, **5 de mayo de 2026**, Pixora IA queda declarada como **producto terminado** en términos de funcionalidades. Esto es un compromiso de disciplina explícito.

Lo que esto significa:

### ✅ Permitido a partir de hoy

- **Agregar contenido nuevo** (wallpapers, eventos, tonos, AURA tracks, day cycles, stories)
- **Bugfixes** cuando un crash o malfuncionamiento aparezca en producción
- **Upgrades obligatorios** de Flutter SDK, Android SDK, dependencias críticas de seguridad
- **Cumplimiento legal** con cambios de política de Google Play, LFPDPPP, etc.
- **Marketing y mejoras de comunicación** (screenshots, descripción, ASO, ads)
- **Refactor MENOR** sólo si es necesario para arreglar un bug — nunca por gusto estético

### ❌ Prohibido a partir de hoy

- **NO se agrega ningún feature nuevo** que requiera código.
- **NO se agrega ninguna pantalla nueva.**
- **NO se agrega ninguna tab nueva al bottom nav.**
- **NO se agrega ningún sistema de personalización extra** (incluyendo la idea de tumbas con nombres del Día de Muertos — vetada explícitamente hoy).
- **NO se hacen refactors arquitectónicos** (mover singletons a Riverpod, etc.) "porque sería más limpio".
- **NO se agregan integraciones nuevas** con APIs externas que no estén ya en uso.

### 📅 Duración del pacto

Este compromiso es vigente por **mínimo 60 días** (hasta 2026-07-05).

Después de ese lapso:
- **Si Pixora generó revenue consistente** ($200+/mes): se prorroga automáticamente otros 60 días sin debate.
- **Si los usuarios no pidieron en review/soporte una feature específica**: se prorroga automáticamente.
- **Solo si UNA feature concreta está siendo pedida por múltiples usuarios** y/o bloquea revenue, se evalúa formalmente para una versión futura.

---

## 📦 Lo que Pixora YA es (estado al cierre)

### Funcionalidades core
- ✅ Wallpapers estáticos (catálogo de 280+, 19 categorías)
- ✅ Wallpapers panorámicos 4192×1024 (scroll lateral en home)
- ✅ Wallpapers en video (live wallpapers, MP4 H.264)
- ✅ Wallpapers shader (GPU efects)
- ✅ Wallpapers Day Cycle (4 imágenes morning/afternoon/evening/night)
- ✅ Wallpapers canvas_scene (Mictlantecuhtli, Volcano Dragon, etc.)
- ✅ AutoRotate — rota wallpaper periódicamente con descripciones (estilo Bing Spotlight)
- ✅ Stories visuales temáticas
- ✅ Tonos de llamada y packs
- ✅ AURA — frecuencias Solfeggio + sonidos de naturaleza, con sleep timer
- ✅ Generación de imágenes con IA (Gemini/Grok dependiendo del prompt)
- ✅ Cultura section con códices culturales
- ✅ Eventos por temporada (Día de la Madre, Halloween, Día de Muertos, Navidad, etc.)
- ✅ Arcano (calendario lunar personalizado por signo)
- ✅ Suscripción Pixora Pro ($49 MXN/mes vía Google Play Billing)
- ✅ Welcome gift (1 instalación gratis sin ads para nuevos usuarios)
- ✅ Tutorial guiado con coach marks
- ✅ Sistema de créditos/diamantes (ad rewards)

### Capas técnicas
- ✅ Themes: Black & Gold + iOS White (alternables en runtime)
- ✅ Auth: Google Sign-In opcional vía Supabase
- ✅ Subscription: Google Play Billing + Edge Function `verify_google_purchase`
- ✅ Catálogos dinámicos (Postgres + JSON en Storage)
- ✅ Analytics: `wallpaper_events`, `ad_events`, `app_events` con dedupe
- ✅ Privacy: TermsAcceptanceGate al primer arranque
- ✅ Audit log: aceptación de términos versionada
- ✅ AdMob interstitials con safety timeout 60s
- ✅ Crash recovery: GracePass, Auth disconnect, ad timeout

### Infraestructura
- ✅ Supabase con IPv4 add-on activo
- ✅ Admin dashboard local (`http://127.0.0.1:5757/`)
- ✅ Engagement analytics tab con KPIs y tablas
- ✅ Migrations versionadas en `supabase/migrations/`
- ✅ Tools de mantenimiento (`tools/apply_migration.py`, etc.)
- ✅ orbixprivate como respaldo cross-machine

---

## 🛣️ Roadmap permitido (lo único en lo que se trabaja)

### Q3 2026 (jul-sep)
- 📈 **Marketing**: ASO, screenshots Play Store, video promocional, YouTube ads
- 📊 **Análisis del dashboard**: medir qué tabs se usan, qué eventos enganchan, retention
- ⚖️ **Cierre legal**: revisión de Términos + Privacidad con abogado, subir HTML a Storage
- 🎨 **Producción de contenido**: 30+ wallpapers nuevos vía pipeline AI + diseño

### Q4 2026 (oct-dic)
- 📱 Promoción a track abierto de Play Store (después de Closed Testing exitoso)
- 🎄 Contenido para temporada navideña + Año Nuevo
- 💰 Tracking real de revenue (AdMob + suscripciones)
- 🔄 Refactor a `orbix-core` package para preparar futuras apps

### 2027
- Si Pixora generó revenue justificado, evaluar lanzamiento de **app #2** (probablemente PDF reader como app independiente bajo Orbix Studio)

---

## 🚨 Política de excepciones

Si en algún momento se considera necesario **violar este pacto** (agregar una feature nueva por código), se requiere:

1. **Documentar la justificación** en este mismo archivo (anexar abajo)
2. **Tres usuarios externos** han pedido la feature en review, soporte o entrevista
3. **Estimación clara** de tiempo de desarrollo + impacto en estabilidad
4. **Decisión escrita** de "esta excepción se justifica porque ___"

Sin esos 4 puntos, la respuesta automática es: "No, ese feature va al backlog para evaluación post-pacto."

---

## 📝 Anexos (si se justifica una excepción)

*Ningún anexo todavía. El pacto está intacto.*

---

## 🤝 Compromiso

Yo, Eduardo Javier Contreras Román, declaro este documento como mi compromiso conmigo mismo y con Orbix Studio. La meta no es estancarse — la meta es **dejar de ingenierear y empezar a vender, distribuir, y crecer**.

Pixora ya tiene más feature surface que la mayoría de su competencia directa (Zedge incluido). Lo que falta no es código — es **distribución + tiempo + contenido**.

---

*Documento generado 2026-05-05 al cierre de v1.7.5+47*
