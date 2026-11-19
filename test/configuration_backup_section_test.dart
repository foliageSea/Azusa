import 'package:azusa/app/theme.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/settings/configuration_backup_section.dart';
import 'package:azusa/features/settings/settings_page.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  testWidgets('configuration backup appears in General, not Appearance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SettingsPage(
          configurationBackup: (_) => const Text('Backup section marker'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final backup = find.text('Backup section marker');
    expect(backup, findsOneWidget);
    expect(backup.hitTestable(), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(backup.hitTestable(), findsNothing);
  });

  testWidgets(
    'export defaults to no credentials and requires a confirmed passphrase when selected',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final working = <bool>[];
      await tester.pumpWidget(
        _app(
          ConfigurationBackupSection(
            locked: false,
            onWorking: working.add,
            onImported: (_) => fail('Cannot import from export dialog'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('export-configuration')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: 'opening dialog');
      final action = find.descendant(
        of: find.byType(FDialog),
        matching: find.widgetWithText(FButton, 'Export configuration'),
      );
      expect(tester.widget<FButton>(action).onPress, isNotNull);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.text('Include credentials'));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'showing passphrase fields',
      );
      final fields = find.byType(EditableText);
      expect(fields, findsNWidgets(2));
      expect(find.text('Enter backup passphrase'), findsOneWidget);
      expect(find.text('Enter the same passphrase'), findsOneWidget);
      expect(tester.widget<FButton>(action).onPress, isNull);
      await tester.enterText(fields.first, 'migration passphrase');
      await tester.enterText(fields.last, 'different passphrase');
      await tester.pump();
      expect(find.text('Passphrases do not match.'), findsOneWidget);
      expect(tester.widget<FButton>(action).onPress, isNull);
      await tester.enterText(fields.last, 'migration passphrase');
      await tester.pump();
      expect(tester.widget<FButton>(action).onPress, isNotNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(working, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(Widget body) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...FLocalizations.localizationsDelegates,
    ],
    builder: (context, child) => FTheme(
      data: createAppTheme(
        const AppSettings(),
        brightness: Brightness.light,
        touch: true,
      ),
      child: child!,
    ),
    home: Scaffold(body: body),
  ),
);
