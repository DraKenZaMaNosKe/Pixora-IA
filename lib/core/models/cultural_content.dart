/// Optional editorial content for live wallpapers in the "Mitología" /
/// "Cultura" categories. Lives in the catalog JSON so new entries can be
/// added without rebuilding the APK.
///
/// Shape (all fields optional except `facts`, which can be empty):
/// ```json
/// "cultural": {
///   "chapter": "Capítulo IX · Mictlán",
///   "subtitle": "Señor del Inframundo",
///   "pronunciation": "[mik · tlan · te · KU · tli]",
///   "lead": "Esposo de Mictecacíhuatl, gobierna...",
///   "facts": [
///     {"key": "Cultura", "value": "Mexica · Tolteca"},
///     {"key": "Reino",   "value": "Mictlán · 9 niveles"}
///   ],
///   "ofrenda": {"label": "Ofrenda", "text": "Cempasúchil, copal..."},
///   "cta": "Invocar al Señor"
/// }
/// ```
class CulturalContent {
  final String? chapter;
  final String? subtitle;
  final String? pronunciation;
  final String? lead;
  final List<CulturalFact> facts;
  final CulturalOfrenda? ofrenda;
  final String? cta;

  const CulturalContent({
    this.chapter,
    this.subtitle,
    this.pronunciation,
    this.lead,
    this.facts = const [],
    this.ofrenda,
    this.cta,
  });

  bool get isEmpty =>
      (chapter ?? '').isEmpty &&
      (subtitle ?? '').isEmpty &&
      (pronunciation ?? '').isEmpty &&
      (lead ?? '').isEmpty &&
      facts.isEmpty &&
      ofrenda == null &&
      (cta ?? '').isEmpty;
  bool get isNotEmpty => !isEmpty;

  factory CulturalContent.fromJson(Map<String, dynamic> json) {
    return CulturalContent(
      chapter: json['chapter'] as String?,
      subtitle: json['subtitle'] as String?,
      pronunciation: json['pronunciation'] as String?,
      lead: json['lead'] as String?,
      facts: (json['facts'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => CulturalFact.fromJson(e))
              .toList() ??
          const [],
      ofrenda: json['ofrenda'] is Map<String, dynamic>
          ? CulturalOfrenda.fromJson(json['ofrenda'] as Map<String, dynamic>)
          : null,
      cta: json['cta'] as String?,
    );
  }
}

class CulturalFact {
  final String key;
  final String value;

  const CulturalFact({required this.key, required this.value});

  factory CulturalFact.fromJson(Map<String, dynamic> json) => CulturalFact(
        key: json['key'] as String? ?? '',
        value: json['value'] as String? ?? '',
      );
}

class CulturalOfrenda {
  final String label;
  final String text;

  const CulturalOfrenda({required this.label, required this.text});

  factory CulturalOfrenda.fromJson(Map<String, dynamic> json) =>
      CulturalOfrenda(
        label: json['label'] as String? ?? 'Nota',
        text: json['text'] as String? ?? '',
      );
}
