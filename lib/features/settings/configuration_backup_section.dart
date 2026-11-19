import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../organizer/connections/configuration_backup.dart';
import '../organizer/connections/configuration_transfer.dart';
import '../organizer/connections/connection_settings.dart';
import 'configuration_backup_files.dart';

class ConfigurationBackupSection extends ConsumerStatefulWidget {
  const ConfigurationBackupSection({
    required this.locked,
    required this.onWorking,
    required this.onImported,
    super.key,
  });

  final bool locked;
  final ValueChanged<bool> onWorking;
  final ValueChanged<Set<BackupSection>> onImported;

  @override
  ConsumerState<ConfigurationBackupSection> createState() =>
      _ConfigurationBackupSectionState();
}

class _ConfigurationBackupSectionState
    extends ConsumerState<ConfigurationBackupSection> {
  bool _working = false;
  final _codec = ConfigurationBackupCodec();

  Future<_BackupChoice?> _dialog(
    _BackupDialogMode mode, {
    ConfigurationImportPreview? preview,
  }) => showFDialog<_BackupChoice>(
    context: context,
    useSafeArea: true,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => _BackupDialog(mode: mode, preview: preview),
    ),
  );

  Future<void> _run(
    Future<bool> Function() action, {
    required bool importing,
  }) async {
    if (_working || widget.locked) return;
    setState(() => _working = true);
    final onWorking = widget.onWorking;
    onWorking(true);
    try {
      final completed = await action();
      if (!mounted || !completed) return;
      final l = context.l10n;
      notifyUser(
        context,
        importing ? l.backupImported : l.backupExported,
        type: NoticeType.success,
      );
    } catch (error) {
      if (!mounted) return;
      final l = context.l10n;
      final message = switch (error) {
        BackupException(:final problem) => switch (problem) {
          BackupProblem.invalid => l.backupInvalid,
          BackupProblem.unsupported => l.backupUnsupported,
          BackupProblem.tooLarge => l.backupTooLarge,
          BackupProblem.passphraseRequired ||
          BackupProblem.unlockFailed => l.backupUnlockFailed,
        },
        ConfigurationImportChanged() => l.backupImportChanged,
        ConfigurationImportRollbackFailed() => l.backupRollbackFailed,
        _ => importing ? l.backupImportFailed : l.backupExportFailed,
      };
      // Import exceptions may originate from third-party file or storage code.
      // Never pass exception text (which can contain credentials) to the UI.
      notifyUser(context, message, type: NoticeType.error);
    } finally {
      onWorking(false);
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _export(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    return _run(() async {
      final choice = await _dialog(_BackupDialogMode.export);
      if (choice == null || !mounted) return false;
      final files = ref.read(configurationBackupFilesProvider);
      final backup = await ref
          .read(connectionSettingsProvider.notifier)
          .exportConfiguration(
            choice.selected,
            includeCredentials: choice.passphrase != null,
          );
      final bytes = await _codec.encode(backup, passphrase: choice.passphrase);
      if (!mounted) return false;
      return files.save(bytes, sharePositionOrigin: origin);
    }, importing: false);
  }

  Future<void> _import() => _run(() async {
    final bytes = await ref.read(configurationBackupFilesProvider).open();
    if (bytes == null || !mounted) return false;
    String? passphrase;
    if (_codec.isEncrypted(bytes)) {
      final unlock = await _dialog(_BackupDialogMode.unlock);
      if (unlock == null || !mounted) return false;
      passphrase = unlock.passphrase;
    }
    final backup = await _codec.decode(bytes, passphrase: passphrase);
    if (!mounted) return false;
    final controller = ref.read(connectionSettingsProvider.notifier);
    final preview = await controller.previewConfiguration(backup);
    if (!mounted) return false;
    final choice = await _dialog(_BackupDialogMode.import, preview: preview);
    if (choice == null || !mounted) return false;
    final onImported = widget.onImported;
    await controller.importConfiguration(
      preview,
      choice.selected,
      replacementAiKey: choice.replacementAiKey,
    );
    onImported(choice.selected);
    return true;
  }, importing: true);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final disabled = widget.locked || _working;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.configurationBackup,
            style: context.theme.typography.body.lg.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Builder(
                builder: (context) => FButton(
                  key: const ValueKey('export-configuration'),
                  variant: .outline,
                  mainAxisSize: MainAxisSize.min,
                  builder: responsiveButtonContent,
                  onPress: disabled ? null : () => _export(context),
                  child: Text(l.backupExport),
                ),
              ),
              FButton(
                key: const ValueKey('import-configuration'),
                variant: .outline,
                mainAxisSize: MainAxisSize.min,
                builder: responsiveButtonContent,
                onPress: disabled ? null : _import,
                child: Text(l.backupImport),
              ),
            ],
          ),
          if (_working) ...[
            const SizedBox(height: 12),
            const Center(child: FCircularProgress()),
          ],
        ],
      ),
    );
  }
}

enum _BackupDialogMode { export, unlock, import }

