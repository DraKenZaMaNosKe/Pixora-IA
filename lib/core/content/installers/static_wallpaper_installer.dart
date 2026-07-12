import '../../services/wallpaper_service.dart';
import '../content_types.dart';
import 'content_installer.dart';

class StaticWallpaperInstaller extends ContentInstaller {
  @override
  Future<bool> install(
      String localPath, ContentItem item, InstallTarget target) async {
    final isHomeOrBoth = target == InstallTarget.homeScreen ||
        target == InstallTarget.bothScreens;
    if (isHomeOrBoth) {
      final sceneId =
          await WallpaperService.instance.resolveCanvasSceneFromPath(localPath);
      if (sceneId != null && sceneId.isNotEmpty) {
        return WallpaperService.instance.setLiveWallpaper(
          localPath,
          item.glowColor,
          interactive: item.interactive,
          sceneId: sceneId,
          contentId: item.id,
        );
      }
    }
    final wallpaperTarget = switch (target) {
      InstallTarget.homeScreen => 0,
      InstallTarget.lockScreen => 1,
      _ => 2,
    };
    return WallpaperService.instance.setWallpaper(localPath, wallpaperTarget);
  }
}
