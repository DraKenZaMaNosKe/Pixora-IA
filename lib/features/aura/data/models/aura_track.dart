import '../../../../core/utils/locale_helper.dart';

enum AuraCategory { frequency, nature }

class AuraTrack {
  final String id;
  final AuraCategory category;
  final int? hz;
  final String? chakra;
  final String? colorHex;
  final String? icon;
  final String nameEn;
  final String nameEs;
  final String descEn;
  final String descEs;
  final int durationSec;
  final String audioUrl;
  final String license;
  final String? freesoundUser;
  final int sortOrder;

  const AuraTrack({
    required this.id,
    required this.category,
    required this.hz,
    required this.chakra,
    required this.colorHex,
    required this.icon,
    required this.nameEn,
    required this.nameEs,
    required this.descEn,
    required this.descEs,
    required this.durationSec,
    required this.audioUrl,
    required this.license,
    required this.freesoundUser,
    required this.sortOrder,
  });

  String get displayName => LocaleHelper.isSpanish ? nameEs : nameEn;
  String get displayDescription => LocaleHelper.isSpanish ? descEs : descEn;

  factory AuraTrack.fromJson(Map<String, dynamic> json) {
    return AuraTrack(
      id: json['id'] as String,
      category: (json['category'] as String) == 'frequency'
          ? AuraCategory.frequency
          : AuraCategory.nature,
      hz: json['hz'] as int?,
      chakra: json['chakra'] as String?,
      colorHex: json['color_hex'] as String?,
      icon: json['icon'] as String?,
      nameEn: json['name_en'] as String,
      nameEs: json['name_es'] as String,
      descEn: json['desc_en'] as String,
      descEs: json['desc_es'] as String,
      durationSec: json['duration_sec'] as int,
      audioUrl: json['audio_url'] as String,
      license: json['license'] as String? ?? 'CC0',
      freesoundUser: json['freesound_user'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
