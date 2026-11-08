import '../dav/webdav.dart';
import 'media_identity.dart';

enum ScrapeArtifactKind { nfo, image }

class ScrapeArtifact {
  const ScrapeArtifact(this.path, this.kind, {this.fingerprint});
  final String path;
  final ScrapeArtifactKind kind;
  final String? fingerprint;
}

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'tbn', 'gif'};
const _videoExtensions = {
  'mkv', 'mp4', 'avi', 'mov', 'wmv', 'flv', 'ts', 'm2ts', 'webm', //
  'rmvb', 'iso', 'm4v', 'mpg', 'mpeg',
};
const _artworkNames = {
  'poster',
  'fanart',
  'banner',
  'clearlogo',
  'clearart',
  'logo',
  'landscape',
  'thumb',
  'disc',
  'discart',
  'folder',
  'backdrop',
  'keyart',
  'characterart',
};

/// Folders that only hold scraper artwork; their images are always matched.
const scrapeArtworkFolders = {'.actors', 'extrafanart', 'extrathumbs'};

final _artworkSuffix = RegExp('^(.*)-(${_artworkNames.join('|')})\$');
final _seasonArtwork = RegExp(
  r'^season(?:\d{2,4}|-specials|-all)-(?:poster|fanart|banner|landscape|thumb)$',
);
final _numberedArtwork = RegExp(r'^(?:fanart|backdrop)\d{1,3}$');

String _extension(String name) => name.contains('.')
    ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
    : '';

/// Classifies files written by Azusa or common scrapers (Kodi, Jellyfin,
/// Emby, tinyMediaManager). [videoBases] holds lower-case base names of the
/// videos in the same folder.
ScrapeArtifactKind? classifyScrapeFile(
  String name,
  Set<String> videoBases, {
  bool artworkFolder = false,
}) {
  final extension = _extension(name);
  if (extension == 'nfo') return ScrapeArtifactKind.nfo;
  if (!_imageExtensions.contains(extension)) return null;
  if (artworkFolder) return ScrapeArtifactKind.image;
  final base = fileBaseName(name).toLowerCase();
  if (_artworkNames.contains(base) ||
      _seasonArtwork.hasMatch(base) ||
      _numberedArtwork.hasMatch(base) ||
      videoBases.contains(base)) {
    return ScrapeArtifactKind.image;
  }
  final suffix = _artworkSuffix.firstMatch(base);
  if (suffix != null && videoBases.contains(suffix.group(1))) {
    return ScrapeArtifactKind.image;
  }
  return null;
}

/// Finds and deletes scraper output (NFO files and artwork) below a folder.
class ScrapeCleaner {
  ScrapeCleaner(this.dav);
  final WebDavClient dav;

  Future<List<ScrapeArtifact>> scan(
    String root, {
    void Function(String)? onProgress,
    void Function()? checkCancelled,
  }) async {
    final result = <ScrapeArtifact>[];
    final visited = <String>{};
    final rootName = decodedSegments(root).lastOrNull?.toLowerCase();
    final pending = <(String, bool)>[
      (root, scrapeArtworkFolders.contains(rootName)),
    ];
    while (pending.isNotEmpty) {
      checkCancelled?.call();
      final (path, artworkFolder) = pending.removeLast();
      if (!visited.add(path)) continue;
      onProgress?.call(path);
      final entries = await dav.listAll(path);
      checkCancelled?.call();
      if (entries.any((e) => !e.path.startsWith(path) || e.path == path)) {
        throw StateError('目录响应无效：$path');
      }
      final videoBases = {
        for (final entry in entries)
          if (!entry.directory &&
              _videoExtensions.contains(_extension(entry.name)))
            fileBaseName(entry.name).toLowerCase(),
      };
      for (final entry in entries) {
        if (entry.directory) {
          final name = entry.name;
          final artwork = scrapeArtworkFolders.contains(name.toLowerCase());
          if (artwork ||
              (!artworkFolder &&
                  !name.startsWith('.') &&
                  name != '#recycle' &&
                  name != '__MACOSX' &&
                  name != '@eaDir')) {
            pending.add((entry.path, artwork));
          }
          continue;
        }
        final kind = classifyScrapeFile(
          entry.name,
          videoBases,
          artworkFolder: artworkFolder,
        );
        if (kind != null) {
          result.add(
            ScrapeArtifact(entry.path, kind, fingerprint: entry.fingerprint),
          );
        }
      }
    }
    return result..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Deletes [selected] after re-checking each file. Changed or missing files
  /// are skipped; any failure stops the cleanup without rollback.
  Future<({int deleted, int skipped})> clean(
    String root,
    Iterable<ScrapeArtifact> selected, {
    void Function()? checkCancelled,
    Future<void> Function(String)? onDeleting,
    Future<void> Function(String)? onDeleted,
    void Function(int deleted, int skipped)? onProgress,
  }) async {
    var deleted = 0;
    var skipped = 0;
    for (final artifact in selected) {
      checkCancelled?.call();
      final path = artifact.path;
      if (!root.endsWith('/') ||
          dav.normalize(path) != path ||
          !path.startsWith(root) ||
          path.endsWith('/')) {
        throw StateError('文件超出清理范围');
      }
      final current = await dav.stat(path);
      checkCancelled?.call();
      if (current == null ||
          current.directory ||
          (artifact.fingerprint != null &&
              current.fingerprint != artifact.fingerprint)) {
        skipped++;
      } else {
        await onDeleting?.call(path);
        checkCancelled?.call();
        await dav.remove(path);
        deleted++;
        await onDeleted?.call(path);
      }
      onProgress?.call(deleted, skipped);
    }
    return (deleted: deleted, skipped: skipped);
  }
}
