import '../../services/wallpaper_service.dart';
import '../content_types.dart';
import 'content_installer.dart';

class StaticWallpaperInstaller extends ContentInstaller {
  @override
  Future<bool> install(
      String localPath, ContentItem item, InstallTarget target) {
    final wallpaperTarget = switch (target) {
      InstallTarget.homeScreen => 0,
      InstallTarget.lockScreen => 1,
      _ => 2,
    };
    return WallpaperService.instance.setWallpaper(localPath, wallpaperTarget);
  }
}
