import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/azusa_logo.dart';
import '../../../shared/loading_button.dart';
import '../../../shared/icon_action.dart';
import '../../../shared/secret_text_field.dart';
import '../../../shared/text_field_action.dart';
import '../../../shared/widgets.dart';
import '../../../shared/localization.dart';
import '../../../shared/runtime_localization.dart';
import '../../../core/settings/settings.dart';
import '../../../core/settings/naming_language.dart';
import '../../../core/settings/naming_format.dart';
import '../../settings/settings_page.dart';
import '../../settings/settings_tab.dart';
import '../../settings/configuration_backup_section.dart';
import 'configuration_backup.dart';
import 'connection_settings.dart';
import 'webdav_manager.dart';
import 'ai_models.dart';
import 'model_picker.dart';
import 'http_clients.dart';
import 'naming_format_examples.dart';
import '../organizer_state.dart';
import '../ai/tmdb.dart';

enum _ConnectionAction { save, ai, tmdb, models }

enum _ConnectionTest {
  ai(NetworkService.ai, _ConnectionAction.ai),
  tmdb(NetworkService.tmdb, _ConnectionAction.tmdb);

  const _ConnectionTest(this.service, this.action);
  final NetworkService service;
  final _ConnectionAction action;
}

enum _ConnectionField {
  aiUrl(3),
  model(4),
  aiKey(5),
  tmdbToken(6),
  proxyUrl(7);

  const _ConnectionField(this.keyIndex);
  // Keep existing field and secret-toggle keys stable.
  final int keyIndex;
}

