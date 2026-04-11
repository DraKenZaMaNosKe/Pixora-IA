import '../../services/story_rotation_service.dart';
import '../content_types.dart';
import 'content_installer.dart';

class StoryInstaller extends ContentInstaller {
  @override
  Future<bool> install(
    String localPath,
    ContentItem item,
    InstallTarget target,
  ) async {
    try {
      final storyId = item.id;
      final imagePaths = item.meta<List<String>>('imagePaths') ?? [localPath];
      final captions = item.meta<List<String>>('captions') ?? [];
      final intervalMinutes = item.meta<int>('intervalMinutes') ?? 30;

      return await StoryRotationService.instance.startStory(
        storyId: storyId,
        imagePaths: imagePaths,
        captions: captions,
        glowColor: item.glowColor,
        intervalMinutes: intervalMinutes,
      );
    } catch (_) {
      return false;
    }
  }
}
