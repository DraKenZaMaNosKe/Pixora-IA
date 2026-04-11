import '../content_types.dart';

/// Base interface for all content installers.
/// Each content type implements this with its specific install logic.
abstract class ContentInstaller {
  /// Install content from a local file path.
  /// Returns true on success, false on failure.
  Future<bool> install(
    String localPath,
    ContentItem item,
    InstallTarget target,
  );
}
