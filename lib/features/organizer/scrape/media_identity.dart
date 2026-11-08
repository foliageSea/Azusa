/// Filename-based media identification for metadata scraping.
///
/// The parser targets names produced by the organizer (`片名 (2014).mkv`,
/// `剧名 - S01E01 - 单集名称.mkv`, dotted variants) and common release names.
/// Matches are only suggestions: the scrape preview lets users deselect them.
library;

enum ScrapeMediaKind { movie, episode }

class MediaGuess {
  const MediaGuess({
    required this.kind,
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.tmdbId,
  });

  final ScrapeMediaKind kind;
  final String title;
  final int? year, season, episode, tmdbId;
}

final _episodePattern = RegExp(
  r'(?<![A-Za-z0-9])[Ss](\d{1,2})[ ._-]?[Ee][Pp]?(\d{1,4})(?!\d)',
);
final _yearPattern = RegExp(r'(?<![0-9])((?:19|20)\d{2})(?![0-9])');
final _tmdbPattern = RegExp(
  r'tmdb(?:id)?[-=_ ]?(\d{1,9})(?!\d)',
  caseSensitive: false,
);
final _tmdbTag = RegExp(
  r'[\[{(]?tmdb(?:id)?[-=_ ]?\d{1,9}[\]})]?',
  caseSensitive: false,
);
final _seasonFolder = RegExp(
  r'^(?:season|series|s)[ ._-]*\d{1,4}$|^第.{1,6}季$|^specials?$|^特别篇$',
  caseSensitive: false,
);
final _extras = RegExp(
  r'(?:^|[ ._\-\[(])(?:sample|trailer|featurette)(?:$|[ ._\-\])])',
  caseSensitive: false,
);
final _releaseTag = RegExp(
  r'(?<![A-Za-z0-9])(?:2160p|1080[pi]|720p|480p|4k|uhd|blu-?ray|bdrip|web-?dl|webrip|hdtv|dvdrip|remux|x26[45]|h\.?26[45]|hevc|avc|hdr10?|dovi|aac|dts|atmos|truehd)(?![A-Za-z0-9])',
  caseSensitive: false,
);

/// Season folders (`Season 1`, `S01`, `第一季`, `Specials`) belong to a show.
bool isSeasonFolderName(String name) => _seasonFolder.hasMatch(name.trim());

/// Decoded path segments, ignoring empty parts.
List<String> decodedSegments(String path) => [
  for (final segment in path.split('/'))
    if (segment.isNotEmpty) Uri.decodeComponent(segment),
];

/// Removes release noise and separators from a title fragment.
String cleanMediaTitle(String raw) {
  var title = raw.replaceAll(_tmdbTag, ' ');
  final tag = _releaseTag.firstMatch(title);
  if (tag != null && tag.start > 0) title = title.substring(0, tag.start);
  title = title
      .replaceAll(RegExp(r'\[[^\]]*\]|【[^】]*】'), ' ')
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'[(（]\s*[)）]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'^[\s\-–—:：]+'), '')
      .replaceFirst(RegExp(r'[\s\-–—:：(（\[]+$'), '');
  return title.trim();
}

/// Splits `Title (2014) extra` into the title before the last year and the
/// year. A leading year (e.g. `2012`) is kept as the title.
(String, int?) splitTitleYear(String text) {
  final withoutTags = text.replaceAll(_tmdbTag, ' ');
  final matches = _yearPattern
      .allMatches(withoutTags)
      .where(
        (m) => cleanMediaTitle(withoutTags.substring(0, m.start)).isNotEmpty,
      )
      .toList();
  if (matches.isEmpty) return (cleanMediaTitle(withoutTags), null);
  final match = matches.last;
  return (
    cleanMediaTitle(withoutTags.substring(0, match.start)),
    int.parse(match.group(1)!),
  );
}

int? tmdbIdHint(String text) {
  final value = int.tryParse(_tmdbPattern.firstMatch(text)?.group(1) ?? '');
  return value != null && value > 0 ? value : null;
}

String fileBaseName(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Directory holding show-level files for an episode: the episode's folder,
/// or its parent when the episode sits inside a season folder.
String showRootFor(String videoPath) {
  final directory = videoPath.substring(0, videoPath.lastIndexOf('/') + 1);
  final segments = decodedSegments(directory);
  if (segments.length > 1 && isSeasonFolderName(segments.last)) {
    final trimmed = directory.substring(0, directory.length - 1);
    return trimmed.substring(0, trimmed.lastIndexOf('/') + 1);
  }
  return directory;
}

/// Guesses the media described by [path]. Returns null for extras or names
/// without a usable title.
MediaGuess? guessMedia(String path) {
  final segments = decodedSegments(path);
  if (segments.isEmpty) return null;
  final base = fileBaseName(segments.last);
  if (_extras.hasMatch(base)) return null;
  final folders = segments.sublist(0, segments.length - 1);
  final episode = _episodePattern.firstMatch(base);
  if (episode != null) {
    final showFolders = folders.isNotEmpty && isSeasonFolderName(folders.last)
        ? folders.sublist(0, folders.length - 1)
        : folders;
    final showFolder = showFolders.isEmpty ? null : showFolders.last;
    var (title, year) = splitTitleYear(base.substring(0, episode.start));
    if (title.isEmpty && showFolder != null) {
      (title, year) = splitTitleYear(showFolder);
    } else if (year == null && showFolder != null) {
      final (folderTitle, folderYear) = splitTitleYear(showFolder);
      if (folderTitle.toLowerCase() == title.toLowerCase()) year = folderYear;
    }
    if (title.isEmpty) return null;
    return MediaGuess(
      kind: ScrapeMediaKind.episode,
      title: title,
      year: year,
      season: int.parse(episode.group(1)!),
      episode: int.parse(episode.group(2)!),
      tmdbId:
          tmdbIdHint(base) ??
          (showFolder == null ? null : tmdbIdHint(showFolder)),
    );
  }
  var (title, year) = splitTitleYear(base);
  final folder = folders.isEmpty ? null : folders.last;
  if (folder != null && (title.isEmpty || year == null)) {
    final (folderTitle, folderYear) = splitTitleYear(folder);
    if (folderYear != null && folderTitle.isNotEmpty) {
      title = folderTitle;
      year = folderYear;
    }
  }
  if (title.isEmpty) return null;
  return MediaGuess(
    kind: ScrapeMediaKind.movie,
    title: title,
    year: year,
    tmdbId: tmdbIdHint(base) ?? (folder == null ? null : tmdbIdHint(folder)),
  );
}
