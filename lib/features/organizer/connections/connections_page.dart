import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/azusa_logo.dart';
import '../../../shared/widgets.dart';
import '../../../shared/localization.dart';
import '../../../core/settings/settings.dart';
import '../../../core/settings/naming_language.dart';
import '../../settings/settings_page.dart';
import 'connection_settings.dart';
import 'http_clients.dart';
import '../organizer_state.dart';
import '../ai/tmdb.dart';
import '../dav/webdav.dart';

class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key});
  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  final fields = List.generate(8, (_) => TextEditingController());
  bool loaded = false, busy = false;
  bool savingNamingLanguage = false;
  bool proxyAi = true, proxyTmdb = true, proxyWebdav = false;
  ProxyMode proxyMode = ProxyMode.direct;

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  ConnectionSettings get current => ConnectionSettings(
    webdavUrl: fields[0].text.trim(),
    username: fields[1].text.trim(),
    webdavPassword: fields[2].text,
    aiUrl: fields[3].text.trim(),
    model: fields[4].text.trim(),
    aiKey: fields[5].text.trim(),
    tmdbToken: fields[6].text.trim(),
    proxyUrl: fields[7].text.trim(),
    proxyMode: proxyMode,
    proxyAi: proxyAi,
    proxyTmdb: proxyTmdb,
    proxyWebdav: proxyWebdav,
  );

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final value = current;
      if (value.webdavUrl.isNotEmpty) {
        validatedHttpUrl(value.webdavUrl, allowHttp: true);
      }
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
        notifyUser(context, '配置已保存', type: NoticeType.success);
      }
    } catch (e) {
      if (mounted) {
        notifyUser(context, '保存失败：${serviceError(e)}', type: NoticeType.error);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> test(NetworkService service) async {
    if (busy) return;
    setState(() => busy = true);
    final value = current;
    Dio? ai;
    WebDavClient? dav;
    TmdbClient? tmdb;
    try {
      switch (service) {
        case NetworkService.webdav:
          dav = WebDavClient(value);
          await dav.list(dav.root);
        case NetworkService.tmdb:
          tmdb = TmdbClient(
            value,
            namingLanguage: ref.read(settingsProvider).namingLanguage,
          );
          await tmdb.search('Breaking Bad');
        case NetworkService.ai:
          final base = validatedHttpUrl(value.aiUrl, allowHttp: true);
          ai = createServiceClient(value);
          final response = await ai.getUri<Object>(
            base.replace(
              path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/models',
            ),
            options: Options(
              headers: {
                if (value.aiKey.isNotEmpty)
                  'Authorization': 'Bearer ${value.aiKey}',
              },
            ),
          );
          if (response.data is! Map) {
            throw const FormatException('AI /models 未返回有效 JSON');
          }
      }
      if (mounted) {
        notifyUser(
          context,
          '连接成功 · ${usesProxy(value, service) ? value.proxyMode.label : '直连'}',
          type: NoticeType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        notifyUser(context, '连接失败：${serviceError(e)}', type: NoticeType.error);
      }
    } finally {
      ai?.close(force: true);
      dav?.close();
      tmdb?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(settingsProvider);
    final settings = ref.watch(connectionSettingsProvider);
    final organizer = ref.watch(organizerProvider);
    final locked =
        busy || savingNamingLanguage || organizer.busy || organizer.executing;
    Widget field(int i, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: FTextField(
        label: Text(label),
        enabled: !locked,
        control: .managed(controller: fields[i]),
        obscureText: [2, 5, 6].contains(i),
        autocorrect: false,
        enableSuggestions: false,
      ),
    );
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
              FButton(onPress: locked ? null : save, child: const Text('保存配置')),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: FCircularProgress()),
                ),
            ],
          ],
        ),
      ),
    );
    return settings.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => PageContent(
        children: [
          Text('读取配置失败：${serviceError(e)}'),
          FButton(
            onPress: () => ref.invalidate(connectionSettingsProvider),
            child: const Text('重试'),
          ),
        ],
      ),
      data: (value) {
        if (!loaded) {
          final values = [
            value.webdavUrl,
            value.username,
            value.webdavPassword,
            value.aiUrl,
            value.model,
            value.aiKey,
            value.tmdbToken,
            value.proxyUrl,
          ];
          for (var i = 0; i < fields.length; i++) {
            fields[i].text = values[i];
          }
          proxyAi = value.proxyAi;
          proxyMode = value.proxyMode;
          proxyTmdb = value.proxyTmdb;
          proxyWebdav = value.proxyWebdav;
          loaded = true;
        }
        return SettingsPage(
          connectionTabs: [
            FTabEntry(
              label: const Text('WebDAV'),
              child: section('WebDAV', [
                field(0, 'WebDAV 地址'),
                field(1, '用户名'),
                field(2, '密码'),
                FButton(
                  variant: .outline,
                  onPress: locked ? null : () => test(NetworkService.webdav),
                  child: const Text('测试 WebDAV'),
                ),
              ]),
            ),
            FTabEntry(
              label: const Text('AI Agent'),
              child: section('AI Agent', [
                field(3, 'OpenAI 兼容 API 基础地址'),
                field(4, '模型名称'),
                field(5, 'API Key'),
                FButton(
                  variant: .outline,
                  onPress: locked ? null : () => test(NetworkService.ai),
                  child: const Text('测试 AI'),
                ),
              ]),
            ),
            FTabEntry(
              label: const Text('TMDB'),
              child: section('TMDB', [
                field(6, 'API Key / Read Access Token'),
                FSelect<NamingLanguage>.rich(
                  key: const ValueKey('naming-language-select'),
                  label: Text(context.l10n.namingLanguage),
                  enabled: !locked,
                  format: (value) => value.label,
                  control: .lifted(
                    value: appSettings.namingLanguage,
                    onChange: (value) async {
                      if (value == null || value == appSettings.namingLanguage) {
                        return;
                      }
                      setState(() => savingNamingLanguage = true);
                      try {
                        await ref
                            .read(settingsProvider.notifier)
                            .update((s) => s.copyWith(namingLanguage: value));
                      } catch (e) {
                        if (context.mounted) {
                          notifyUser(
                            context,
                            '保存失败：${serviceError(e)}',
                            type: NoticeType.error,
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => savingNamingLanguage = false);
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
                FButton(
                  variant: .outline,
                  onPress: locked ? null : () => test(NetworkService.tmdb),
                  child: const Text('测试 TMDB'),
                ),
              ]),
            ),
            FTabEntry(
              label: const Text('HTTP 代理'),
              child: section('HTTP 代理', [
                FSelect<ProxyMode>.rich(
                  label: const Text('代理模式'),
                  enabled: !locked,
                  control: .lifted(
                    value: proxyMode,
                    onChange: (mode) {
                      if (mode != null) setState(() => proxyMode = mode);
                    },
                  ),
                  format: (mode) => mode.label,
                  children: [
                    for (final mode in ProxyMode.values)
                      FSelectItem(title: Text(mode.label), value: mode),
                  ],
                ),
                const SizedBox(height: 18),
                if (proxyMode == ProxyMode.manual)
                  field(7, '代理地址（http://主机:端口）'),
                FCheckbox(
                  label: const Text('AI 使用代理'),
                  value: proxyAi,
                  enabled: !locked,
                  onChange: (v) => setState(() => proxyAi = v),
                ),
                const SizedBox(height: 12),
                FCheckbox(
                  label: const Text('TMDB 使用代理'),
                  value: proxyTmdb,
                  enabled: !locked,
                  onChange: (v) => setState(() => proxyTmdb = v),
                ),
                const SizedBox(height: 12),
                FCheckbox(
                  label: const Text('WebDAV 使用代理'),
                  value: proxyWebdav,
                  enabled: !locked,
                  onChange: (v) => setState(() => proxyWebdav = v),
                ),
              ]),
            ),
            FTabEntry(
              label: const Text('关于'),
              child: section('关于', [
                const Row(
                  children: [
                    AzusaLogo(height: 40),
                    SizedBox(width: 10),
                    Text('Azusa'),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'This product uses the TMDB API but is not endorsed or certified by TMDB.',
                ),
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
                  child: const Text('MiSans 字体许可'),
                ),
              ], editable: false),
            ),
          ],
        );
      },
    );
  }
}
