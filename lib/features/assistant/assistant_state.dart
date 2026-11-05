import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../organizer/ai/agent_activity.dart';
import '../organizer/ai/ai_usage.dart';
import '../organizer/ai/folder_layout.dart';
import '../organizer/connections/connection_settings.dart';
import '../organizer/organizer_state.dart';
import '../organizer/rename_plan.dart';

enum AssistantRunStatus { running, succeeded, failed, stopped }

enum AssistantReplyKind { plan, layout, empty, failed, stopped, executed }

sealed class AssistantMessage {
  const AssistantMessage(this.id);
  final int id;
}

class AssistantUserMessage extends AssistantMessage {
  const AssistantUserMessage(super.id, this.text);
  final String text;
}

/// The real steps taken for one request, updated while they happen.
class AssistantRun extends AssistantMessage {
  const AssistantRun(
    super.id, {
    required this.startedAt,
    this.activities = const [],
    this.status = AssistantRunStatus.running,
    this.finishedAt,
    this.usage,
    this.pricing,
  });

  final List<AgentActivity> activities;
  final AssistantRunStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final AiUsage? usage;
  final ModelPricing? pricing;

  bool get running => status == AssistantRunStatus.running;

  int get modelRounds =>
      activities.where((a) => a.kind == AgentActivityKind.model).length;

  int get lookups => activities
      .where(
        (a) =>
            a.kind != AgentActivityKind.model &&
            a.kind != AgentActivityKind.scan,
      )
      .length;

  AssistantRun withActivity(AgentActivity activity) {
    final index = activities.indexWhere((a) => a.key == activity.key);
    return _copy(
      activities: index < 0
          ? [...activities, activity]
          : [
              for (final (i, item) in activities.indexed)
                i == index ? activity : item,
            ],
    );
  }

  AssistantRun finish(
    AssistantRunStatus status, {
    required DateTime at,
    AiUsage? usage,
    ModelPricing? pricing,
  }) => _copy(
    status: status,
    finishedAt: at,
    usage: usage,
    pricing: pricing,
    activities: [
      for (final activity in activities)
        activity.status == AgentActivityStatus.running
            ? activity.copyWith(
                status: status == AssistantRunStatus.succeeded
                    ? AgentActivityStatus.succeeded
                    : AgentActivityStatus.stopped,
              )
            : activity,
    ],
  );

  AssistantRun _copy({
    List<AgentActivity>? activities,
    AssistantRunStatus? status,
    DateTime? finishedAt,
    AiUsage? usage,
    ModelPricing? pricing,
  }) => AssistantRun(
    id,
    startedAt: startedAt,
    activities: activities ?? this.activities,
    status: status ?? this.status,
    finishedAt: finishedAt ?? this.finishedAt,
    usage: usage ?? this.usage,
    pricing: pricing ?? this.pricing,
  );
}

class PlanSummary {
  const PlanSummary({
    required this.movies,
    required this.series,
    required this.changes,
    required this.unchanged,
    this.folders = 0,
  });

  factory PlanSummary.of(List<RenameItem> plan) => PlanSummary(
    movies: {
      for (final item in plan)
        if (item.tmdbMediaType == TmdbMediaType.movie) item.tmdbId,
    }.length,
    series: {
      for (final item in plan)
        if (item.tmdbMediaType == TmdbMediaType.tv) item.tmdbId,
    }.length,
    changes: plan.where((item) => item.source != item.target).length,
    unchanged: plan.where((item) => item.source == item.target).length,
    folders: plannedFolders(plan).length,
  );

  final int movies, series, changes, unchanged, folders;
}

class AssistantReply extends AssistantMessage {
  const AssistantReply(
    super.id,
    this.kind, {
    this.detail = '',
    this.planVersion,
    this.summary,
    this.revised = false,
  });

  final AssistantReplyKind kind;

  /// A runtime message produced by the organizer, localized when displayed.
  final String detail;
  final int? planVersion;
  final PlanSummary? summary;

  /// Whether this plan replaces an earlier one from the same conversation.
  final bool revised;
}

class AssistantState {
  const AssistantState({
    this.messages = const [],
    this.planVersion = 0,
    this.consentScope,
    this.layout = FolderLayout.full,
  });

  final List<AssistantMessage> messages;
  final int planVersion;

  /// The connection and directory the user agreed to send to the AI service.
  final String? consentScope;

  /// How the plan groups files into folders.
  final FolderLayout layout;

  AssistantState copyWith({
    List<AssistantMessage>? messages,
    int? planVersion,
    String? consentScope,
    FolderLayout? layout,
  }) => AssistantState(
    messages: messages ?? this.messages,
    planVersion: planVersion ?? this.planVersion,
    consentScope: consentScope ?? this.consentScope,
    layout: layout ?? this.layout,
  );
}

final assistantProvider = NotifierProvider<AssistantController, AssistantState>(
  AssistantController.new,
);

class AssistantController extends Notifier<AssistantState> {
  static const _maxInstructionLength = 2000;
  int _nextId = 0;