typedef _BackupChoice = ({
  Set<BackupSection> selected,
  String? passphrase,
  String? replacementAiKey,
});

class _BackupDialog extends StatefulWidget {
  const _BackupDialog({required this.mode, this.preview});
  final _BackupDialogMode mode;
  final ConfigurationImportPreview? preview;

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  late final _selected = {..._available};
  Set<BackupSection> get _available =>
      widget.preview?.backup.sections ?? BackupSection.values.toSet();
  final _input = TextEditingController();
  final _confirmation = TextEditingController();
  bool _includeCredentials = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_changed);
    _confirmation.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _input.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Widget _secret(TextEditingController controller, String label, String hint) =>
      FTextField(
        label: Text(label),
        hint: hint,
        control: .managed(controller: controller),
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final preview = widget.preview;
    final exporting = widget.mode == _BackupDialogMode.export;
    final unlocking = widget.mode == _BackupDialogMode.unlock;
    final needsKey =
        preview?.aiNeedsKey == true && _selected.contains(BackupSection.ai);
    final enabled = unlocking
        ? _input.text.isNotEmpty
        : _selected.isNotEmpty &&
              (!needsKey || _input.text.trim().isNotEmpty) &&
              (!_includeCredentials ||
                  (_input.text.trim().runes.length >=
                          ConfigurationBackupCodec.minPassphraseLength &&
                      _input.text == _confirmation.text));
    final title = unlocking
        ? l.backupUnlock
        : exporting
        ? l.backupExport
        : l.backupPreview;
    final action = unlocking
        ? l.backupUnlock
        : exporting
        ? l.backupExport
        : l.backupImport;
    String label(BackupSection section) => switch (section) {
      BackupSection.webdav => 'WebDAV',
      BackupSection.tmdb => 'TMDB',
      BackupSection.ai => 'AI Agent',
    };
    String summary(BackupSection section) => switch (section) {
      BackupSection.webdav => l.backupDavSummary(
        preview!.additions.length,
        preview.skipped,
      ),
      BackupSection.tmdb || BackupSection.ai => l.backupOverwrite,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: context.theme.typography.body.lg.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (!unlocking)
            for (final section in _available) ...[
              FCheckbox(
                label: Text(label(section)),
                value: _selected.contains(section),
                onChange: (checked) => setState(() {
                  if (checked) {
                    _selected.add(section);
                  } else {
                    _selected.remove(section);
                  }
                }),
              ),
              if (preview != null && _selected.contains(section)) ...[
                Text(
                  '${summary(section)} · ${preview.backup.hasCredentials(section) ? l.backupWithCredentials : l.backupWithoutCredentials}',
                ),
                if (section == BackupSection.webdav &&
                    preview.additions.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 124),
                    child: ListView.builder(
                      primary: false,
                      shrinkWrap: true,
                      itemCount: preview.additions.length,
                      itemBuilder: (context, index) {
                        final dav = preview.additions[index];
                        return Text(
                          '${dav.name} · ${dav.url}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ),
                if (section == BackupSection.ai &&
                    preview.backup.ai!.url.isNotEmpty)
                  Text(preview.backup.ai!.url),
                if (section == BackupSection.ai &&
                    preview.backup.ai!.model.isNotEmpty)
                  Text('${l.modelName}: ${preview.backup.ai!.model}'),
              ],
              const SizedBox(height: 8),
            ],
          if (exporting)
            FCheckbox(
              label: Text(l.backupIncludeCredentials),
              value: _includeCredentials,
              onChange: (value) => setState(() => _includeCredentials = value),
            ),
          if (_includeCredentials || unlocking) ...[
            const SizedBox(height: 8),
            _secret(
              _input,
              _includeCredentials ? l.backupNewPassphrase : l.backupPassphrase,
              l.backupPassphraseHint,
            ),
            if (_includeCredentials) ...[
              const SizedBox(height: 8),
              _secret(
                _confirmation,
                l.backupConfirmPassphrase,
                l.backupConfirmPassphraseHint,
              ),
              if (_confirmation.text.isNotEmpty &&
                  _input.text != _confirmation.text)
                Text(l.backupPassphraseMismatch),
            ],
          ],
          if (needsKey) ...[
            const SizedBox(height: 8),
            _secret(
              _input,
              l.backupReplacementAiKey,
              l.backupReplacementAiKeyHint,
            ),
          ],
          const SizedBox(height: 16),
          FButton(
            builder: responsiveButtonContent,
            onPress: enabled
                ? () => Navigator.of(context).pop<_BackupChoice>((
                    selected: Set.of(_selected),
                    passphrase: _includeCredentials || unlocking
                        ? _input.text
                        : null,
                    replacementAiKey: needsKey ? _input.text : null,
                  ))
                : null,
            child: Text(action),
          ),
          const SizedBox(height: 8),
          FButton(
            builder: responsiveButtonContent,
            variant: .outline,
            onPress: () => Navigator.of(context).pop(),
            child: Text(l.cancel),
          ),
        ],
      ),
    );
  }
}
