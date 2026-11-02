import 'package:flutter/widgets.dart';

import 'localization.dart';

List<(String, String)> languageOptions(BuildContext context) => [
  ('system', context.l10n.system),
  ('zh', '简体中文'),
  ('en', 'English'),
];
