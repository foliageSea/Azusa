import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_exception.dart';
import '../logging.dart';
import 'naming_language.dart';
import 'directory_sort.dart';

enum AppThemeColor { azusa, neutral, blue, green, violet, orange, rose }

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = 'system',
    this.namingLanguage = NamingLanguage.simplifiedChinese,
    this.directorySort = DirectorySort.nameAscending,
    this.compactSidebar = false,
    this.themeColor = AppThemeColor.azusa,
    this.radiusScale = 1,
    this.fontScale = 1,
  }) : assert(radiusScale >= 0 && radiusScale <= 2),
       assert(fontScale >= 0.8 && fontScale <= 1.2);
  final ThemeMode themeMode;
  final String language;
  final NamingLanguage namingLanguage;
  final DirectorySort directorySort;
  final bool compactSidebar;
  final AppThemeColor themeColor;
  final double radiusScale;
  final double fontScale;
  Locale? get locale => language == 'system' ? null : Locale(language);
  AppSettings copyWith({
    ThemeMode? themeMode,
    String? language,
    NamingLanguage? namingLanguage,
    DirectorySort? directorySort,
    bool? compactSidebar,
    AppThemeColor? themeColor,
    double? radiusScale,
    double? fontScale,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    language: language ?? this.language,
    namingLanguage: namingLanguage ?? this.namingLanguage,
    directorySort: directorySort ?? this.directorySort,
    compactSidebar: compactSidebar ?? this.compactSidebar,
    themeColor: themeColor ?? this.themeColor,
    radiusScale: radiusScale ?? this.radiusScale,
    fontScale: fontScale ?? this.fontScale,
  );
  Map<String, Object> toJson() => {
    'theme': themeMode.name,
    'language': language,
    'namingLanguage': namingLanguage.code,
    'directorySort': directorySort.name,
    'compactSidebar': compactSidebar,
    'themeColor': themeColor.name,
    'radiusScale': radiusScale,
    'fontScale': fontScale,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeMode: ThemeMode.values.firstWhere(
      (v) => v.name == json['theme'],
      orElse: () => ThemeMode.system,
    ),
    language: ['zh', 'en'].contains(json['language'])
        ? json['language'] as String
        : 'system',
    namingLanguage: NamingLanguage.fromCode(json['namingLanguage']),
    directorySort: DirectorySort.fromName(json['directorySort']),
    compactSidebar: json['compactSidebar'] == true,
    themeColor: AppThemeColor.values.firstWhere(
      // 原默认中性色迁移为 Azusa 红；保留用户选择的其他主题色。
      (value) =>
          value.name ==
          (json['themeColor'] == 'neutral' ? 'azusa' : json['themeColor']),
      orElse: () => AppThemeColor.azusa,
    ),
    radiusScale: switch (json['radiusScale']) {
      num value when value.isFinite && value >= 0 && value <= 2 =>
        value.toDouble(),
      _ => 1,
    },
    fontScale: switch (json['fontScale']) {
      num value when value.isFinite && value >= 0.8 && value <= 1.2 =>
        value.toDouble(),
      _ => 1,
    },
  );
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class PreferencesSettingsRepository implements SettingsRepository {
  PreferencesSettingsRepository(this.preferences);
  final SharedPreferencesAsync preferences;
  static const key = 'azusa.settings.v1';
  @override
  Future<AppSettings> load() async {
    final raw = await preferences.getString(key);
    return raw == null
        ? const AppSettings()
        : AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      await preferences.setString(key, jsonEncode(settings.toJson()));
    } catch (e) {
      throw AppException(FailureKind.storage, e);
    }
  }
}

final preferencesProvider = Provider((ref) => SharedPreferencesAsync());
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => PreferencesSettingsRepository(ref.watch(preferencesProvider)),
);
final initialSettingsProvider = Provider((ref) => const AppSettings());
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> with LoggingMixin {
  Future<void> _pending = Future.value();
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);
  Future<void> update(AppSettings Function(AppSettings) transform) {
    final next = _pending.then((_) async {
      final settings = transform(state);
      await ref.read(settingsRepositoryProvider).save(settings);
      state = settings;
    });
    _pending = next.catchError((Object e, StackTrace stack) {
      log.severe('Settings write failed', e, stack);
    });
    return next;
  }
}
