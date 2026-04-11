import '../../services/ringtone_service.dart';
import '../content_types.dart';
import 'content_installer.dart';

class RingtoneInstaller extends ContentInstaller {
  @override
  Future<bool> install(
      String localPath, ContentItem item, InstallTarget target) async {
    final type = switch (target) {
      InstallTarget.ringtone => 0,
      InstallTarget.notificationSound => 1,
      InstallTarget.alarmSound => 2,
      _ => 0,
    };
    final name = item.name ?? item.id;
    return RingtoneService.instance.setAsRingtone(localPath, name, type);
  }
}
