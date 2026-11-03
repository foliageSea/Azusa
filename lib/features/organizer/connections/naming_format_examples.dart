import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/settings/naming_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/localization.dart';

String namingFormatLabel(AppLocalizations l, NamingFormat format) =>
    switch (format) {
      NamingFormat.standard => l.namingFormatStandard,
      NamingFormat.compact => l.namingFormatCompact,
      NamingFormat.dotted => l.namingFormatDotted,
      NamingFormat.dottedCompact => l.namingFormatDottedCompact,
    };

Future<void> showNamingFormatExamples(BuildContext context) =>
    showFDialog<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) {
        final l = context.l10n;
        final examples = {
          NamingFormat.standard: (
            l.namingExampleMovieStandard,
            l.namingExampleTvStandard,
          ),
          NamingFormat.compact: (
            l.namingExampleMovieStandard,
            l.namingExampleTvCompact,
          ),
          NamingFormat.dotted: (
            l.namingExampleMovieDotted,
            l.namingExampleTvDotted,
          ),
          NamingFormat.dottedCompact: (
            l.namingExampleMovieDotted,
            l.namingExampleTvDottedCompact,
          ),
        };
        return FDialog(
          key: const ValueKey('naming-format-examples-dialog'),
          animation: animation,
          semanticsLabel: l.namingFormatExamples,
          builder: (context, style) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.namingFormatExamples,
                  style: context.theme.typography.body.lg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in examples.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  namingFormatLabel(l, entry.key),
                                  style: context.theme.typography.body.sm
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  entry.value.$1,
                                  style: context.theme.typography.body.sm,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.value.$2,
                                  style: context.theme.typography.body.sm,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FButton(
                  key: const ValueKey('close-naming-format-examples'),
                  variant: .outline,
                  onPress: () => Navigator.of(context).pop(),
                  child: Text(l.close),
                ),
              ],
            ),
          ),
        );
      },
    );
