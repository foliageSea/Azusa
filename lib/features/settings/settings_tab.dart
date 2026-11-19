enum SettingsTab {
  general,
  appearance,
  fileServers,
  ai,
  tmdb,
  proxy,
  about;

  static SettingsTab fromParameter(String? value) => value == 'webdav'
      ? fileServers
      : values.where((tab) => tab.name == value).firstOrNull ?? general;

  String get location => '/connections?tab=$name';
}
