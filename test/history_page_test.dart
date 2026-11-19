import 'package:azusa/app/theme.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/history/history_entry.dart';
import 'package:azusa/features/organizer/history/history_page.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  testWidgets('shows server names and protocol tags in all history rows', (
    tester,
  ) async {
    const records = [
      ExecutionHistoryRecord(
        '完成 delete /webdav/movie.mkv',
        server: HistoryServer(
          connectionId: 'old-dav',
          name: 'Archived WebDAV server',
          protocol: 'webdav',
        ),
      ),
      ExecutionHistoryRecord(
        '完成 delete /smb/movie.mkv',
        server: HistoryServer(
          connectionId: 'old-smb',
          name: 'Archived SMB server',
          protocol: 'smb',
        ),
      ),
      ExecutionHistoryRecord('完成 delete /legacy/movie.mkv'),
    ];
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          executionHistoryProvider.overrideWith((_) async => records),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
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
          home: const HistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)))!;
    final labels = [
      l10n.historyFileServer('Archived WebDAV server'),
      l10n.historyFileServer('Archived SMB server'),
      l10n.historyFileServer('-'),
    ];
    void expectServerLabels() {
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      for (final protocol in ['WebDAV', 'SMB']) {
        expect(
          find.ancestor(of: find.text(protocol), matching: find.byType(FBadge)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: find.byType(FBadge), matching: find.text('-')),
        findsNothing,
      );
    }

    expectServerLabels();

    for (var i = 0; i < records.length; i++) {
      final expand = find.byIcon(FLucideIcons.chevronDown).first;
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pumpAndSettle();
    }
    expect(find.byIcon(FLucideIcons.chevronUp), findsNWidgets(records.length));
    expectServerLabels();
  });
}
