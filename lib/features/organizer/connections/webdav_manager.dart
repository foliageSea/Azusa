import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/icon_action.dart';
import '../../../shared/localization.dart';
import '../../../shared/loading_button.dart';
import '../../../shared/runtime_localization.dart';
import '../../../shared/secret_text_field.dart';
import '../../../shared/widgets.dart';
import '../file_server/file_server.dart';
import '../file_server/file_server_connection.dart';
import '../file_server/file_server_factory.dart';
import '../organizer_state.dart';
import '../smb/smb_connection.dart';
import 'connection_settings.dart';
import 'file_server_connections.dart';
import 'http_clients.dart';
import 'webdav_connections.dart';
import 'webdav_switcher.dart';

Future<bool> confirmConnectionChange(
  BuildContext context,
  String title, {
  bool destructive = false,
}) async =>
    await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              const SizedBox(height: 24),
              FButton(
                variant: destructive ? .destructive : .primary,
                onPress: () => Navigator.of(context).pop(true),
                child: Text(context.l10n.confirmAction),
              ),
              const SizedBox(height: 8),
              FButton(
                variant: .outline,
                onPress: () => Navigator.of(context).pop(false),
                child: Text(context.l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;

enum _FileServerType {
  webdav('WebDAV'),
  smb('SMB');

  const _FileServerType(this.label);
  final String label;
}

class WebDavManager extends ConsumerStatefulWidget {
  const WebDavManager({super.key, this.compact = false, this.subtitle});
  final bool compact;
  final String? subtitle;
  @override
  ConsumerState<WebDavManager> createState() => _WebDavManagerState();
}

class _WebDavManagerState extends ConsumerState<WebDavManager> {
  bool working = false;

  bool get organizerLocked {
    final organizer = ref.read(organizerProvider);
    return organizer.busy || organizer.executing;
  }

  Future<void> run(Future<void> Function() action) async {
    if (working || organizerLocked) return;
    setState(() => working = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        notifyUser(
          context,
          localizeRuntimeMessage(context.l10n, serviceError(e)),
          type: NoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> select(String id) => run(() async {
    if (ref.read(organizerProvider).plan.isNotEmpty &&
        !await confirmConnectionChange(
          context,
          context.l10n.discardConnectionPreview,
        )) {
      return;
    }
    if (!mounted || organizerLocked) return;
    await ref.read(connectionSettingsProvider.notifier).selectConnection(id);
  });

  Future<void> edit([FileServerConnection? original]) => run(() async {
    if (original != null &&
        original.id ==
            ref.read(connectionSettingsProvider).requireValue.connectionId &&
        ref.read(organizerProvider).plan.isNotEmpty &&
        !await confirmConnectionChange(
          context,
          context.l10n.discardConnectionPreview,
        )) {
      return;
    }
    if (!mounted || organizerLocked) return;
    final editable = original == null
        ? null
        : await ref
              .read(fileServerConnectionsRepositoryProvider)
              .withPassword(original);
    if (!mounted || organizerLocked) return;
    await showFDialog<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
        builder: (context, style) => _FileServerEditor(value: editable),
      ),
    );
  });

  Future<void> remove(FileServerConnection item) => run(() async {
    if (!await confirmConnectionChange(
      context,
      context.l10n.deleteConnectionConfirmation(item.name),
      destructive: true,
    )) {
      return;
    }
    if (!mounted || organizerLocked) return;
    await ref
        .read(connectionSettingsProvider.notifier)
        .deleteConnection(item.id);
  });

  Future<void> testConnection(FileServerConnection item) => run(() async {
    FileServerClient? server;
    try {
      final connection = await ref
          .read(fileServerConnectionsRepositoryProvider)
          .withPassword(item);
      if (!mounted || organizerLocked) return;
      final globals = ref.read(connectionSettingsProvider).requireValue;
      server = ref.read(fileServerClientProvider)(
        globals.copyWith(fileServerConnection: connection),
      );
      await server.list(server.root);
      if (mounted) {
        notifyUser(
          context,
          context.l10n.connectionSucceeded(item.name),
          type: NoticeType.success,
        );
      }
    } finally {
      server?.close();
    }
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final organizer = ref.watch(organizerProvider);
    final locked = working || organizer.busy || organizer.executing;
    final active = ref
        .watch(connectionSettingsProvider)
        .asData
        ?.value
        .connectionId;
    final connections = ref.watch(fileServerConnectionsProvider);
    if (widget.compact) {
      final items = connections.asData?.value ?? const <FileServerConnection>[];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: items.isEmpty
                ? Text(l.nasDirectory, style: context.theme.typography.body.lg)
                : IntrinsicWidth(
                    child: WebDavSwitcher(
                      items: items,
                      activeId: active,
                      locked: locked,
                      onSelect: select,
                    ),
                  ),
          ),
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.subtitle!,
                style: context.theme.typography.body.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.fileServers,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconAction(
              key: const ValueKey('add-webdav-connection'),
              label: l.addFileServer,
              icon: FLucideIcons.plus,
              onPress: locked ? null : () => edit(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        connections.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Text(localizeRuntimeMessage(l, serviceError(e))),
          data: (items) => items.isEmpty
              ? Text(
                  l.noFileServers,
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        Container(
                          height: 1,
                          color: context.theme.colors.border,
                        ),
                      _connectionRow(items[i], active: active, locked: locked),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _connectionRow(
    FileServerConnection item, {
    required String? active,
    required bool locked,
  }) {
    final l = context.l10n;
    final current = item.id == active;
    final menu = FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.pencil),
              title: Text(l.editConnection),
              onPress: locked ? null : () => edit(item),
            ),
            FItem(
              prefix: const Icon(FLucideIcons.plugZap),
              title: Text(l.testWebdav),
              onPress: locked ? null : () => testConnection(item),
            ),
            FItem(
              variant: .destructive,
              prefix: const Icon(FLucideIcons.trash2),
              title: Text(l.deleteConnection),
              onPress: locked ? null : () => remove(item),
            ),
          ],
        ),
      ],
      builder: (_, controller, _) => FButton.icon(
        key: ValueKey('webdav-menu-${item.id}'),
        variant: .ghost,
        size: .sm,
        semanticsLabel: l.connectionActions(item.name),
        onPress: locked ? null : controller.toggle,
        child: const Icon(FLucideIcons.ellipsis),
      ),
    );
    final use = FButton(
      key: ValueKey('use-webdav-${item.id}'),
      variant: .outline,
      size: .sm,
      mainAxisSize: MainAxisSize.min,
      onPress: locked ? null : () => select(item.id),
      child: Text(l.useConnection),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 420;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    FLucideIcons.server,
                    size: 20,
                    color: context.theme.colors.mutedForeground,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.theme.typography.body.md.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            FBadge(
                              variant: .secondary,
                              child: Text(fileServerProtocolLabel(item)),
                            ),
                            if (current)
                              FBadge(
                                variant: .secondary,
                                child: Text(l.currentConnection),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fileServerDisplayAddress(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.typography.body.sm.copyWith(
                            color: context.theme.colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!current && !narrow) ...[const SizedBox(width: 16), use],
                  const SizedBox(width: 8),
                  menu,
                ],
              ),
              if (!current && narrow)
                Padding(
                  padding: const EdgeInsets.only(top: 12, left: 32),
                  child: Align(alignment: Alignment.centerLeft, child: use),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FileServerEditor extends ConsumerStatefulWidget {
  const _FileServerEditor({this.value});
  final FileServerConnection? value;
  @override
  ConsumerState<_FileServerEditor> createState() => _FileServerEditorState();
}

class _FileServerEditorState extends ConsumerState<_FileServerEditor> {
  WebDavConnection? get _webdav => switch (widget.value) {
    final WebDavConnection value => value,
    _ => null,
  };
  SmbConnection? get _smb => switch (widget.value) {
    final SmbConnection value => value,
    _ => null,
  };

  late final name = TextEditingController(text: widget.value?.name);
  late final url = TextEditingController(text: _webdav?.url);
  late final host = TextEditingController(text: _smb?.host);
  late final share = TextEditingController(text: _smb?.share);
  late final domain = TextEditingController(text: _smb?.domain);
  late final username = TextEditingController(
    text: _smb?.username ?? _webdav?.username,
  );
  late final password = TextEditingController(
    text: _smb?.password ?? _webdav?.password,
  );
  late var type = _smb == null ? _FileServerType.webdav : _FileServerType.smb;
  late bool proxy = _webdav?.useProxy ?? false;
  bool visible = false, busy = false, testing = false;

  @override
  void dispose() {
    for (final field in [name, url, host, share, domain, username, password]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> submit({bool test = false}) async {
    final organizer = ref.read(organizerProvider);
    if (busy || organizer.busy || organizer.executing) return;
    setState(() {
      busy = true;
      testing = test;
    });
    FileServerClient? server;
    try {
      final id = widget.value?.id ?? newConnectionId();
      final connectionName = name.text.trim();
      if (connectionName.isEmpty) throw const FormatException('请输入连接名称');
      final value = switch (type) {
        _FileServerType.webdav => WebDavConnection(
          id: id,
          name: connectionName,
          url: url.text.trim(),
          username: username.text.trim(),
          password: password.text,
          useProxy: proxy,
        ),
        _FileServerType.smb => SmbConnection(
          id: id,
          name: connectionName,
          host: host.text.trim(),
          share: share.text.trim(),
          domain: domain.text.trim(),
          username: username.text.trim(),
          password: password.text,
        ),
      };
      ref.read(fileServerFactoryProvider).validate(value);
      if (test) {
        final globals = ref.read(connectionSettingsProvider).requireValue;
        server = ref.read(fileServerClientProvider)(
          globals.copyWith(fileServerConnection: value),
        );
        await server.list(server.root);
        if (mounted) {
          notifyUser(
            context,
            context.l10n.connectionSucceeded(value.name),
            type: NoticeType.success,
          );
        }
      } else {
        await ref
            .read(connectionSettingsProvider.notifier)
            .saveConnection(value);
        if (mounted) {
          notifyUser(
            context,
            context.l10n.configurationSaved,
            type: NoticeType.success,
          );
          setState(() => busy = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        notifyUser(
          context,
          localizeRuntimeMessage(context.l10n, serviceError(e)),
          type: NoticeType.error,
        );
      }
    } finally {
      server?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final organizer = ref.watch(organizerProvider);
    final locked = busy || organizer.busy || organizer.executing;
    final smb = type == _FileServerType.smb;
    Widget field(
      String key,
      TextEditingController controller,
      String label,
      String hint,
    ) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: FTextField(
        key: ValueKey(key),
        label: Text(label),
        hint: hint,
        enabled: !locked,
        control: .managed(controller: controller),
        autocorrect: false,
        enableSuggestions: false,
      ),
    );
    return PopScope(
      canPop: !busy,
      child: Padding(
        key: const ValueKey('webdav-editor-content'),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.value == null ? l.addFileServer : l.editConnection,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FSelect<_FileServerType>.rich(
                key: const ValueKey('file-server-type'),
                autoHide: true,
                label: Text(l.fileServerType),
                enabled: !locked && widget.value == null,
                format: (type) => type.label,
                control: .lifted(
                  value: type,
                  onChange: (value) {
                    if (value != null && !locked && widget.value == null) {
                      setState(() {
                        type = value;
                        visible = false;
                      });
                    }
                  },
                ),
                children: [
                  for (final option in _FileServerType.values)
                    FSelectItem(
                      title: Text(
                        option.label,
                        key: ValueKey('file-server-type-option-${option.name}'),
                      ),
                      value: option,
                    ),
                ],
              ),
              field(
                'webdav-editor-field-0',
                name,
                l.connectionName,
                l.connectionNameHint,
              ),
              if (smb) ...[
                field('smb-editor-host', host, l.smbHost, l.smbHostHint),
                field('smb-editor-share', share, l.smbShare, l.smbShareHint),
                field(
                  'smb-editor-domain',
                  domain,
                  l.smbDomain,
                  l.smbDomainHint,
                ),
              ] else
                field(
                  'webdav-editor-field-1',
                  url,
                  l.webdavUrl,
                  l.webdavUrlHint,
                ),
              field(
                'webdav-editor-field-2',
                username,
                l.username,
                l.usernameHint,
              ),
              const SizedBox(height: 16),
              SecretTextField(
                fieldKey: const ValueKey('webdav-editor-password'),
                toggleKey: const ValueKey('webdav-editor-toggle-password'),
                controller: password,
                label: l.password,
                hint: l.passwordHint,
                enabled: !locked,
                visible: visible,
                showLabel: l.showPassword,
                hideLabel: l.hidePassword,
                onVisibilityChange: (v) => setState(() => visible = v),
              ),
              if (!smb) ...[
                const SizedBox(height: 16),
                FCheckbox(
                  label: Text(l.proxyWebdav),
                  value: proxy,
                  enabled: !locked,
                  onChange: (v) => setState(() => proxy = v),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  IntrinsicWidth(
                    child: LoadingButton(
                      label: l.testWebdav,
                      loading: busy && testing,
                      variant: .outline,
                      onPress: locked ? null : () => submit(test: true),
                    ),
                  ),
                  FButton(
                    mainAxisSize: MainAxisSize.min,
                    variant: .outline,
                    onPress: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l.cancel),
                  ),
                  IntrinsicWidth(
                    child: LoadingButton(
                      label: l.save,
                      loading: busy && !testing,
                      onPress: locked ? null : submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
