import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connections/connection_settings.dart';
import 'organizer_state.dart';

final startupConnectionProvider = FutureProvider<void>((ref) async {
  final settings = await ref.read(connectionSettingsProvider.future);
  if (!ref.mounted || settings.webdavUrl.trim().isEmpty) return;

  final organizer = ref.read(organizerProvider);
  if (organizer.directory.isNotEmpty || organizer.busy || organizer.executing) {
    return;
  }
  await ref.read(organizerProvider.notifier).open(null);
});
