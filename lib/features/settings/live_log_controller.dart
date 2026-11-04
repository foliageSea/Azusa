import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../core/logging/live_log_store.dart';

/// Pausing and clearing affect only this viewer, never the shared log store.
class LiveLogController extends ChangeNotifier {
  LiveLogController(this.store) {
    _snapshot = store.snapshot;
    _filter();
    store.addListener(_refresh);
  }

  final LiveLogStore store;
  late List<LiveLogEntry> _snapshot;
  List<LiveLogEntry> _entries = const [];
  bool _paused = false;
  int _afterId = 0;
  String _query = '';
  Level _minimumLevel = Level.ALL;

  List<LiveLogEntry> get entries => _entries;
  bool get paused => _paused;
  Level get minimumLevel => _minimumLevel;
  bool get hasFilters => _query.trim().isNotEmpty || _minimumLevel != Level.ALL;
  bool get hasUnfilteredEntries =>
      _snapshot.any((entry) => entry.id > _afterId);
  String get copyText => _entries.map((entry) => entry.text).join('\n\n');

  void _filter() {
    final query = _query.trim().toLowerCase();
    _entries = List.unmodifiable(
      _snapshot.where(
        (entry) =>
            entry.id > _afterId &&
            entry.level >= _minimumLevel &&
            (query.isEmpty || entry.text.toLowerCase().contains(query)),
      ),
    );
  }

  void _refresh() {
    if (_paused) return;
    _snapshot = store.snapshot;
    _filter();
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    _filter();
    notifyListeners();
  }

  void setMinimumLevel(Level level) {
    _minimumLevel = level;
    _filter();
    notifyListeners();
  }

  void togglePaused() {
    _paused = !_paused;
    if (!_paused) _snapshot = store.snapshot;
    _filter();
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _minimumLevel = Level.ALL;
    _filter();
    notifyListeners();
  }

  void clearView() {
    _afterId = store.latestId;
    _snapshot = const [];
    _filter();
    notifyListeners();
  }

  @override
  void dispose() {
    store.removeListener(_refresh);
    super.dispose();
  }
}
