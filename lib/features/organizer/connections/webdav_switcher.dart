import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/localization.dart';
import '../../../shared/responsive_button.dart';
import '../organizer_state.dart';
import '../../settings/settings_tab.dart';
import 'connection_settings.dart';
import 'webdav_connections.dart';

class WebDavSwitcher extends ConsumerWidget {
  const WebDavSwitcher({
    required this.items,
    required this.activeId,
    required this.locked,
    required this.onSelect,
    super.key,
  });

  final List<WebDavConnection> items;
  final String? activeId;
  final bool locked;
  final Future<void> Function(String) onSelect;

  bool _locked(WidgetRef ref) {
    final state = ref.read(organizerProvider);
    return locked || state.busy || state.executing;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final name =
        items.where((item) => item.id == activeId).firstOrNull?.name ??
        l.webdavConnection;
    Widget trigger(VoidCallback open) => FButton(
      key: const ValueKey('webdav-switcher-trigger'),
      semanticsLabel: '${l.switchConnection}: $name',
      variant: .ghost,
      mainAxisSize: MainAxisSize.min,
      prefix: const Icon(FLucideIcons.server),
      suffix: Icon(
        FLucideIcons.chevronDown,
        size: 14,
        color: context.theme.colors.mutedForeground,
      ),
      builder: responsiveButtonContent,
      onPress: locked ? null : open,
      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    void manage() {
      if (!_locked(ref)) context.go(SettingsTab.webdav.location);
    }

    if (MediaQuery.sizeOf(context).width < 600) {
      return trigger(() async {
        final result = await showFSheet<_Selection>(
          context: context,
          side: .btt,
          useSafeArea: true,
          mainAxisMaxRatio: 0.75,
          builder: (context) => _ConnectionPanel(
            items: items,
            activeId: activeId,
            onSelected: (id) => Navigator.of(context).pop(_Selection(id)),
            onManage: () => Navigator.of(context).pop(const _Selection(null)),
          ),
        );
        if (!context.mounted || result == null || _locked(ref)) return;
        if (result.id == null) {
          manage();
        } else if (result.id !=
            ref.read(connectionSettingsProvider).asData?.value.connectionId) {
          await onSelect(result.id!);
        }
      });
    }
    return FPopover(
      popoverAnchor: Alignment.topLeft,
      childAnchor: Alignment.bottomLeft,
      popoverBuilder: (_, controller) => Container(
        key: const ValueKey('webdav-switcher-popover-border'),
        width: 340,
        decoration: BoxDecoration(
          borderRadius: context.theme.style.borderRadius.md,
        ),
        clipBehavior: Clip.antiAlias,
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: context.theme.colors.border),
          borderRadius: context.theme.style.borderRadius.md,
        ),
        child: _ConnectionPanel(
          items: items,
          activeId: activeId,
          onSelected: (id) async {
            await controller.hide();
            if (!context.mounted || _locked(ref)) return;
            if (id !=
                ref
                    .read(connectionSettingsProvider)
                    .asData
                    ?.value
                    .connectionId) {
              await onSelect(id);
            }
          },
          onManage: () async {
            await controller.hide();
            if (context.mounted) manage();
          },
        ),
      ),
      builder: (_, controller, _) => trigger(controller.toggle),
    );
  }
}

class _Selection {
  const _Selection(this.id);
  final String? id;
}

String _host(String url) => Uri.tryParse(url)?.authority ?? url;

class _ConnectionPanel extends ConsumerStatefulWidget {
  const _ConnectionPanel({
    required this.items,
    required this.activeId,
    required this.onSelected,
    required this.onManage,
  });
  final List<WebDavConnection> items;
  final String? activeId;
  final ValueChanged<String> onSelected;
  final VoidCallback onManage;

  @override
  ConsumerState<_ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends ConsumerState<_ConnectionPanel> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final state = ref.watch(organizerProvider);
    final locked = state.busy || state.executing;
    final activeId =
        ref.watch(connectionSettingsProvider).asData?.value.connectionId ??
        widget.activeId;
    final items = widget.items
        .where(
          (item) => '${item.name} ${_host(item.url)}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    return Container(
      key: const ValueKey('webdav-switcher-panel'),
      color: theme.colors.background,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text(
              l.switchConnection,
              style: theme.typography.body.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.items.length > 6) ...[
            FTextField(
              key: const ValueKey('webdav-switcher-search'),
              hint: l.searchConnections,
              enabled: !locked,
              control: .managed(
                onChange: (value) => setState(() => query = value.text),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in items)
                      FItem(
                        key: ValueKey('webdav-switcher-item-${item.id}'),
                        prefix: const Icon(FLucideIcons.server),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _host(item.url),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        suffix: item.id == activeId
                            ? Icon(
                                FLucideIcons.check,
                                color: theme.colors.primary,
                              )
                            : null,
                        semanticsLabel: item.name,
                        semanticsChecked: item.id == activeId,
                        onPress: locked
                            ? null
                            : () => widget.onSelected(item.id),
                      ),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l.noConnectionsFound),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: theme.colors.border),
          const SizedBox(height: 8),
          FItem(
            key: const ValueKey('manage-webdav-connections'),
            prefix: const Icon(FLucideIcons.settings2),
            title: Text(l.manageWebdavConnections),
            onPress: locked ? null : widget.onManage,
          ),
        ],
      ),
    );
  }
}
