import '../dav/dav_paths.dart';
import '../rename_plan.dart';

/// How matched media is grouped into folders below the analyzed directory.
class FolderLayout {
  const FolderLayout({
    this.movieFolders = false,
    this.seriesFolders = false,
    this.seasonFolders = false,
  });

  static const none = FolderLayout();
  static const full = FolderLayout(
    movieFolders: true,
    seriesFolders: true,
    seasonFolders: true,
  );

  final bool movieFolders, seriesFolders, seasonFolders;

  bool get enabled => movieFolders || seriesFolders || seasonFolders;

  FolderLayout copyWith({
    bool? movieFolders,
    bool? seriesFolders,
    bool? seasonFolders,
  }) => FolderLayout(
    movieFolders: movieFolders ?? this.movieFolders,
    seriesFolders: seriesFolders ?? this.seriesFolders,
    seasonFolders: seasonFolders ?? this.seasonFolders,
  );

  @override
  bool operator ==(Object other) =>
      other is FolderLayout &&
      other.movieFolders == movieFolders &&
      other.seriesFolders == seriesFolders &&
      other.seasonFolders == seasonFolders;

  @override
  int get hashCode => Object.hash(movieFolders, seriesFolders, seasonFolders);
}

String _folderName(String title, int? year) {
  final name = sanitizeSuggestedFileName(
    year == null ? title : '$title ($year)',
    originalName: '',
  );
  return fileNameError(name) == null ? name : '';
}

String seasonFolderName(int season) =>
    season == 0 ? 'Specials' : 'Season ${season.toString().padLeft(2, '0')}';

/// The folder below [scope] for [item], or null when the layout does not
/// apply to it.
String? plannedDirectory(RenameItem item, String scope, FolderLayout layout) {
  final title = item.mediaTitle?.trim();
  if (title == null || title.isEmpty) return null;
  final segments = <String>[];
  switch (item.tmdbMediaType) {
    case TmdbMediaType.movie when layout.movieFolders:
      segments.add(_folderName(title, item.mediaYear));
    case TmdbMediaType.tv:
      if (layout.seriesFolders) {
        segments.add(_folderName(title, item.mediaYear));
      }
      if (layout.seasonFolders && item.seasonNumber != null) {
        segments.add(seasonFolderName(item.seasonNumber!));
      }
    default:
      return null;
  }
  if (segments.isEmpty || segments.any((segment) => segment.isEmpty)) {
    return null;
  }
  final scopeSegments = scope.split('/').where((part) => part.isNotEmpty);
  if (scopeSegments.isNotEmpty &&
      Uri.decodeComponent(scopeSegments.last) == segments.first) {
    segments.removeAt(0);
  }
  return [
    scope,
    for (final segment in segments) '${Uri.encodeComponent(segment)}/',
  ].join();
}

/// Places every matched item according to [layout]. Where the layout does not
/// apply, episodes in subfolders move up into [scope] and other files stay in
/// their folder.
List<RenameItem> applyFolderLayout(
  List<RenameItem> plan,
  String scope,
  FolderLayout layout,
) => [
  for (final item in plan)
    if (item.scope != scope)
      item
    else
      item.withTargetDirectory(
        plannedDirectory(item, scope, layout) ??
            (item.tmdbMediaType == TmdbMediaType.tv && item.parent != scope
                ? scope
                : null),
      ),
];

/// Folders the plan will create, ordered from outermost to innermost.
List<String> plannedFolders(List<RenameItem> plan) {
  final folders = <String>{};
  for (final item in plan.where((item) => item.enabled)) {
    final scope = item.scope;
    final directory = item.targetDirectory;
    if (scope == null || directory == null || directory == scope) continue;
    var path = scope;
    for (final segment
        in directory
            .substring(scope.length)
            .split('/')
            .where((segment) => segment.isNotEmpty)) {
      path = '$path$segment/';
      folders.add(path);
    }
  }
  return folders.toList()..sort();
}
