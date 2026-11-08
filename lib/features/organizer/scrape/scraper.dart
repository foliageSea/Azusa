import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/agent.dart';
import '../ai/tmdb.dart';
import '../dav/dav_paths.dart';
import '../dav/directory_scan.dart';
import '../dav/webdav.dart';
import 'media_identity.dart';
import 'nfo.dart';

/// A video matched to TMDB, ready to receive metadata files.
class ScrapeTarget {
  const ScrapeTarget({
    required this.video,
    required this.kind,
    required this.tmdbId,
    required this.title,
    this.year,
    this.season,
    this.episode,
  });

  final String video;
  final ScrapeMediaKind kind;
  final int tmdbId;
  final String title;
  final int? year, season, episode;

  String get directory => video.substring(0, video.lastIndexOf('/') + 1);
  String get baseName =>
      fileBaseName(Uri.decodeComponent(video.split('/').last));
  String get showRoot => showRootFor(video);
}

class ScrapeScan {
  const ScrapeScan(this.targets, this.unmatched);
  final List<ScrapeTarget> targets;

  /// Videos that could not be identified or matched on TMDB.
  final List<String> unmatched;
}

typedef ScrapeResult = ({int written, int skipped});

class _ScrapeFile {
  const _ScrapeFile(this.path, this.content);
  final String path;

  /// Returns null when TMDB offers no data for this file.
  final Future<List<int>?> Function() content;
}

/// Identifies videos by file name, matches them on TMDB and writes NFO files
/// and artwork next to them. Existing files are never overwritten.
class MetadataScraper {
  MetadataScraper(this.dav, this.tmdb);
  final WebDavClient dav;
  final TmdbClient tmdb;

  final _searches = <String, Future<Map<String, dynamic>?>>{};
  final _movies = <int, Future<Map<String, dynamic>>>{};
  final _shows = <int, Future<Map<String, dynamic>>>{};
  final _seasons = <String, Future<Map<String, dynamic>>>{};

  static int? _yearOf(Object? date) => date is String && date.length >= 4
      ? int.tryParse(date.substring(0, 4))
      : null;

