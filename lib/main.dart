import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app/app.dart';
import 'core/logging.dart';
import 'core/settings/settings.dart';
import 'core/window/desktop_window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    const licenses = {
      'COPYING': 'libsmb2',
      'LICENCE-LGPL-2.1.txt': 'libsmb2',
      'LICENSE-OpenSSL.txt': 'OpenSSL',
      'dart_smb2-NOTICE': 'SMB third-party notices',
      'SOURCE': 'SMB corresponding source',
    };
    for (final entry in licenses.entries) {
      final text = await rootBundle.loadString(
        'assets/licenses/smb/${entry.key}',
      );
      yield LicenseEntryWithLineBreaks([entry.value], text);
    }
  });
  await initializeLogging();
  final log = Logger('main');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe('Flutter error', details.exception, details.stack);
  };
  final bootstrap = ProviderContainer();
  AppSettings settings;
  try {
    settings = await bootstrap.read(settingsRepositoryProvider).load();
  } catch (e, stack) {
    log.severe('Settings read failed; using defaults', e, stack);
    settings = const AppSettings();
  }
  final window = NativeDesktopWindowController();
  if (window.available) await window.initialize();
  bootstrap.dispose();
  runApp(
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(settings),
        desktopWindowProvider.overrideWithValue(window),
      ],
      child: const StarterApp(),
    ),
  );
}
