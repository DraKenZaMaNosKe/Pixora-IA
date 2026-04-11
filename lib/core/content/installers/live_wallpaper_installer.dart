import '../../services/wallpaper_service.dart';
import '../content_types.dart';
import 'content_installer.dart';

class LiveWallpaperInstaller extends ContentInstaller {
  @override
  Future<bool> install(
    String localPath,
    ContentItem item,
    InstallTarget target,
  ) async {
    try {
      await WallpaperService.instance.setLiveWallpaper(
        localPath,
        item.glowColor,
        interactive: item.interactive,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
