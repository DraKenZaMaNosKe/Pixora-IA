# Pixora — Documentos Legales

Esta carpeta contiene los documentos legales en estado **borrador**, listos
para revisión profesional antes de pasar a producción.

## Archivos

| Archivo | Propósito | Estado |
|---|---|---|
| `terms_v1.md` | Términos y Condiciones de Uso | 🔶 Borrador — pendiente revisión legal |
| `privacy_v1.md` | Aviso de Privacidad (LFPDPPP) | 🔶 Borrador — pendiente revisión legal |

## Para la persona que revise (abogado/a)

1. **Buscar todos los marcadores `[PENDIENTE]`** y completar con los datos
   reales: razón social, RFC, domicilio fiscal, correo formal de privacidad,
   correo de contacto, dirección web pública.
2. **Validar** que las cláusulas se ajusten a:
   - Ley Federal del Derecho de Autor (México)
   - Ley Federal de Protección al Consumidor (México)
   - Ley Federal de Protección de Datos Personales en Posesión de los
     Particulares (LFPDPPP) y su Reglamento
   - Lineamientos del INAI sobre Avisos de Privacidad
   - Políticas de Google Play (Developer Program Policies, Subscriptions,
     Data Safety, Family Policy si aplica)
   - Políticas de App Store (Apple) si se publica en iOS
3. **Confirmar** la jurisdicción: actualmente Guadalajara, Jalisco —
   ajustar si el responsable está en otra entidad.
4. **Revisar** la limitación de responsabilidad — el monto cap (\$1,000 MXN
   o 12 meses de pagos) es estándar pero puede ajustarse al riesgo.
5. **Ratificar** el manejo de menores (mínimo 13 años) y si aplica COPPA
   (US) por distribución global vía Play Store.
6. **Confirmar** las prácticas reales contra lo que dicen los documentos:
   - El Aviso de Privacidad lista qué datos se recolectan — debe coincidir
     EXACTAMENTE con lo que la App realmente recolecta. La sección 2 del
     Aviso es la que más se compara.
   - Los terceros listados (Supabase, Google AdMob, modelos de IA) deben
     ser exactamente los activos en producción.

## Después de la revisión legal

1. Reemplazar todos los `[PENDIENTE]`.
2. Eliminar las cajas de aviso amarillas (`> ⚠️ AVISO IMPORTANTE — DOCUMENTO
   PRELIMINAR`).
3. Actualizar la versión: `Versión 1.0 — Documento preliminar` →
   `Versión 1.0 — Aprobado`.
4. Convertir a HTML (puedes usar Pandoc:
   `pandoc terms_v1.md -o terms_v1.html --standalone --metadata title="Términos y Condiciones"`).
5. Subir a Supabase Storage en el bucket `legal/`:
   - `legal/v1/terms_es.html`
   - `legal/v1/terms_en.html` (traducción si aplica)
   - `legal/v1/privacy_es.html`
   - `legal/v1/privacy_en.html`
6. Configurar las URLs públicas en:
   - **Play Console** → Privacy Policy URL (obligatorio).
   - **Pixora app** → constantes en `lib/core/services/legal_service.dart`
     (cuando se implemente).

## Versionado

Cuando se modifique cualquier documento:

- Crear un archivo nuevo (`terms_v2.md`, `privacy_v2.md`).
- Conservar las versiones anteriores en esta carpeta.
- Registrar en Supabase la versión que cada Usuario aceptó (tabla
  `user_terms_acceptance`) para tener evidencia legal.
- Notificar a los Usuarios al iniciar sesión cuando hay versión nueva.

## Costos esperados de revisión

Estimado en México (2026):

- Revisión inicial completa de ambos documentos: **\$2,000 — \$5,000 MXN**.
- Customización por iteración (cambios estructurales): adicional según
  abogado.
- Traducción profesional al inglés (si se requiere): **\$1,500 — \$3,000
  MXN** por documento, con un traductor jurado.

Recomendado buscar abogado especializado en **derecho digital** o **propiedad
intelectual** para asegurar que las cláusulas de IA generativa, suscripciones
y datos personales queden bien blindadas.
