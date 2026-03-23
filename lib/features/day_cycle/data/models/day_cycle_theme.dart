import '../../../../core/constants/supabase_config.dart';

class DayCycleTheme {
  final String id;
  final String name;
  final String description;
  final String previewImage;
  final String morningImage;
  final String afternoonImage;
  final String eveningImage;
  final String nightImage;
  final String glowColor;

  const DayCycleTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.previewImage,
    required this.morningImage,
    required this.afternoonImage,
    required this.eveningImage,
    required this.nightImage,
    this.glowColor = '#7C4DFF',
  });

  String get previewUrl => SupabaseConfig.imageUrl(previewImage);
  String get morningUrl => SupabaseConfig.imageUrl(morningImage);
  String get afternoonUrl => SupabaseConfig.imageUrl(afternoonImage);
  String get eveningUrl => SupabaseConfig.imageUrl(eveningImage);
  String get nightUrl => SupabaseConfig.imageUrl(nightImage);

  /// All 4 period image filenames
  List<String> get allImages => [morningImage, afternoonImage, eveningImage, nightImage];

  /// Get the image filename for the current time of day
  String imageForCurrentPeriod() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return morningImage;
    if (hour >= 12 && hour < 18) return afternoonImage;
    if (hour >= 18 && hour < 21) return eveningImage;
    return nightImage;
  }

  /// Period label for the current time
  static String currentPeriodLabel() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 18) return 'Afternoon';
    if (hour >= 18 && hour < 21) return 'Evening';
    return 'Night';
  }

  factory DayCycleTheme.fromJson(Map<String, dynamic> json) {
    return DayCycleTheme(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      previewImage: json['previewImage'] as String? ?? '',
      morningImage: json['morningImage'] as String? ?? '',
      afternoonImage: json['afternoonImage'] as String? ?? '',
      eveningImage: json['eveningImage'] as String? ?? '',
      nightImage: json['nightImage'] as String? ?? '',
      glowColor: json['glowColor'] as String? ?? '#7C4DFF',
    );
  }
}
