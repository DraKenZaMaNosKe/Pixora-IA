import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

/// Texto que se escribe solo, carácter por carácter, como máquina de
/// escribir — para que el usuario lea la historia del wallpaper mientras
/// aparece (Eduardo 2026-07-05: "no solo es una imagen sino una historia").
///
/// Soporta un markup semántico ligero para resaltar palabras con color:
///   `[[name:Serenity]]`  → estilo del rol `name` (nombres propios).
///   `[[key:amor eterno]]` → estilo del rol `key` (conceptos/lecciones).
/// Los roles y sus estilos los define quien usa el widget vía
/// [highlightStyles]; un rol sin estilo cae al [style] base. El markup NO
/// cuenta para el efecto de escritura: se teclea el texto plano visible, y
/// cada segmento aparece con su color en cuanto le toca su turno.
///
/// Detalles de diseño:
///  - El texto COMPLETO se pinta transparente debajo del visible, así el
///    layout reserva su altura final desde el frame 1 y nada brinca
///    mientras se escribe (el CTA no se mueve).
///  - Pausas naturales en puntuación (más largas en `.` `—`, cortas en `,`)
///    para que el ritmo se sienta humano, no metrónomo.
///  - Cursor fino que parpadea mientras escribe y desaparece al terminar.
///  - Respeta `MediaQuery.disableAnimations` (accesibilidad): muestra todo
///    el texto al instante.
class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    super.key,
    this.style,
    this.highlightStyles = const {},
    this.textAlign = TextAlign.center,
    this.charInterval = const Duration(milliseconds: 30),
    this.startDelay = const Duration(milliseconds: 400),
    this.cursorColor,
    this.scrollController,
    this.autoScrollAlignment = 0.62,
  });

  /// Texto crudo, opcionalmente con markup `[[rol:contenido]]`.
  final String text;
  final TextStyle? style;

  /// Estilos por rol de resaltado. La clave es el rol usado en el markup
  /// (`name`, `key`, …); el valor se fusiona SOBRE [style], así basta con
  /// dar `color`/`fontWeight` y el resto se hereda del base.
  final Map<String, TextStyle> highlightStyles;

  final TextAlign textAlign;

  /// Ritmo base por carácter (~33 chars/seg con el default de 30ms —
  /// apenas arriba de la velocidad de lectura, se lee cómodo en vivo).
  final Duration charInterval;

  /// Espera antes de empezar a escribir, para que la transición de
  /// página termine de asentarse.
  final Duration startDelay;

  /// Color del cursor. Default: el color del estilo del texto.
  final Color? cursorColor;

  /// Si se provee, el widget hace autoscroll conforme escribe para mantener
  /// la última línea visible (Eduardo 2026-07-05: "que se vaya haciendo
  /// autoscroll para mantener el foco en la lectura"). Debe ser el mismo
  /// controller del scroll view que contiene a este texto.
  final ScrollController? scrollController;

  /// Dónde dejar el cursor dentro del viewport al autoscrollear (0 = arriba,
  /// 1 = abajo). 0.62 ≈ zona de lectura cómoda, un poco abajo del centro.
  final double autoScrollAlignment;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

/// Patrón del markup `[[rol:contenido]]`. Compartido por el parser y el
/// helper [stripTypewriterMarkup].
final RegExp _kMarkup = RegExp(r'\[\[(\w+):(.*?)\]\]', dotAll: true);

/// Devuelve el texto sin markup — para cualquier lugar que muestre la
/// descripción cruda (búsqueda, compartir, cards). `[[name:Goku]]` → `Goku`.
String stripTypewriterMarkup(String raw) =>
    raw.replaceAllMapped(_kMarkup, (m) => m.group(2) ?? '');

/// Un tramo de texto con su rol de resaltado (`null` = texto normal).
class _Seg {
  const _Seg(this.text, this.role);
  final String text;
  final String? role;
}

/// Parte el texto crudo en segmentos, extrayendo el markup `[[rol:texto]]`.
/// El texto entre marcas queda con rol `null`. Robusto ante marcas
/// malformadas: lo que no casa el patrón se trata como texto normal.
List<_Seg> _parseSegments(String raw) {
  final segs = <_Seg>[];
  var last = 0;
  for (final m in _kMarkup.allMatches(raw)) {
    if (m.start > last) segs.add(_Seg(raw.substring(last, m.start), null));
    segs.add(_Seg(m.group(2) ?? '', m.group(1)));
    last = m.end;
  }
  if (last < raw.length) segs.add(_Seg(raw.substring(last), null));
  return segs;
}

class _TypewriterTextState extends State<TypewriterText> {
  Timer? _timer;
  int _visible = 0;
  int _pauseTicks = 0;
  bool _started = false;

  late List<_Seg> _segs;
  late String _plain; // texto sin markup, sobre el que corre la escritura

  // ── Autoscroll ──────────────────────────────────────────────────────────
  double _lastAutoOffset = 0; // último destino al que animamos
  bool _animating = false; // true mientras corre nuestra animateTo
  bool _userInterrupted = false; // el usuario subió a mano → dejamos de seguir