  static String? _name(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  Future<Map<String, dynamic>?> _match(MediaGuess guess) {
    final movie = guess.kind == ScrapeMediaKind.movie;
    final key =
        '${guess.kind.name}|${guess.tmdbId}|${guess.title.toLowerCase()}|${guess.year}';
    return _searches[key] ??= () async {
      if (guess.tmdbId != null) {
        try {
          return movie
              ? await _movie(guess.tmdbId!)
              : await _show(guess.tmdbId!);
        } on DioException catch (error) {
          if (error.response?.statusCode == 404) return null;
          rethrow;
        } on FormatException {
          return null;
        }
      }
      final dateKey = movie ? 'release_date' : 'first_air_date';
      var results = movie
          ? await tmdb.searchMovies(guess.title, year: guess.year)
          : await tmdb.search(guess.title);
      if (results.isEmpty && movie && guess.year != null) {
        results = await tmdb.searchMovies(guess.title);
      }
      if (results.isEmpty) return null;
      return results.firstWhere(
        (result) =>
            guess.year != null && _yearOf(result[dateKey]) == guess.year,
        orElse: () => results.first,
      );
    }();
  }

  Future<Map<String, dynamic>> _movie(int id) =>
      _movies[id] ??= tmdb.movieMetadata(id);
  Future<Map<String, dynamic>> _show(int id) =>
      _shows[id] ??= tmdb.tvMetadata(id);
  Future<Map<String, dynamic>> _season(int id, int number) =>
      _seasons['$id/$number'] ??= tmdb.seasonMetadata(id, number);

  Future<ScrapeScan> scan(
    String root, {
    void Function(String path, int count)? onProgress,
    void Function()? checkCancelled,
  }) async {
    final entries = await scanMediaDirectories(
      dav,
      root,
      recursive: true,
      onProgress: onProgress,
      checkCancelled: checkCancelled,
    );
    final videos = entries.where(RenameAgent.isVideo).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final targets = <ScrapeTarget>[];
    final unmatched = <String>[];
    for (final (index, video) in videos.indexed) {
      checkCancelled?.call();
      onProgress?.call(video.path, index);
      final guess = guessMedia(video.path);
      final match = guess == null ? null : await _match(guess);
      checkCancelled?.call();
      final id = match?['id'];
      if (guess == null || match == null || id is! int || id < 1) {
        unmatched.add(video.path);
        continue;
      }
      final movie = guess.kind == ScrapeMediaKind.movie;
      targets.add(
        ScrapeTarget(
          video: video.path,
          kind: guess.kind,
          tmdbId: id,
          title:
              _name(
                match,
                movie ? ['title', 'original_title'] : ['name', 'original_name'],
              ) ??
              guess.title,
          year: _yearOf(match[movie ? 'release_date' : 'first_air_date']),
          season: guess.season,
          episode: guess.episode,
        ),
      );
    }
    return ScrapeScan(targets, unmatched);
  }

  /// Show roots receive tvshow.nfo and show artwork only when every
  /// identified video below them belongs to the same series.
  static Map<String, int> showRoots(List<ScrapeTarget> all) {
    final shows = <String, Set<int>>{};
    final mixed = <String>{};
    for (final target in all) {
      if (target.kind == ScrapeMediaKind.episode) {
        shows.putIfAbsent(target.showRoot, () => {}).add(target.tmdbId);
      }
    }
    for (final root in shows.keys) {
      if (all.any(
        (target) =>
            target.video.startsWith(root) &&
            (target.kind == ScrapeMediaKind.movie ||
                target.tmdbId != shows[root]!.first),
      )) {
        mixed.add(root);
      }
    }
    return {
      for (final entry in shows.entries)
        if (entry.value.length == 1 && !mixed.contains(entry.key))
          entry.key: entry.value.first,
    };
  }

  static String _imageName(String base, String tmdbPath) {
    final extension = tmdbPath
        .substring(tmdbPath.lastIndexOf('.') + 1)
        .toLowerCase();
    return '$base.${extension == 'jpeg' ? 'jpg' : extension}';
  }

  _ScrapeFile? _image(
    String directory,
    String base,
    Object? tmdbPath,
    String size,
  ) {
    if (!TmdbClient.validImagePath(tmdbPath)) return null;
    final path = tmdbPath as String;
    return _ScrapeFile(
      childDavPath(directory, _imageName(base, path)),
      () => tmdb.image(path, size: size),
    );
  }

  Future<List<_ScrapeFile>> _files(
    String scope,
    List<ScrapeTarget> selected,
    List<ScrapeTarget> all, {
    required bool artwork,
  }) async {
    final files = <_ScrapeFile>[];
    List<int> utf8Text(String text) => utf8.encode(text);
    final roots = showRoots(all);
    for (final MapEntry(key: root, value: id) in roots.entries) {
      // Selecting a season must not write show files in its parent folder.
      if (!root.startsWith(scope)) continue;
      final episodes = selected.where(
        (t) => t.kind == ScrapeMediaKind.episode && t.showRoot == root,
      );
      if (episodes.isEmpty) continue;
      files.add(
        _ScrapeFile(
          childDavPath(root, 'tvshow.nfo'),
          () async => utf8Text(tvShowNfo(await _show(id))),
        ),
      );
      if (!artwork) continue;
      final show = await _show(id);
      files.addAll(
        [
          _image(root, 'poster', show['poster_path'], 'w780'),
          _image(root, 'fanart', show['backdrop_path'], 'w1280'),
        ].whereType<_ScrapeFile>(),
      );
      for (final number in {
        for (final e in episodes) e.season!,
      }.toList()..sort()) {
        final season = await _season(id, number);
        final name = number == 0
            ? 'season-specials-poster'
            : 'season${number.toString().padLeft(2, '0')}-poster';
        final image = _image(root, name, season['poster_path'], 'w780');
        if (image != null) files.add(image);
      }
    }
    for (final target in selected) {
      final directory = target.directory;
      final base = target.baseName;
      if (target.kind == ScrapeMediaKind.movie) {
        files.add(
          _ScrapeFile(
            childDavPath(directory, '$base.nfo'),
            () async => utf8Text(movieNfo(await _movie(target.tmdbId))),
          ),
        );
        if (!artwork) continue;
        final movie = await _movie(target.tmdbId);
        files.addAll(
          [
            _image(directory, '$base-poster', movie['poster_path'], 'w780'),
            _image(directory, '$base-fanart', movie['backdrop_path'], 'w1280'),
          ].whereType<_ScrapeFile>(),
        );
      } else {
        Future<Map<String, dynamic>?> episode() async {
          final season = await _season(target.tmdbId, target.season!);
          return (season['episodes'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .where((e) => e['episode_number'] == target.episode)
              .firstOrNull;
        }

        files.add(
          _ScrapeFile(
            childDavPath(directory, '$base.nfo'),
            () async => utf8Text(
              episodeNfo(
                await _show(target.tmdbId),
                await episode(),
                season: target.season!,
                number: target.episode!,
              ),
            ),
          ),
        );
        if (!artwork) continue;
        final image = _image(
          directory,
          '$base-thumb',
          (await episode())?['still_path'],
          'w780',
        );
        if (image != null) files.add(image);
      }
    }
    return files;
  }

  /// Writes metadata for [selected]. [all] is the full scan result and decides
  /// which folders may hold show-level files. Stops at the first failure.
  Future<ScrapeResult> write(
    String root,
    List<ScrapeTarget> selected,
    List<ScrapeTarget> all, {
    bool artwork = true,
    void Function()? checkCancelled,
    Future<void> Function(String path)? onWriting,
    Future<void> Function(String path)? onWritten,
    void Function(int written, int skipped, int total)? onProgress,
  }) async {
    for (final target in selected) {
      if (!target.video.startsWith(root) ||
          dav.normalize(target.video) != target.video) {
        throw StateError('文件超出搜刮范围');
      }
    }
    if (!root.endsWith('/') || dav.normalize(root) != root) {
      throw StateError('文件超出搜刮范围');
    }
    final files = await _files(root, selected, all, artwork: artwork);
    if (files.any(
      (file) =>
          !file.path.startsWith(root) || dav.normalize(file.path) != file.path,
    )) {
      throw StateError('文件超出搜刮范围');
    }
    final listings = <String, Set<String>>{};
    var written = 0;
    var skipped = 0;
    onProgress?.call(written, skipped, files.length);
    for (final file in files) {
      checkCancelled?.call();
      final directory = file.path.substring(0, file.path.lastIndexOf('/') + 1);
      final name = file.path.substring(directory.length).toLowerCase();
      final existing = listings[directory] ??= {
        for (final entry in await dav.listAll(directory))
          entry.path
              .replaceFirst(RegExp(r'/$'), '')
              .substring(directory.length)
              .toLowerCase(),
      };
      final content = existing.contains(name) ? null : await file.content();
      checkCancelled?.call();
      if (content == null) {
        skipped++;
      } else {
        await onWriting?.call(file.path);
        checkCancelled?.call();
        await dav.upload(file.path, Stream.value(content), content.length);
        existing.add(name);
        written++;
        await onWritten?.call(file.path);
      }
      onProgress?.call(written, skipped, files.length);
    }
    return (written: written, skipped: skipped);
  }
}
