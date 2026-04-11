import '../../../features/aura/data/models/aura_track.dart';
import '../../../features/aura/services/aura_download_service.dart';
import '../../../features/aura/services/aura_player_service.dart';
import '../content_types.dart';
import 'content_installer.dart';

class AuraInstaller extends ContentInstaller {
  @override
  Future<bool> install(
      String localPath, ContentItem item, InstallTarget target) async {
    try {
      if (target == InstallTarget.play) {
        // Streaming play — localPath not needed, use the audio URL
        final track = _toAuraTrack(item);
        await AuraPlayerService.instance.play(track);
        return true;
      }

      if (target == InstallTarget.offline) {
        // Save for offline — download to aura cache
        final track = _toAuraTrack(item);
        final file = await AuraDownloadService.instance.download(track);
        return file != null;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  AuraTrack _toAuraTrack(ContentItem item) {
    return AuraTrack(
      id: item.id,
      category: item.meta<String>('category') == 'frequency'
          ? AuraCategory.frequency
          : AuraCategory.nature,
      hz: item.meta<int>('hz'),
      chakra: item.meta<String>('chakra'),
      colorHex: item.meta<String>('colorHex'),
      icon: item.meta<String>('icon'),
      nameEn: item.meta<String>('nameEn') ?? item.name ?? '',
      nameEs: item.meta<String>('nameEs') ?? item.name ?? '',
      descEn: item.meta<String>('descEn') ?? '',
      descEs: item.meta<String>('descEs') ?? '',
      durationSec: item.meta<int>('durationSec') ?? 0,
      audioUrl: item.meta<String>('audioUrl') ?? '',
      license: item.meta<String>('license') ?? 'CC0',
      freesoundUser: item.meta<String>('freesoundUser'),
      sortOrder: item.meta<int>('sortOrder') ?? 0,
    );
  }
}
