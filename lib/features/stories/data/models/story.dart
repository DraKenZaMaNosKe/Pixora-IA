import '../../../../core/constants/supabase_config.dart';

class StoryFrame {
  final String imageFile;
  final String caption;

  const StoryFrame({required this.imageFile, required this.caption});

  String get fullImageUrl => SupabaseConfig.imageUrl(imageFile);

  factory StoryFrame.fromJson(Map<String, dynamic> json) {
    return StoryFrame(
      imageFile: json['imageFile'] as String,
      caption: json['caption'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'imageFile': imageFile,
    'caption': caption,
  };
}

class Story {
  final String id;
  final String title;
  final String description;
  final String coverImage;
  final String glowColor;
  final String category;
  final int intervalMinutes;
  final List<StoryFrame> frames;

  const Story({
    required this.id,
    required this.title,
    required this.description,
    required this.coverImage,
    required this.glowColor,
    required this.category,
    required this.intervalMinutes,
    required this.frames,
  });

  String get coverImageUrl => SupabaseConfig.imageUrl(coverImage);

  factory Story.fromJson(Map<String, dynamic> json) {
    final framesList = (json['frames'] as List<dynamic>?)
        ?.map((e) => StoryFrame.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    return Story(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      coverImage: json['coverImage'] as String,
      glowColor: json['glowColor'] as String? ?? '#7C4DFF',
      category: json['category'] as String? ?? 'STORIES',
      intervalMinutes: json['intervalMinutes'] as int? ?? 30,
      frames: framesList,
    );
  }
}