  @override
  void initState() {
    super.initState();
    _rebuild();
    widget.scrollController?.addListener(_onUserScroll);
  }

  /// Si el usuario se desplaza hacia arriba de donde dejamos el scroll,
  /// asumimos que quiere leer a su ritmo y dejamos de autoscrollear.
  void _onUserScroll() {
    if (_animating || _userInterrupted) return;
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return;
    if (sc.offset < _lastAutoOffset - 24) _userInterrupted = true;
  }

  void _scheduleAutoScroll() {
    if (widget.scrollController == null || _userInterrupted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScroll());
  }

  void _autoScroll() {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients || _userInterrupted || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final width = box.size.width;
    final base = widget.style ?? const TextStyle();
    // Altura del texto revelado hasta el cursor, en coords locales del widget.
    final tp = TextPainter(
      text: TextSpan(
          text: _plain.substring(0, _visible.clamp(0, _plain.length)),
          style: base),
      textDirection: TextDirection.ltr,
      textAlign: widget.textAlign,
    )..layout(maxWidth: width);
    final cursorY = tp.height;
    // Offset de scroll que llevaría el punto (0, cursorY) al top del viewport.
    final reveal = RenderAbstractViewport.of(box)
        .getOffsetToReveal(box, 0.0, rect: Rect.fromLTWH(0, cursorY, width, 1))
        .offset;
    final vpDim = sc.position.viewportDimension;
    final target = (reveal - vpDim * widget.autoScrollAlignment)
        .clamp(0.0, sc.position.maxScrollExtent);
    final fontSize = base.fontSize ?? 14;
    final lineH = fontSize * (base.height ?? 1.3);
    // Solo hacia abajo, y solo si avanzó ~media línea (evita micro-jitter).
    if (target > sc.offset + lineH * 0.5) {
      _animating = true;
      _lastAutoOffset = target;
      sc
          .animateTo(target,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut)
          .whenComplete(() => _animating = false);
    }
  }

  void _rebuild() {
    _segs = _parseSegments(widget.text);
    _plain = _segs.map((s) => s.text).join();
  }

  bool get _done => _visible >= _plain.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Accesibilidad: sin animaciones → texto completo de una vez.
    if (MediaQuery.of(context).disableAnimations) {
      _visible = _plain.length;
      return;
    }
    Future.delayed(widget.startDelay, () {
      if (!mounted) return;
      _timer = Timer.periodic(widget.charInterval, _tick);
    });
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _timer?.cancel();
      _rebuild();
      _visible = 0;
      _pauseTicks = 0;
      _timer = Timer.periodic(widget.charInterval, _tick);
    }
  }

  void _tick(Timer t) {
    if (_pauseTicks > 0) {
      _pauseTicks--;
      return;
    }
    if (_done) {
      t.cancel();
      if (mounted) setState(() {}); // repintar sin cursor
      return;
    }
    setState(() {
      _visible++;
      // Pausa según el carácter recién escrito — respiración natural.
      final ch = _plain[_visible - 1];
      _pauseTicks = switch (ch) {
        '.' || '—' || ':' || ';' || '!' || '?' => 7,
        ',' => 3,
        _ => 0,
      };
    });
    _scheduleAutoScroll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.scrollController?.removeListener(_onUserScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final fontSize = base.fontSize ?? 14;
    final showCursor = !_done && _visible > 0;

    final children = <InlineSpan>[];
    var remaining = _visible; // chars visibles globales por repartir
    var cursorPlaced = false;

    TextStyle styleFor(String? role) {
      final hl = role == null ? null : widget.highlightStyles[role];
      return hl == null ? base : base.merge(hl);
    }

    for (final seg in _segs) {
      final segStyle = styleFor(seg.role);
      final vis = remaining.clamp(0, seg.text.length);
      if (vis > 0) {
        children
            .add(TextSpan(text: seg.text.substring(0, vis), style: segStyle));
        remaining -= vis;
      }
      // Cursor de ANCHO CERO justo tras el último char visible: no ocupa
      // espacio en el flujo, así el wrapping es idéntico al del texto final
      // y nada brinca en los bordes de línea mientras escribe.
      if (!cursorPlaced && remaining == 0 && showCursor) {
        cursorPlaced = true;
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(
            width: 0,
            height: fontSize,
            child: OverflowBox(
              maxWidth: 3,
              alignment: Alignment.centerLeft,
              child: Container(
                width: 2,
                height: fontSize * 0.95,
                color:
                    (widget.cursorColor ?? base.color)?.withValues(alpha: 0.85),
              ),
            ),
          ),
        ));
      }
      // Resto transparente: reserva el layout final desde el frame 1,
      // el CTA de abajo nunca se mueve. Conserva el estilo del segmento
      // (con color transparente) para que las métricas coincidan.
      if (vis < seg.text.length) {
        children.add(TextSpan(
          text: seg.text.substring(vis),
          style: segStyle.copyWith(color: Colors.transparent),
        ));
      }
    }

    return Text.rich(
      TextSpan(children: children, style: base),
      textAlign: widget.textAlign,
    );
  }
}