class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({this.tab = SettingsTab.general, super.key});
  final SettingsTab tab;
  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  final fields = {
    for (final field in _ConnectionField.values) field: TextEditingController(),
  };
  bool loaded = false;
  _ConnectionAction? activeAction;
  bool get busy => activeAction != null;
  bool savingNamingSettings = false;
  bool transferringConfiguration = false;
  final visibleSecrets = <_ConnectionField>{};
  GoRouter? router;
  bool proxyAi = true, proxyTmdb = true;
  ProxyMode proxyMode = ProxyMode.direct;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = GoRouter.of(context);
    if (router == next) return;
    router?.routeInformationProvider.removeListener(hideSecretsOnNavigation);
    router = next;
    next.routeInformationProvider.addListener(hideSecretsOnNavigation);
  }

  void hideSecretsOnNavigation() {
    if (visibleSecrets.isNotEmpty &&
        router?.routeInformationProvider.value.uri.path != '/connections') {
      setState(visibleSecrets.clear);
    }
  }

  @override
  void dispose() {
    router?.routeInformationProvider.removeListener(hideSecretsOnNavigation);
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  ConnectionSettings get current => ref
      .read(connectionSettingsProvider)
      .requireValue
      .copyWith(
        aiUrl: fields[_ConnectionField.aiUrl]!.text.trim(),
        model: fields[_ConnectionField.model]!.text.trim(),
        aiKey: fields[_ConnectionField.aiKey]!.text.trim(),
        tmdbToken: fields[_ConnectionField.tmdbToken]!.text.trim(),
        proxyUrl: fields[_ConnectionField.proxyUrl]!.text.trim(),
        proxyMode: proxyMode,
        proxyAi: proxyAi,
        proxyTmdb: proxyTmdb,
      );

  void _refreshImportedFields(Set<BackupSection> selected) {
    if (!mounted) return;
    final value = ref.read(connectionSettingsProvider).requireValue;
    setState(() {
      if (selected.contains(BackupSection.ai)) {
        fields[_ConnectionField.aiUrl]!.text = value.aiUrl;
        fields[_ConnectionField.model]!.text = value.model;
        fields[_ConnectionField.aiKey]!.text = value.aiKey;
        proxyAi = value.proxyAi;
        visibleSecrets.remove(_ConnectionField.aiKey);
      }
      if (selected.contains(BackupSection.tmdb)) {
        fields[_ConnectionField.tmdbToken]!.text = value.tmdbToken;
        proxyTmdb = value.proxyTmdb;
        visibleSecrets.remove(_ConnectionField.tmdbToken);
      }
    });
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => activeAction = _ConnectionAction.save);
    try {
      final value = current;
      if (value.aiUrl.isNotEmpty) {
        validatedHttpUrl(value.aiUrl, allowHttp: true);
      }
      if (value.proxyMode == ProxyMode.manual) {
        if (validatedProxy(value.proxyUrl) == null) {
          throw const FormatException('请输入代理地址');
        }
      }
      await ref.read(connectionSettingsProvider.notifier).save(value);
      ref.invalidate(organizerProvider);
      if (mounted) {
        notifyUser(
          context,
          context.l10n.configurationSaved,
          type: NoticeType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        notifyUser(
          context,
          context.l10n.saveFailed(
            e is PlatformException
                ? context.l10n.storageError
                : localizeRuntimeMessage(context.l10n, serviceError(e)),
          ),
          type: NoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => activeAction = null);
    }
  }

  Future<void> test(_ConnectionTest target) async {
    if (busy) return;
    setState(() => activeAction = target.action);
    TmdbClient? tmdb;
    try {
      final value = current;
      switch (target) {
        case _ConnectionTest.tmdb:
          tmdb = TmdbClient(
            value,
            namingLanguage: ref.read(settingsProvider).namingLanguage,
          );
          await tmdb.search('Breaking Bad');
        case _ConnectionTest.ai:
          await ref.read(aiModelsLoaderProvider)(value);
      }
      if (mounted) {
        notifyUser(
          context,
          context.l10n.connectionSucceeded(
            usesProxy(value, target.service)
                ? _proxyLabel(context, value.proxyMode)
                : context.l10n.directConnection,
          ),
          type: NoticeType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        notifyUser(
          context,
          context.l10n.connectionFailed(
            localizeRuntimeMessage(context.l10n, serviceError(e)),
          ),
          type: NoticeType.error,
        );
      }
    } finally {
      tmdb?.close();
      if (mounted) setState(() => activeAction = null);
    }
  }

  Future<void> getModels() async {
    if (busy) return;
    setState(() => activeAction = _ConnectionAction.models);
    try {
      final models = await ref.read(aiModelsLoaderProvider)(current);
      if (!mounted) return;
      setState(() => activeAction = null);
      if (models.isEmpty) {
        notifyUser(context, context.l10n.noModelsAvailable);
        return;
      }
      final selected = await showModelPicker(
        context,
        models,
        selected: fields[_ConnectionField.model]!.text.trim(),
      );
      if (mounted && selected != null) {
        fields[_ConnectionField.model]!.text = selected;
      }
    } catch (e) {
      if (mounted) {
        notifyUser(
          context,
          context.l10n.fetchModelsFailed(
            localizeRuntimeMessage(context.l10n, serviceError(e)),
          ),
          type: NoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => activeAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final appSettings = ref.watch(settingsProvider);
    final settings = ref.watch(connectionSettingsProvider);
    final organizer = ref.watch(organizerProvider);
    final locked =
        busy ||
        transferringConfiguration ||
        savingNamingSettings ||
        organizer.busy ||
        organizer.executing;
    Widget field(_ConnectionField field, String label) {
      final hint = switch (field) {
        _ConnectionField.aiUrl => l.aiUrlHint,
        _ConnectionField.model => l.modelNameHint,
        _ConnectionField.aiKey => l.apiKeyHint,
        _ConnectionField.tmdbToken => l.tmdbTokenHint,
        _ConnectionField.proxyUrl => l.proxyUrlHint,
      };
      final key = ValueKey('connection-field-${field.keyIndex}');
      final controller = fields[field]!;
      final secret =
          field == _ConnectionField.aiKey ||
          field == _ConnectionField.tmdbToken;
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: secret
            ? SecretTextField(
                fieldKey: key,
                toggleKey: ValueKey('toggle-secret-${field.keyIndex}'),
                controller: controller,
                label: label,
                hint: hint,
                enabled: !locked,
                visible: visibleSecrets.contains(field),
                showLabel: l.showApiKey,
                hideLabel: l.hideApiKey,
                onVisibilityChange: (visible) => setState(() {
                  if (visible) {
                    visibleSecrets.add(field);
                  } else {
                    visibleSecrets.remove(field);
                  }
                }),
              )
            : FTextField(
                key: key,
                label: Text(label),
                hint: hint,
                enabled: !locked,
                control: .managed(controller: controller),
                suffixBuilder: field == _ConnectionField.model
                    ? (context, style, variants) => TextFieldAction(
                        key: const ValueKey('fetch-ai-models'),
                        style: style,
                        label: l.fetchModels,
                        icon: FLucideIcons.refreshCw,
                        loading: activeAction == _ConnectionAction.models,
                        onPress: locked ? null : getModels,
                      )
                    : null,
                autocorrect: false,
                enableSuggestions: false,
              ),
      );
    }

    Widget section(
      String title,
      List<Widget> children, {
      bool editable = true,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: context.theme.typography.body.lg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            ...children,
            if (editable) ...[
              const SizedBox(height: 16),
              LoadingButton(
                label: l.saveConfiguration,
                loading: activeAction == _ConnectionAction.save,
                onPress: locked ? null : save,
              ),
            ],
          ],
        ),
      ),
    );
    Widget testButton(_ConnectionTest target, String label) => LoadingButton(
      label: label,
      variant: .outline,
      loading: activeAction == target.action,
      onPress: locked ? null : () => test(target),
    );
    return settings.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => PageContent(
        children: [
          Text(
            l.configurationLoadFailed(
              localizeRuntimeMessage(l, serviceError(e)),
            ),
          ),
          FButton(
            onPress: () =>
                ref.read(connectionSettingsProvider.notifier).retryLoad(),
            child: Text(l.retry),
          ),
        ],
      ),
      data: (value) {
        if (!loaded) {
          fields[_ConnectionField.aiUrl]!.text = value.aiUrl;
          fields[_ConnectionField.model]!.text = value.model;
          fields[_ConnectionField.aiKey]!.text = value.aiKey;
          fields[_ConnectionField.tmdbToken]!.text = value.tmdbToken;
          fields[_ConnectionField.proxyUrl]!.text = value.proxyUrl;
          proxyAi = value.proxyAi;
          proxyMode = value.proxyMode;
          proxyTmdb = value.proxyTmdb;
          loaded = true;
        }
        return SettingsPage(
          configurationBackup: (saving) => ConfigurationBackupSection(
            locked: locked || saving,
            onWorking: (working) {
              if (mounted) setState(() => transferringConfiguration = working);
            },
            onImported: _refreshImportedFields,
          ),
          selectedTab: widget.tab.index,
          onTabChanged: (index) {
            if (index >= SettingsTab.values.length) return;
            final uri = GoRouterState.of(context).uri;
            context.go(
              uri
                  .replace(
                    queryParameters: {
                      ...uri.queryParameters,
                      'tab': SettingsTab.values[index].name,
                    },
                  )
                  .toString(),
            );
          },
          connectionTabs: [
            FTabEntry(
              label: Text(l.fileServers),
              child: const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Surface(child: WebDavManager()),
              ),
            ),
            FTabEntry(
              label: const Text('AI Agent'),
              child: section('AI Agent', [
                field(_ConnectionField.aiUrl, l.aiBaseUrl),
                field(_ConnectionField.model, l.modelName),
                field(_ConnectionField.aiKey, 'API Key'),
                testButton(_ConnectionTest.ai, l.testAi),
              ]),
            ),
            FTabEntry(
              label: const Text('TMDB'),
              child: section('TMDB', [
                field(
                  _ConnectionField.tmdbToken,
                  'API Key / Read Access Token',
                ),
                FSelect<NamingLanguage>.rich(
                  key: const ValueKey('naming-language-select'),
                  label: Text(context.l10n.namingLanguage),
                  enabled: !locked,
                  format: (value) => value.label,
                  control: .lifted(
                    value: appSettings.namingLanguage,
                    onChange: (value) async {
                      if (value == null ||
                          value == appSettings.namingLanguage) {
                        return;
                      }
                      setState(() => savingNamingSettings = true);
                      try {
                        await ref
                            .read(settingsProvider.notifier)
                            .update((s) => s.copyWith(namingLanguage: value));
                      } catch (e) {
                        if (context.mounted) {
                          notifyUser(
                            context,
                            context.l10n.saveFailed(
                              localizeRuntimeMessage(
                                context.l10n,
                                serviceError(e),
                              ),
                            ),
                            type: NoticeType.error,
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => savingNamingSettings = false);
                        }
                      }
                    },
                  ),
                  children: [
                    for (final language in NamingLanguage.values)
                      FSelectItem(title: Text(language.label), value: language),
                  ],
                ),
                const SizedBox(height: 18),
                FSelect<NamingFormat>.rich(
                  key: const ValueKey('naming-format-select'),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.namingFormat),
                      const SizedBox(width: 4),
                      IconAction(
                        key: const ValueKey('naming-format-help'),
                        label: l.namingFormatExamples,
                        icon: FLucideIcons.circleQuestionMark,
                        iconSize: 16,
                        onPress: () => showNamingFormatExamples(context),
                      ),
                    ],
                  ),
                  enabled: !locked,
                  format: (value) => namingFormatLabel(l, value),
                  control: .lifted(
                    value: appSettings.namingFormat,
                    onChange: (value) async {
                      if (value == null || value == appSettings.namingFormat) {
                        return;
                      }
                      setState(() => savingNamingSettings = true);
                      try {
                        await ref
                            .read(settingsProvider.notifier)
                            .update((s) => s.copyWith(namingFormat: value));
                      } catch (e) {
                        if (context.mounted) {
                          notifyUser(
                            context,
                            l.saveFailed(
                              localizeRuntimeMessage(l, serviceError(e)),
                            ),
                            type: NoticeType.error,
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => savingNamingSettings = false);
                        }
                      }
                    },
                  ),
                  children: [
                    for (final format in NamingFormat.values)
                      FSelectItem(
                        title: Text(namingFormatLabel(l, format)),
                        value: format,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                testButton(_ConnectionTest.tmdb, l.testTmdb),
              ]),
            ),
            FTabEntry(
              label: Text(l.httpProxy),
              child: section(l.httpProxy, [
                FSelect<ProxyMode>.rich(
                  label: Text(l.proxyMode),
                  enabled: !locked,
                  control: .lifted(
                    value: proxyMode,
                    onChange: (mode) {
                      if (mode != null) setState(() => proxyMode = mode);
                    },
                  ),
                  format: (mode) => _proxyLabel(context, mode),
                  children: [
                    for (final mode in ProxyMode.values)
                      FSelectItem(
                        title: Text(_proxyLabel(context, mode)),
                        value: mode,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (proxyMode == ProxyMode.manual)
                  field(_ConnectionField.proxyUrl, l.proxyAddress),
                FCheckbox(
                  label: Text(l.proxyAi),
                  value: proxyAi,
                  enabled: !locked,
                  onChange: (v) => setState(() => proxyAi = v),
                ),
                const SizedBox(height: 12),
                FCheckbox(
                  label: Text(l.proxyTmdb),
                  value: proxyTmdb,
                  enabled: !locked,
                  onChange: (v) => setState(() => proxyTmdb = v),
                ),
              ]),
            ),
            FTabEntry(
              label: Text(l.appAbout),
              child: section(l.appAbout, [
                const Row(
                  children: [
                    AzusaLogo(height: 40),
                    SizedBox(width: 10),
                    Text('Azusa'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(l.tmdbDisclaimer),
                const SizedBox(height: 12),
                FButton(
                  variant: .ghost,
                  onPress: () =>
                      openDocumentation(context, 'https://www.themoviedb.org'),
                  child: const Text('The Movie Database'),
                ),
                FButton(
                  variant: .ghost,
                  onPress: () =>
                      openDocumentation(context, 'https://hyperos.mi.com/font'),
                  child: Text(l.misansLicense),
                ),
              ], editable: false),
            ),
          ],
        );
      },
    );
  }
}

String _proxyLabel(BuildContext context, ProxyMode mode) => switch (mode) {
  ProxyMode.direct => context.l10n.directConnection,
  ProxyMode.system => context.l10n.systemProxyMode,
  ProxyMode.manual => context.l10n.manualProxyMode,
};
