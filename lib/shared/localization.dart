import 'package:flutter/widgets.dart';

import '../l10n/generated/app_localizations.dart';

extension AppLocalization on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