  @override
  AssistantState build() {
    ref.listen(organizerProvider.select((state) => state.directory), (
      previous,
      next,
    ) {
      if (previous != next) state = AssistantState(layout: state.layout);
    });
    return const AssistantState();
  }

  OrganizerController get _organizer => ref.read(organizerProvider.notifier);

  String? get scope {
    final directory = ref.read(organizerProvider).directory;
    if (directory.isEmpty) return null;
    final connection = ref.read(connectionSettingsProvider).asData?.value;
    return '${connection?.connectionId ?? connection?.webdavUrl}|$directory|${ref.read(organizerProvider).includeSubdirectories}';
  }

  bool get hasConsent => scope != null && state.consentScope == scope;

  void grantConsent() {
    final current = scope;
    if (current != null) state = state.copyWith(consentScope: current);
  }

  void reset() {
    final organizer = ref.read(organizerProvider);
    if (organizer.busy || organizer.executing) return;
    _organizer.clearPlan();
    state = AssistantState(
      consentScope: state.consentScope,
      layout: state.layout,
    );
  }

  void updateLayout(FolderLayout Function(FolderLayout layout) update) =>
      setLayout(update(state.layout));

  void setLayout(FolderLayout layout) {
    final organizer = ref.read(organizerProvider);
    if (organizer.busy || organizer.executing || layout == state.layout) {
      return;
    }
    state = state.copyWith(layout: layout);
    if (organizer.plan.isEmpty) return;
    _organizer.applyLayout(layout);
    state = state.copyWith(planVersion: state.planVersion + 1);
    _append(
      AssistantReply(
        _id(),
        AssistantReplyKind.layout,
        planVersion: state.planVersion,
        summary: PlanSummary.of(ref.read(organizerProvider).plan),
        revised: true,
      ),
    );
  }

  int _id() => _nextId++;

  void _replace(AssistantMessage message) {
    state = state.copyWith(
      messages: [
        for (final item in state.messages)
          item.id == message.id ? message : item,
      ],
    );
  }

  void _append(AssistantMessage message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// All requirements of this conversation, so later turns refine earlier ones.
  String _instruction() {
    final requirements = [
      for (final message in state.messages)
        if (message is AssistantUserMessage) message.text,
    ];
    var text = requirements.join('\n');
    while (text.length > _maxInstructionLength && requirements.length > 1) {
      requirements.removeAt(0);
      text = requirements.join('\n');
    }
    return text.length > _maxInstructionLength
        ? text.substring(text.length - _maxInstructionLength)
        : text;
  }

  Future<void> send(String text) async {
    final message = text.trim();
    final organizer = ref.read(organizerProvider);
    if (message.isEmpty ||
        organizer.busy ||
        organizer.executing ||
        organizer.directory.isEmpty ||
        !hasConsent) {
      return;
    }
    final revising = state.messages.any(
      (item) => item is AssistantReply && item.kind == AssistantReplyKind.plan,
    );
    _append(AssistantUserMessage(_id(), message));
    var run = AssistantRun(_id(), startedAt: DateTime.now());
    _append(run);
    await _organizer.propose(
      instruction: _instruction(),
      folderLayout: state.layout,
      onActivity: (activity) {
        run = run.withActivity(activity);
        _replace(run);
      },
      onLayout: (layout) => state = state.copyWith(layout: layout),
    );
    final result = ref.read(organizerProvider);
    final (status, reply) = switch (result) {
      OrganizerState(plan: final plan) when plan.isNotEmpty => (
        AssistantRunStatus.succeeded,
        AssistantReply(
          _id(),
          AssistantReplyKind.plan,
          planVersion: state.planVersion + 1,
          summary: PlanSummary.of(plan),
          revised: revising,
        ),
      ),
      OrganizerState(message: final m) when m.startsWith('AI 建议已中断') => (
        AssistantRunStatus.stopped,
        AssistantReply(_id(), AssistantReplyKind.stopped, detail: m),
      ),
      OrganizerState(message: final m) when m.startsWith('未找到') => (
        AssistantRunStatus.succeeded,
        AssistantReply(_id(), AssistantReplyKind.empty, detail: m),
      ),
      OrganizerState(message: final m) => (
        AssistantRunStatus.failed,
        AssistantReply(_id(), AssistantReplyKind.failed, detail: m),
      ),
    };
    _replace(
      run.finish(
        status,
        at: DateTime.now(),
        usage: result.aiUsage,
        pricing: result.pricing,
      ),
    );
    if (reply.planVersion != null) {
      state = state.copyWith(planVersion: reply.planVersion);
    }
    _append(reply);
  }

  void stop() => _organizer.cancelSuggestions();

  Future<void> execute() async {
    final organizer = ref.read(organizerProvider);
    if (organizer.busy || organizer.executing || organizer.plan.isEmpty) {
      return;
    }
    await _organizer.execute();
    final result = ref.read(organizerProvider);
    if (result.message.isEmpty) return;
    _append(
      AssistantReply(
        _id(),
        AssistantReplyKind.executed,
        detail: result.message,
        summary: result.plan.isEmpty ? null : PlanSummary.of(result.plan),
        planVersion: result.plan.isEmpty ? null : state.planVersion,
      ),
    );
  }
}
