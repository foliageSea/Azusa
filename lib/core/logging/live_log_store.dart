import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _applicationLogs = LiveLogStore();
final liveLogStoreProvider = Provider<LiveLogStore>((ref) => _applicationLogs);

/// Captures session logs independently of file storage and viewer lifetime.
LiveLogStore get applicationLogs => _applicationLogs;

@immutable
class LiveLogEntry {
  const LiveLogEntry({
    required this.id,
    required this.level,
    required this.time,
    required this.text,
  });

  final int id;
  final Level level;
  final DateTime time;
  final String text;
}

/// Bounded text storage with coalesced notifications, not a buffered stream.
class LiveLogStore extends ChangeNotifier {
  LiveLogStore({
    this.maxEntries = 1000,
    this.maxTextLength = 1024 * 1024,
    this.maxEntryLength = 16 * 1024,
    this.refreshInterval = const Duration(milliseconds: 100),
  }) : assert(maxEntries > 0),
       assert(maxTextLength > 1),
       assert(maxEntryLength > 1);

  final int maxEntries;
  // UTF-16 code units: the default text budget is approximately 2 MiB.
  final int maxTextLength;
  final int maxEntryLength;
  final Duration refreshInterval;
  final Queue<LiveLogEntry> _entries = Queue();
  int _textLength = 0;
  int _latestId = 0;
  Timer? _notification;

  int get latestId => _latestId;
  List<LiveLogEntry> get snapshot => List.unmodifiable(_entries);

  void add({
    required Level level,
    required DateTime time,
    required String text,
  }) {
    final limit = maxEntryLength < maxTextLength
        ? maxEntryLength
        : maxTextLength;
    var retained = text;
    if (text.length > limit) {
      var end = limit - 1;
      // Do not split a UTF-16 surrogate pair when shortening a large entry.
      final last = text.codeUnitAt(end - 1);
      if (last >= 0xd800 && last <= 0xdbff) end--;
      retained = '${text.substring(0, end)}…';
    }
    _entries.add(
      LiveLogEntry(id: ++_latestId, level: level, time: time, text: retained),
    );
    _textLength += retained.length;
    while (_entries.length > maxEntries || _textLength > maxTextLength) {
      _textLength -= _entries.removeFirst().text.length;
    }
    if (hasListeners && _notification == null) {
      _notification = Timer(refreshInterval, () {
        _notification = null;
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _notification?.cancel();
    super.dispose();
  }
}
