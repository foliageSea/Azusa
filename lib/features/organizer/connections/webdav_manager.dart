import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/localization.dart';
import '../../../shared/loading_button.dart';
import '../../../shared/runtime_localization.dart';
import '../../../shared/secret_text_field.dart';
import '../../../shared/widgets.dart';
import '../organizer_state.dart';
import '../dav/webdav.dart';
import 'connection_settings.dart';
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

class WebDavManager extends ConsumerStatefulWidget {
  const WebDavManager({super.key, this.compact = false, this.subtitle});
  final bool compact;
  final String? subtitle;
  @override
  ConsumerState<WebDavManager> createState() => _WebDavManagerState();
}

class _WebDavManagerState extends ConsumerState<WebDavManager> {
  bool working = false;

  Future<void> run(Future<void> Function() action) async {
    if (working) return;
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
    await ref.read(connectionSettingsProvider.notifier).selectConnection(id);
  });

  Future<void> edit([WebDavConnection? value]) => run(() async {
    final original = value;
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
    final editable = original == null
        ? null
        : await ref
              .read(webDavConnectionsRepositoryProvider)
              .withPassword(original);
    if (!mounted) return;
    await showFDialog<void>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
        builder: (context, style) => _ConnectionEditor(value: editable),
      ),
    );
  });

  Future<void> remove(WebDavConnection item) => run(() async {
    if (!await confirmConnectionChange(
      context,
      context.l10n.deleteConnectionConfirmation(item.name),
      destructive: true,
    )) {
      return;
    }
    await ref
        .read(connectionSettingsProvider.notifier)
        .deleteConnection(item.id);
  });

  Future<void> testConnection(WebDavConnection item) => run(() async {
    WebDavClient? dav;
    try {
      dav = ref.read(webDavFactoryProvider)(
        (await ref.read(webDavConnectionsRepositoryProvider).withPassword(item))
            .apply(ref.read(connectionSettingsProvider).requireValue),
      );
      await dav.list(dav.root);
      if (mounted) {
        notifyUser(
          context,
          context.l10n.connectionSucceeded(item.name),
          type: NoticeType.success,
        );
      }
    } finally {
      dav?.close();
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
    final connections = ref.watch(webDavConnectionsProvider);
    if (widget.compact) {
      final items = connections.asData?.value ?? const <WebDavConnection>[];
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
                'WebDAV',
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FButton(
              key: const ValueKey('add-webdav-connection'),
              size: .sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.plus),
              onPress: locked ? null : () => edit(),
              child: Text(l.addWebdavConnection),
            ),
          ],
        ),
        const SizedBox(height: 16),
        connections.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Text(localizeRuntimeMessage(l, serviceError(e))),
          data: (items) => Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Container(height: 1, color: context.theme.colors.border),
                _connectionRow(items[i], active: active, locked: locked),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _connectionRow(
    WebDavConnection item, {
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
                            if (current)
                              FBadge(
                                variant: .secondary,
                                child: Text(l.currentConnection),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.url,
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

class _ConnectionEditor extends ConsumerStatefulWidget {
  const _ConnectionEditor({this.value});
  final WebDavConnection? value;
  @override
  ConsumerState<_ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends ConsumerState<_ConnectionEditor> {
  late final fields = [
    widget.value?.name ?? '',
    widget.value?.url ?? '',
    widget.value?.username ?? '',
    widget.value?.password ?? '',
  ].map((text) => TextEditingController(text: text)).toList();
  late bool proxy = widget.value?.useProxy ?? false;
  bool visible = false, busy = false, testing = false;
  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> submit({bool test = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      testing = test;
    });
    WebDavClient? dav;
    try {
      final value = WebDavConnection(
        id: widget.value?.id ?? newConnectionId(),
        name: fields[0].text.trim(),
        url: fields[1].text.trim(),
        username: fields[2].text.trim(),
        password: fields[3].text,
        useProxy: proxy,
      );
      if (test) {
        dav = WebDavClient(
          value.apply(ref.read(connectionSettingsProvider).requireValue),
        );
        await dav.list(dav.root);
        if (mounted) {
          notifyUser(
            context,
            context.l10n.connectionSucceeded(context.l10n.webdavConnection),
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
      dav?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final organizer = ref.watch(organizerProvider);
    final locked = busy || organizer.busy || organizer.executing;
    final labels = [l.connectionName, l.webdavUrl, l.username];
    final hints = [l.connectionNameHint, l.webdavUrlHint, l.usernameHint];
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
                widget.value == null ? l.addWebdavConnection : l.editConnection,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FTextField(
                    key: ValueKey('webdav-editor-field-$i'),
                    label: Text(labels[i]),
                    hint: hints[i],
                    enabled: !locked,
                    control: .managed(controller: fields[i]),
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
              const SizedBox(height: 16),
              SecretTextField(
                fieldKey: const ValueKey('webdav-editor-password'),
                toggleKey: const ValueKey('webdav-editor-toggle-password'),
                controller: fields[3],
                label: l.password,
                hint: l.passwordHint,
                enabled: !locked,
                visible: visible,
                showLabel: l.showPassword,
                hideLabel: l.hidePassword,
                onVisibilityChange: (v) => setState(() => visible = v),
              ),
              const SizedBox(height: 16),
              FCheckbox(
                label: Text(l.proxyWebdav),
                value: proxy,
                enabled: !locked,
                onChange: (v) => setState(() => proxy = v),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final test = IntrinsicWidth(
                    child: LoadingButton(
                      label: l.testWebdav,
                      loading: busy && testing,
                      variant: .outline,
                      onPress: locked ? null : () => submit(test: true),
                    ),
                  );
                  final save = IntrinsicWidth(
                    child: LoadingButton(
                      label: l.save,
                      loading: busy && !testing,
                      onPress: locked ? null : submit,
                    ),
                  );
                  final cancel = FButton(
                    mainAxisSize: MainAxisSize.min,
                    variant: .ghost,
                    onPress: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l.cancel),
                  );
                  final primaryActions = Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [cancel, save],
                  );
                  if (constraints.maxWidth < 400) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: test),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: primaryActions,
                        ),
                      ],
                    );
                  }
                  return Row(children: [test, const Spacer(), primaryActions]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
