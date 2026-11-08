import 'package:xml/xml.dart';

/// Kodi/Jellyfin/Emby compatible NFO documents built from TMDB responses.
String movieNfo(Map<String, dynamic> movie) => _document('movie', (b) {
  final date = _text(movie['release_date']);
  _element(b, 'title', movie['title']);
  _element(b, 'originaltitle', movie['original_title']);
  _element(b, 'year', _year(date));
  _element(b, 'premiered', date);
  _element(b, 'plot', movie['overview']);
  _element(b, 'tagline', movie['tagline']);
  final runtime = movie['runtime'];
  if (runtime is int && runtime > 0) _element(b, 'runtime', runtime);
  _ratings(b, movie);
  _uniqueIds(b, tmdb: movie['id'], imdb: movie['imdb_id']);
  for (final genre in _names(movie['genres'])) {
    _element(b, 'genre', genre);
  }
  for (final studio in _names(movie['production_companies'])) {
    _element(b, 'studio', studio);
  }
  for (final country in _names(movie['production_countries'])) {
    _element(b, 'country', country);
  }
  final collection = movie['belongs_to_collection'];
  if (collection is Map && _text(collection['name']) != null) {
    b.element('set', nest: () => _element(b, 'name', collection['name']));
  }
  _credits(b, movie['credits']);
});

String tvShowNfo(Map<String, dynamic> show) => _document('tvshow', (b) {
  final date = _text(show['first_air_date']);
  _element(b, 'title', show['name']);
  _element(b, 'originaltitle', show['original_name']);
  _element(b, 'showtitle', show['name']);
  _element(b, 'year', _year(date));
  _element(b, 'premiered', date);
  _element(b, 'plot', show['overview']);
  _element(b, 'status', show['status']);
  _ratings(b, show);
  final external = show['external_ids'];
  _uniqueIds(
    b,
    tmdb: show['id'],
    imdb: external is Map ? external['imdb_id'] : null,
    tvdb: external is Map ? external['tvdb_id'] : null,
  );
  for (final genre in _names(show['genres'])) {
    _element(b, 'genre', genre);
  }
  for (final studio in _names(show['networks'])) {
    _element(b, 'studio', studio);
  }
  _credits(b, show['credits']);
});

String episodeNfo(
  Map<String, dynamic> show,
  Map<String, dynamic>? episode, {
  required int season,
  required int number,
}) => _document('episodedetails', (b) {
  final date = _text(episode?['air_date']);
  _element(b, 'title', episode?['name']);
  _element(b, 'showtitle', show['name']);
  _element(b, 'season', season);
  _element(b, 'episode', number);
  _element(b, 'aired', date);
  _element(b, 'premiered', date);
  _element(b, 'year', _year(date));
  _element(b, 'plot', episode?['overview']);
  final runtime = episode?['runtime'];
  if (runtime is int && runtime > 0) _element(b, 'runtime', runtime);
  if (episode != null) {
    _ratings(b, episode);
    _uniqueIds(b, tmdb: episode['id']);
    _credits(b, {'crew': episode['crew'], 'cast': episode['guest_stars']});
  }
});

const _imageBase = 'https://image.tmdb.org/t/p';

String _document(String root, void Function(XmlBuilder) build) {
  final builder = XmlBuilder()
    ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element(root, nest: () => build(builder));
  return '${builder.buildDocument().toXmlString(pretty: true, indent: '  ')}\n';
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]'), '')
      .trim();
  return text.isEmpty ? null : text;
}

String? _year(String? date) => date != null && RegExp(r'^\d{4}').hasMatch(date)
    ? date.substring(0, 4)
    : null;

void _element(
  XmlBuilder b,
  String name,
  Object? value, {
  Map<String, String> attributes = const {},
}) {
  final text = _text(value);
  if (text != null) b.element(name, attributes: attributes, nest: text);
}

Iterable<String> _names(Object? list) sync* {
  if (list is! List) return;
  for (final item in list) {
    if (item is Map) {
      final name = _text(item['name']);
      if (name != null) yield name;
    }
  }
}

void _ratings(XmlBuilder b, Map<String, dynamic> data) {
  final value = data['vote_average'];
  final votes = data['vote_count'];
  if (value is! num || value <= 0) return;
  b.element(
    'ratings',
    nest: () => b.element(
      'rating',
      attributes: {'name': 'themoviedb', 'max': '10', 'default': 'true'},
      nest: () {
        _element(b, 'value', value.toStringAsFixed(1));
        if (votes is int) _element(b, 'votes', votes);
      },
    ),
  );
}

void _uniqueIds(XmlBuilder b, {Object? tmdb, Object? imdb, Object? tvdb}) {
  _element(
    b,
    'uniqueid',
    tmdb,
    attributes: {'type': 'tmdb', 'default': 'true'},
  );
  _element(b, 'uniqueid', imdb, attributes: {'type': 'imdb'});
  _element(b, 'uniqueid', tvdb, attributes: {'type': 'tvdb'});
  _element(b, 'tmdbid', tmdb);
  _element(b, 'imdbid', imdb);
}

void _credits(XmlBuilder b, Object? credits) {
  if (credits is! Map) return;
  final crew = credits['crew'];
  if (crew is List) {
    for (final person in crew.whereType<Map>()) {
      final job = person['job'];
      if (job == 'Director') _element(b, 'director', person['name']);
      if (job == 'Screenplay' || job == 'Writer') {
        _element(b, 'credits', person['name']);
      }
    }
  }
  final cast = credits['cast'];
  if (cast is! List) return;
  for (final (index, person) in cast.whereType<Map>().take(20).indexed) {
    final name = _text(person['name']);
    if (name == null) continue;
    b.element(
      'actor',
      nest: () {
        _element(b, 'name', name);
        _element(b, 'role', person['character']);
        _element(b, 'order', index);
        final profile = person['profile_path'];
        if (profile is String &&
            RegExp(r'^/[A-Za-z0-9_-]+\.\w+$').hasMatch(profile)) {
          _element(b, 'thumb', '$_imageBase/w185$profile');
        }
      },
    );
  }
}
