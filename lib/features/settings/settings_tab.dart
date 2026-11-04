enum SettingsTab {
  general,
  appearance,
  webdav,
  ai,
  tmdb,
  proxy,
  about;

  static SettingsTab fromParameter(String? value) =>
      values.where((tab) => tab.name == value).firstOrNull ?? general;

  String get location => '/connections?tab=$name';
}
