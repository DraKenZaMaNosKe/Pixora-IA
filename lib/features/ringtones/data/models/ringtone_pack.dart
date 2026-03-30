import '../../../../core/constants/supabase_config.dart';

class RingtoneTone {
  final String id;
  final String name;
  final String file;
  final int duration;
  final String suggestedType; // ringtone, notification, alarm

  const RingtoneTone({
    required this.id,
    required this.name,
    required this.file,
    required this.duration,
    required this.suggestedType,
  });

  String get fileUrl => '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/$file';

  String get durationFormatted {
    if (duration < 60) return '${duration}s';
    return '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}';
  }

  factory RingtoneTone.fromJson(Map<String, dynamic> json) {
    return RingtoneTone(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      file: json['file'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      suggestedType: json['suggestedType'] as String? ?? 'notification',
    );
  }
}

class RingtonePack {
  final String id;
  final String name;
  final String description;
  final String previewImage;
  final String glowColor;
  final String category;
  final List<RingtoneTone> tones;

  const RingtonePack({
    required this.id,
    required this.name,
    required this.description,
    required this.previewImage,
    required this.glowColor,
    required this.category,
    required this.tones,
  });

  String get previewUrl => SupabaseConfig.imageUrl(previewImage);

  List<RingtoneTone> get ringtoneTones =>
      tones.where((t) => t.suggestedType == 'ringtone').toList();
  List<RingtoneTone> get notificationTones =>
      tones.where((t) => t.suggestedType == 'notification').toList();
  List<RingtoneTone> get alarmTones =>
      tones.where((t) => t.suggestedType == 'alarm').toList();

  factory RingtonePack.fromJson(Map<String, dynamic> json) {
    final tonesList = (json['tones'] as List<dynamic>?)
        ?.map((e) => RingtoneTone.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    return RingtonePack(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      previewImage: json['previewImage'] as String? ?? '',
      glowColor: json['glowColor'] as String? ?? '#7C4DFF',
      category: json['category'] as String? ?? 'MISC',
      tones: tonesList,
    );
  }
}
