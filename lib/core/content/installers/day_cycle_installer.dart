import '../../../features/day_cycle/data/models/day_cycle_theme.dart';
import '../../services/day_cycle_service.dart';
import '../content_types.dart';
import 'content_installer.dart';

class DayCycleInstaller extends ContentInstaller {
  @override
  Future<bool> install(
    String localPath,
    ContentItem item,
    InstallTarget target,
  ) async {
    try {
      // DayCycleService handles its own downloads internally.
      // The ContentItem metadata carries the DayCycleTheme.
      final theme = item.meta<DayCycleTheme>('theme');
      if (theme == null) return false;

      final wallpaperTarget = target == InstallTarget.lockScreen ? 1 : 0;
      return await DayCycleService.instance.activate(
        theme,
        target: wallpaperTarget,
      );
    } catch (_) {
      return false;
    }
  }
}
