import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/runtime_localization.dart';
import '../../shared/status_badge.dart';
import '../../shared/widgets.dart';
import '../organizer/ai/agent_activity.dart';
import '../organizer/ai/folder_layout.dart';
import '../organizer/connections/connection_settings.dart';
import '../organizer/connections/webdav_manager.dart';
import '../organizer/dav/dav_paths.dart';
import '../organizer/organizer_state.dart';
import '../organizer/rename_plan.dart';
import '../settings/settings_tab.dart';
import 'assistant_state.dart';
import 'plan_tree.dart';
import 'plan_tree_view.dart';

/// Width at which the plan sits beside the conversation instead of in a sheet.
const _splitWidth = 960.0;

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode(debugLabel: 'assistant input');
  final _scroll = ScrollController();
  String? _selectedPrompt;

  @override
  void initState() {
    super.initState();
    _input.addListener(_inputChanged);
  }

  void _inputChanged() => setState(() {});

  @override
  void dispose() {
    _input
      ..removeListener(_inputChanged)
      ..dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AssistantController get _assistant => ref.read(assistantProvider.notifier);

  void _selectDirectory() {
    final organizer = ref.read(organizerProvider);
    if (organizer.busy || organizer.executing) return;
    context.go('/organize');
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<bool> _confirm(String title, String detail, String action) async =>
      await showFDialog<bool>(
        context: context,
        builder: (context, style, animation) => FDialog(
          animation: animation,
          builder: (context, style) => EscapeDismiss(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: context.theme.typography.body.lg),
                  const SizedBox(height: 12),
                  Text(
                    detail,
                    style: context.theme.typography.body.sm.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      FButton(
                        variant: .outline,
                        mainAxisSize: MainAxisSize.min,
                        onPress: () => Navigator.of(context).pop(),
                        child: Text(context.l10n.cancel),
                      ),
                      FButton(
                        mainAxisSize: MainAxisSize.min,
                        onPress: () => Navigator.of(context).pop(true),
                        child: Text(action),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;

  void _selectPrompt(String prompt) {
    setState(() => _selectedPrompt = prompt);
    _inputFocus.requestFocus();
  }

  void _removePrompt() {
    setState(() => _selectedPrompt = null);
    _inputFocus.requestFocus();
  }

  Future<void> _send() async {
    final text = [
      ?_selectedPrompt,
      if (_input.text.trim().isNotEmpty) _input.text.trim(),
    ].join('\n');
    final organizer = ref.read(organizerProvider);
    if (text.isEmpty || organizer.busy || organizer.executing) return;
    final connection = ref.read(connectionSettingsProvider).asData?.value;
    if (!_assistant.hasConsent) {
      final l = context.l10n;
      if (!await _confirm(
            l.analyzeDirectory,
            organizer.includeSubdirectories
                ? l.analyzeRecursiveDetail
                : l.analyzeDirectoryDetail,
            l.startAnalysis,
          ) ||
          !mounted ||
          !identical(
            connection,
            ref.read(connectionSettingsProvider).asData?.value,
          )) {
        return;
      }
      _assistant.grantConsent();
    }
    setState(() => _selectedPrompt = null);
    _input.clear();
    _scrollToEnd();
    await _assistant.send(text);
    _scrollToEnd();
  }

  Future<void> _execute() async {
    final l = context.l10n;
    final connection = ref.read(connectionSettingsProvider).asData?.value;
    final folders = plannedFolders(ref.read(organizerProvider).plan).isNotEmpty;
    if (!await _confirm(
          l.executeRenames,
          folders ? l.executeOrganizeDetail : l.executeRenamesDetail,
          l.startExecution,
        ) ||
        !mounted ||
        !identical(
          connection,
          ref.read(connectionSettingsProvider).asData?.value,
        )) {
      return;
    }
    await _assistant.execute();
    _scrollToEnd();
  }

  Future<void> _showPlanSheet() => showFSheet<void>(
    context: context,
    side: .btt,
    useSafeArea: true,
    mainAxisMaxRatio: .9,
    builder: (context) => ColoredBox(
      color: context.theme.colors.background,
      child: _PlanPanel(
        onExecute: () async {
          Navigator.of(context).pop();
          await _execute();
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(assistantProvider.select((state) => state.messages.length), (
      previous,
      next,
    ) {
      if ((previous ?? 0) < next) _scrollToEnd();
    });
    final settings = ref.watch(connectionSettingsProvider);
    final config = settings.asData?.value;
    if (config == null && settings.isLoading) {
      return const PageContent(children: [LoadingNotice()]);
    }
    if (config == null || config.webdavUrl.isEmpty) {
      return PageContent(
        children: [
          EmptyNotice(
            context.l10n.noConnectionConfigured,
            icon: FLucideIcons.hardDrive,
            child: FButton(
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.settings2),
              onPress: () => context.go(SettingsTab.webdav.location),
              child: Text(context.l10n.configureConnection),
            ),
          ),
        ],
      );
    }
    final organizer = ref.watch(organizerProvider);
    final assistant = ref.watch(assistantProvider);
    final padding = PageContent.paddingOf(context);
    return ColoredBox(
      color: context.theme.colors.background,
      child: LayoutBuilder(
        builder: (context, box) {
          final split = box.maxWidth >= _splitWidth;
          final conversation = _Conversation(
            organizer: organizer,
            assistant: assistant,
            scroll: _scroll,
            input: _input,
            inputFocus: _inputFocus,
            selectedPrompt: _selectedPrompt,
            onRemovePrompt: _removePrompt,
            onSend: _send,
            onPrompt: _selectPrompt,
            onStop: _assistant.stop,
            onSelectDirectory: _selectDirectory,
            onViewPlan: split ? null : _showPlanSheet,
          );
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: PageContent.maxWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
                child: split
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: conversation),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 4,
                            child: FCard(
                              child: _PlanPanel(onExecute: _execute),
                            ),
                          ),
                        ],
                      )
                    : conversation,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Conversation extends ConsumerWidget {
  const _Conversation({
    required this.organizer,
    required this.assistant,
    required this.scroll,
    required this.input,
    required this.inputFocus,
    required this.selectedPrompt,
    required this.onRemovePrompt,
    required this.onSend,
    required this.onPrompt,
    required this.onStop,
    required this.onSelectDirectory,
    required this.onViewPlan,
  });

  final OrganizerState organizer;
  final AssistantState assistant;
  final ScrollController scroll;
  final TextEditingController input;
  final FocusNode inputFocus;
  final String? selectedPrompt;
  final VoidCallback onRemovePrompt;
  final Future<void> Function() onSend;
  final ValueChanged<String> onPrompt;
  final VoidCallback onStop;
  final VoidCallback onSelectDirectory;
  final VoidCallback? onViewPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = context.theme;
    final locked = organizer.busy || organizer.executing;
    final directory = organizer.directory;
    final latestPlan = assistant.messages
        .whereType<AssistantReply>()
        .where((reply) => reply.planVersion != null)
        .lastOrNull
        ?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LayoutBuilder(
            key: const ValueKey('assistant-toolbar'),
            builder: (context, box) {
              final narrow = box.maxWidth < 480;
              final checkboxStyle = theme.typography.body.sm;
              final labelPainter = TextPainter(
                text: TextSpan(
                  text: l.includeSubdirectories,
                  style: checkboxStyle,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final checkboxWidth = labelPainter.width.ceilToDouble() + 40;
              labelPainter.dispose();
              return Row(
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: WebDavManager(compact: true),
                    ),
                  ),
                  if (directory.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: checkboxWidth,
                      child: FCheckbox(
                        key: const ValueKey('include-subdirectories'),
                        value: organizer.includeSubdirectories,
                        enabled: !locked,
                        label: Text(
                          l.includeSubdirectories,
                          style: checkboxStyle,
                          maxLines: 1,
                          softWrap: false,
                        ),
                        onChange: ref
                            .read(organizerProvider.notifier)
                            .setIncludeSubdirectories,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            (box.maxWidth -
                                    checkboxWidth -
                                    24 -
                                    (assistant.messages.isNotEmpty ? 48 : 0) -
                                    (narrow ? 72 : 120))
                                .clamp(0, narrow ? 112 : 180),
                      ),
                      child: FButton(
                        key: const ValueKey('assistant-directory'),
                        variant: .outline,
                        size: .sm,
                        mainAxisSize: MainAxisSize.min,
                        builder: responsiveButtonContent,
                        semanticsLabel: displayDavPath(directory),
                        prefix: const Icon(FLucideIcons.folderOpen),
                        onPress: locked ? null : onSelectDirectory,
                        child: Text(
                          _directoryName(directory, l.rootDirectory),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  if (assistant.messages.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    FTooltip(
                      tipBuilder: (_, _) => Text(l.assistantNewConversation),
                      child: FButton.icon(
                        key: const ValueKey('assistant-reset'),
                        variant: .ghost,
                        size: .sm,
                        semanticsLabel: l.assistantNewConversation,
                        onPress: locked
                            ? null
                            : ref.read(assistantProvider.notifier).reset,
                        child: const Icon(FLucideIcons.squarePen),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        Expanded(
          child: directory.isEmpty
              ? EmptyState(
                  l.openSeriesDirectory,
                  icon: FLucideIcons.folderOpen,
                  child: FButton(
                    variant: .outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: locked ? null : onSelectDirectory,
                    child: Text(l.selectDirectory),
                  ),
                )
              : assistant.messages.isEmpty
              ? _Welcome(
                  enabled: !locked && organizer.entries.isNotEmpty,
                  onPrompt: onPrompt,
                )
              : ListView.builder(
                  key: const ValueKey('assistant-messages'),
                  controller: scroll,
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: assistant.messages.length,
                  itemBuilder: (context, index) {
                    final message = assistant.messages[index];
                    return Padding(
                      key: ValueKey('assistant-message-${message.id}'),
                      padding: const EdgeInsets.only(bottom: 14),
                      child: switch (message) {
                        AssistantUserMessage() => _UserBubble(message),
                        AssistantRun() => _RunCard(message),
                        AssistantReply() => _ReplyCard(
                          message,
                          current: message.id == latestPlan,
                          onViewPlan: onViewPlan,
                        ),
                      },
                    );
                  },
                ),
        ),
        if (directory.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (organizer.analyzing && organizer.progress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.analysisBatchProgress(organizer.progress),
                style: theme.typography.body.sm,
              ),
            ),
          _Composer(
            controller: input,
            focusNode: inputFocus,
            selectedPrompt: selectedPrompt,
            onRemovePrompt: onRemovePrompt,
            analyzing: organizer.analyzing,
            enabled:
                !locked &&
                organizer.entries.isNotEmpty &&
                (selectedPrompt != null || input.text.trim().isNotEmpty),
            readOnly: locked,
            onSend: onSend,
            onStop: onStop,
          ),
          if (organizer.executing) ...[
            const SizedBox(height: 8),
            _ExecutionProgress(progress: organizer.progress),
          ],
          if (!organizer.analyzing &&
              !organizer.executing &&
              organizer.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.openNonemptyDirectory,
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

String _directoryName(String directory, String root) {
  final segments = directory.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? root : Uri.decodeComponent(segments.last);
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.enabled, required this.onPrompt});

  final bool enabled;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final prompts = [
      (FLucideIcons.sparkles, l.assistantPromptOrganize),
      (FLucideIcons.folderTree, l.assistantPromptFolders),
      (FLucideIcons.tv, l.assistantPromptSeriesOnly),
      (FLucideIcons.film, l.assistantPromptMoviesOnly),
    ];
    return Center(
      child: SingleChildScrollView(
        primary: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                FLucideIcons.botMessageSquare,
                size: 32,
                color: theme.colors.mutedForeground,
              ),
              const SizedBox(height: 12),
              Text(
                l.assistantEmptyTitle,
                textAlign: TextAlign.center,
                style: theme.typography.body.lg,
              ),
              const SizedBox(height: 20),
              for (final (icon, text) in prompts) ...[
                FButton(
                  key: ValueKey('assistant-prompt-$text'),
                  variant: .outline,
                  prefix: Icon(icon),
                  onPress: enabled ? () => onPrompt(text) : null,
                  child: Flexible(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.message);
  final AssistantUserMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colors.primary,
            borderRadius: theme.style.borderRadius.lg,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              message.text,
              style: theme.typography.body.sm.copyWith(
                color: theme.colors.primaryForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantRow extends StatelessWidget {
  const _AssistantRow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: context.theme.colors.secondary,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 28,
          child: Icon(
            FLucideIcons.sparkles,
            size: 14,
            color: context.theme.colors.secondaryForeground,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: child),
    ],
  );
}

class _RunCard extends StatefulWidget {
  const _RunCard(this.run);
  final AssistantRun run;

  @override
  State<_RunCard> createState() => _RunCardState();
}

class _RunCardState extends State<_RunCard> {
  bool? _expanded;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final run = widget.run;
    final expanded = _expanded ?? run.running;
    final seconds = run.finishedAt?.difference(run.startedAt).inSeconds;
    final (icon, label, tone) = switch (run.status) {
      AssistantRunStatus.running => (null, l.runWorking, null),
      AssistantRunStatus.succeeded => (
        FLucideIcons.circleCheck,
        l.runDone(run.lookups),
        StatusTone.success,
      ),
      AssistantRunStatus.failed => (
        FLucideIcons.circleX,
        l.runFailed,
        StatusTone.error,
      ),
      AssistantRunStatus.stopped => (
        FLucideIcons.circleSlash,
        l.runStopped,
        StatusTone.warning,
      ),
    };
    final usage = run.usage;
    final cost = usage == null ? null : run.pricing?.estimate(usage);
    final meta = [
      if (seconds != null) l.runSeconds(seconds),
      if (usage != null && usage.responses > 0 && !usage.missingUsage)
        '${usage.inputTokens + usage.outputTokens} Tok',
      if (cost != null) '\$${cost.toStringAsFixed(4)}',
    ].join(' · ');
    return _AssistantRow(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colors.border),
          borderRadius: theme.style.borderRadius.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTappable(
              key: ValueKey('assistant-run-${run.id}'),
              semanticsLabel: expanded ? l.hideActivity : l.showActivity,
              onPress: () => setState(() => _expanded = !expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    if (icon == null)
                      const FCircularProgress(size: .sm)
                    else
                      Icon(icon, size: 16, color: _toneColor(context, tone!)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.typography.body.sm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        meta,
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        FLucideIcons.chevronDown,
                        size: 16,
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded && run.activities.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final activity in run.activities)
                            _ActivityRow(activity),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

Color _toneColor(BuildContext context, StatusTone tone) {
  final dark = context.theme.colors.brightness == Brightness.dark;
  return switch (tone) {
    StatusTone.success => Color(dark ? 0xFF4ADE80 : 0xFF15803D),
    StatusTone.error => context.theme.colors.destructive,
    StatusTone.warning => Color(dark ? 0xFFFBBF24 : 0xFFB45309),
    StatusTone.info => Color(dark ? 0xFF60A5FA : 0xFF1D4ED8),
  };
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.activity);
  final AgentActivity activity;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final title = switch (activity.kind) {
      AgentActivityKind.scan => l.activityScan,
      AgentActivityKind.model => l.activityModel(activity.number ?? 1),
      AgentActivityKind.searchMovie =>
        activity.number == null
            ? l.activitySearchMovie(activity.subject ?? '')
            : l.activitySearchMovieYear(
                activity.subject ?? '',
                activity.number!,
              ),
      AgentActivityKind.getMovie =>
        activity.title == null
            ? l.activityGetMovie
            : l.activityMovieVerified(activity.title!),
      AgentActivityKind.searchTv => l.activitySearchTv(activity.subject ?? ''),
      AgentActivityKind.getSeason =>
        activity.subject == null
            ? l.activitySeason(activity.number ?? 0)
            : l.activitySeasonOf(activity.subject!, activity.number ?? 0),
      AgentActivityKind.listDirectory => l.activityListDirectory,
    };
    final count = activity.count;
    final result = switch (activity.status) {
      AgentActivityStatus.failed => localizeRuntimeMessage(
        l,
        activity.error ?? '',
      ),
      AgentActivityStatus.stopped => l.activityStopped,
      AgentActivityStatus.running => '',
      AgentActivityStatus.succeeded => switch (activity.kind) {
        AgentActivityKind.scan || AgentActivityKind.listDirectory =>
          count == null ? '' : l.activityEntries(count),
        AgentActivityKind.searchMovie || AgentActivityKind.searchTv =>
          count == null ? '' : l.activityCandidates(count),
        AgentActivityKind.getSeason =>
          count == null ? '' : l.activityEpisodes(count),
        AgentActivityKind.getMovie => activity.date ?? '',
        AgentActivityKind.model => '',
      },
    };
    final icon = switch (activity.kind) {
      AgentActivityKind.scan ||
      AgentActivityKind.listDirectory => FLucideIcons.folderSearch,
      AgentActivityKind.model => FLucideIcons.sparkles,
      AgentActivityKind.searchMovie ||
      AgentActivityKind.getMovie => FLucideIcons.film,
      AgentActivityKind.searchTv ||
      AgentActivityKind.getSeason => FLucideIcons.tv,
    };
    final muted = theme.colors.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 18,
            child: switch (activity.status) {
              AgentActivityStatus.running => const Center(
                child: FCircularProgress(size: .xs),
              ),
              AgentActivityStatus.succeeded => Icon(
                FLucideIcons.check,
                size: 14,
                color: _toneColor(context, StatusTone.success),
              ),
              AgentActivityStatus.failed => Icon(
                FLucideIcons.x,
                size: 14,
                color: theme.colors.destructive,
              ),
              AgentActivityStatus.stopped => Icon(
                FLucideIcons.minus,
                size: 14,
                color: muted,
              ),
            },
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.xs.copyWith(
                color: activity.status == AgentActivityStatus.running
                    ? theme.colors.foreground
                    : muted,
              ),
            ),
          ),
          if (result.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                result,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.typography.body.xs.copyWith(
                  color: activity.status == AgentActivityStatus.failed
                      ? theme.colors.destructive
                      : muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard(
    this.reply, {
    required this.current,
    required this.onViewPlan,
  });

  final AssistantReply reply;
  final bool current;
  final VoidCallback? onViewPlan;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final text = switch (reply.kind) {
      AssistantReplyKind.plan =>
        reply.revised ? l.replyPlanRevised : l.replyPlan,
      AssistantReplyKind.layout => l.replyLayout,
      _ => localizeRuntimeMessage(l, reply.detail),
    };
    final summary = reply.summary;
    final error = reply.kind == AssistantReplyKind.failed;
    return _AssistantRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: theme.typography.body.sm.copyWith(
                color: error ? theme.colors.destructive : null,
              ),
            ),
          ),
          if (summary != null && reply.planVersion != null) ...[
            const SizedBox(height: 10),
            _PlanSummaryCard(
              key: ValueKey('assistant-plan-${reply.planVersion}'),
              version: reply.planVersion!,
              summary: summary,
              current: current,
              remaining: reply.kind == AssistantReplyKind.executed,
              onView: current ? onViewPlan : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.version,
    required this.summary,
    required this.current,
    required this.remaining,
    required this.onView,
    super.key,
  });

  final int version;
  final PlanSummary summary;
  final bool current, remaining;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final stats = [
      if (summary.movies > 0) (FLucideIcons.film, l.planMovies(summary.movies)),
      if (summary.series > 0) (FLucideIcons.tv, l.planSeries(summary.series)),
      if (remaining)
        (
          FLucideIcons.circleAlert,
          l.planRemaining(summary.changes + summary.unchanged),
        )
      else ...[
        (FLucideIcons.squarePen, l.planChanges(summary.changes)),
        if (summary.folders > 0)
          (FLucideIcons.folderPlus, l.planFolders(summary.folders)),
        if (summary.unchanged > 0)
          (FLucideIcons.circleCheck, l.planUnchanged(summary.unchanged)),
      ],
    ];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: current ? 1 : .6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colors.secondary.withValues(alpha: .5),
          border: Border.all(color: theme.colors.border),
          borderRadius: theme.style.borderRadius.lg,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    FLucideIcons.listChecks,
                    size: 16,
                    color: theme.colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.planVersion(version),
                      style: theme.typography.body.sm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!current)
                    FBadge(variant: .outline, child: Text(l.planSuperseded)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  for (final (icon, label) in stats)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 13,
                          color: theme.colors.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: theme.typography.body.xs.copyWith(
                            color: theme.colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (onView != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FButton(
                    key: const ValueKey('assistant-view-plan'),
                    variant: .outline,
                    size: .sm,
                    mainAxisSize: MainAxisSize.min,
                    suffix: const Icon(FLucideIcons.arrowRight),
                    onPress: onView,
                    child: Text(l.viewChanges),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.selectedPrompt,
    required this.onRemovePrompt,
    required this.analyzing,
    required this.enabled,
    required this.readOnly,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? selectedPrompt;
  final VoidCallback onRemovePrompt;
  final bool analyzing, enabled, readOnly;
  final Future<void> Function() onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            !readOnly &&
            selectedPrompt != null &&
            controller.text.isEmpty &&
            !controller.value.composing.isValid) {
          onRemovePrompt();
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.enter ||
            HardwareKeyboard.instance.isShiftPressed ||
            controller.value.composing.isValid) {
          return KeyEventResult.ignored;
        }
        if (enabled) onSend();
        return KeyEventResult.handled;
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => FTextField(
                key: const ValueKey('assistant-input'),
                style: .delta(constraints: BoxConstraints(minHeight: 44)),
                control: .managed(controller: controller),
                focusNode: focusNode,
                hint: l.assistantInputHint,
                readOnly: readOnly,
                textAlignVertical: TextAlignVertical.center,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                prefixBuilder: selectedPrompt == null
                    ? (context, style, variants) =>
                          const SizedBox(width: 10, height: 44)
                    : (context, style, variants) => Padding(
                        padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.65,
                          ),
                          child: FBadge(
                            key: const ValueKey('assistant-prompt-tag'),
                            variant: .secondary,
                            style: .delta(
                              padding: .value(EdgeInsets.fromLTRB(8, 2, 2, 2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    selectedPrompt!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                FButton.icon(
                                  key: const ValueKey(
                                    'assistant-remove-prompt',
                                  ),
                                  variant: .ghost,
                                  size: .sm,
                                  style: .delta(
                                    iconContentStyle: .delta(
                                      constraints: BoxConstraints.tightFor(
                                        width: 24,
                                        height: 24,
                                      ),
                                      padding: .value(EdgeInsets.all(5)),
                                    ),
                                  ),
                                  semanticsLabel: l.close,
                                  onPress: readOnly ? null : onRemovePrompt,
                                  child: const Icon(FLucideIcons.x, size: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (analyzing)
            FTooltip(
              tipBuilder: (_, _) => Text(l.assistantStop),
              child: FButton.icon(
                key: const ValueKey('assistant-stop'),
                style: .delta(
                  iconContentStyle: .delta(
                    constraints: BoxConstraints.tightFor(width: 44, height: 44),
                  ),
                ),
                variant: .outline,
                semanticsLabel: l.assistantStop,
                onPress: onStop,
                child: const Icon(FLucideIcons.square),
              ),
            )
          else
            FTooltip(
              tipBuilder: (_, _) => Text(l.assistantSend),
              child: FButton.icon(
                key: const ValueKey('assistant-send'),
                style: .delta(
                  iconContentStyle: .delta(
                    constraints: BoxConstraints.tightFor(width: 44, height: 44),
                  ),
                ),
                semanticsLabel: l.assistantSend,
                onPress: enabled ? onSend : null,
                child: const Icon(FLucideIcons.sendHorizontal),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExecutionProgress extends StatelessWidget {
  const _ExecutionProgress({required this.progress});
  final String progress;

  @override
  Widget build(BuildContext context) {
    final parts = progress.split('/');
    double? value;
    if (parts.length == 2) {
      final done = int.tryParse(parts[0].trim());
      final total = int.tryParse(parts[1].trim());
      if (done != null && total != null && total > 0) value = done / total;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.renaming,
                style: context.theme.typography.body.xs,
              ),
            ),
            Text(
              localizeRuntimeMessage(context.l10n, progress),
              style: context.theme.typography.body.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        value == null ? const FProgress() : FDeterminateProgress(value: value),
      ],
    );
  }
}

class _PlanPanel extends ConsumerWidget {
  const _PlanPanel({required this.onExecute});
  final Future<void> Function() onExecute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = context.theme;
    final organizer = ref.watch(organizerProvider);
    final version = ref.watch(
      assistantProvider.select((state) => state.planVersion),
    );
    final layout = ref.watch(assistantProvider.select((state) => state.layout));
    final locked = organizer.busy || organizer.executing;
    final plan = organizer.plan;
    final entries = organizer.analysisEntries.isEmpty
        ? organizer.entries
        : organizer.analysisEntries;
    final controller = ref.read(organizerProvider.notifier);
    final error = plan.isEmpty ? null : validatePlan(plan, entries);
    final selected = plan.where((item) => item.enabled).length;
    final changes = plan
        .where((item) => item.enabled && item.source != item.target)
        .length;
    final canExecute = !locked && error == null && changes > 0;

    final tree = PlanTree.build(organizer.directory, plan, entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Row(
            children: [
              Icon(
                FLucideIcons.listChecks,
                size: 18,
                color: theme.colors.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      version > 0 && plan.isNotEmpty
                          ? l.planVersion(version)
                          : l.planPanelTitle,
                      style: theme.typography.body.md.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (plan.isNotEmpty)
                      Text(
                        l.selectedChanges(selected, plan.length, changes),
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              if (plan.isNotEmpty)
                FButton(
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: locked
                      ? null
                      : () => controller.setAllEnabled(selected != plan.length),
                  child: Text(
                    selected == plan.length ? l.deselectAll : l.selectAll,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: theme.colors.border)),
        if (plan.isNotEmpty)
          _LayoutBar(
            layout: layout,
            folders: tree.newDirectories.length,
            locked: locked,
            onChange: ref.read(assistantProvider.notifier).updateLayout,
          ),
        Expanded(
          child: plan.isEmpty
              ? EmptyState(l.noPlanYet, icon: FLucideIcons.listChecks)
              : PlanTreeView(
                  tree: tree,
                  entries: entries,
                  disabled: locked,
                  onName: (index, name) => controller.edit(index, name: name),
                  onEnabled: (index, enabled) =>
                      controller.edit(index, enabled: enabled),
                ),
        ),
        if (plan.isNotEmpty) ...[
          SizedBox(height: 1, child: ColoredBox(color: theme.colors.border)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  FAlert(
                    variant: .destructive,
                    icon: const Icon(FLucideIcons.circleAlert),
                    title: Text(l.cannotExecute),
                    subtitle: Text(localizeRuntimeMessage(l, error)),
                  ),
                  const SizedBox(height: 10),
                ],
                FButton(
                  key: const ValueKey('assistant-execute'),
                  prefix: const Icon(FLucideIcons.play),
                  onPress: canExecute ? onExecute : null,
                  child: Text(l.confirmAndExecute),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LayoutBar extends StatelessWidget {
  const _LayoutBar({
    required this.layout,
    required this.folders,
    required this.locked,
    required this.onChange,
  });

  final FolderLayout layout;
  final int folders;
  final bool locked;
  final void Function(FolderLayout Function(FolderLayout layout) update)
  onChange;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    Widget option(
      String key,
      String label,
      bool value,
      FolderLayout Function(FolderLayout layout) toggle,
    ) => FCheckbox(
      key: ValueKey('folder-layout-$key'),
      label: Text(label),
      value: value,
      enabled: !locked,
      onChange: (_) => onChange(toggle),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colors.secondary.withValues(alpha: .4),
        border: Border(bottom: BorderSide(color: theme.colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  FLucideIcons.folderTree,
                  size: 15,
                  color: theme.colors.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.folderLayout,
                    style: theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (folders > 0)
                  Text(
                    l.planFolders(folders),
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                option(
                  'movies',
                  l.folderMovies,
                  layout.movieFolders,
                  (current) =>
                      current.copyWith(movieFolders: !current.movieFolders),
                ),
                option(
                  'series',
                  l.folderSeries,
                  layout.seriesFolders,
                  (current) =>
                      current.copyWith(seriesFolders: !current.seriesFolders),
                ),
                option(
                  'seasons',
                  l.folderSeasons,
                  layout.seasonFolders,
                  (current) =>
                      current.copyWith(seasonFolders: !current.seasonFolders),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
