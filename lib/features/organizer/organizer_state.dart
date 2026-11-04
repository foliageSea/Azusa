import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging.dart';
import '../../core/settings/settings.dart';
import 'ai/agent.dart';
import 'ai/agent_activity.dart';
import 'ai/folder_layout.dart';
import 'ai/ai_usage.dart';
import 'ai/ai_usage_history.dart';
import 'ai/model_pricing.dart';
import 'connections/connection_settings.dart';
import 'dav/dav_paths.dart';
import 'history/execution_history.dart';
import 'connections/http_clients.dart';
import 'rename_plan.dart';
import 'ai/tmdb.dart';
import 'dav/webdav.dart';

class OrganizerState {
  const OrganizerState({
    this.directory = '',
    this.entries = const [],
    this.analysisEntries = const [],
    this.plan = const [],
    this.busy = false,
    this.executing = false,
    this.analyzing = false,
    this.progress = '',
    this.message = '',
    this.aiUsage,
    this.pricing,
  });
  final String directory, progress, message;
  final List<DavEntry> entries;
  final List<DavEntry> analysisEntries;
  final List<RenameItem> plan;
  final bool busy, executing;
  final bool analyzing;
  final AiUsage? aiUsage;
  final ModelPricing? pricing;

  bool get hasError =>
      RegExp('失败|停止|无效|错误|未找到|不能|冲突|已变化|已存在').hasMatch(message);

  OrganizerState copyWith({
    String? directory,
    String? progress,
    String? message,
    List<DavEntry>? entries,
    List<DavEntry>? analysisEntries,
    List<RenameItem>? plan,
    bool? busy,
    bool? executing,
    bool? analyzing,
    AiUsage? aiUsage,
    ModelPricing? pricing,
    bool clearAnalysis = false,
  }) => OrganizerState(
    directory: directory ?? this.directory,
    entries: entries ?? this.entries,
    analysisEntries: clearAnalysis
        ? const []
        : analysisEntries ?? this.analysisEntries,
    plan: plan ?? this.plan,
    busy: busy ?? this.busy,
    executing: executing ?? this.executing,
    analyzing: analyzing ?? this.analyzing,
    progress: progress ?? this.progress,
    message: message ?? this.message,
    aiUsage: clearAnalysis ? null : aiUsage ?? this.aiUsage,
    pricing: clearAnalysis ? null : pricing ?? this.pricing,
  );
}

final organizerProvider = NotifierProvider<OrganizerController, OrganizerState>(
  OrganizerController.new,
);
final webDavFactoryProvider =
    Provider<WebDavClient Function(ConnectionSettings)>(
      (ref) => WebDavClient.new,
    );
final modelPricingLookupProvider =
    Provider<Future<ModelPricing?> Function(ConnectionSettings)>(
      (ref) => ModelPricingCatalog.lookup,
    );
final executionHistoryProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(executionHistoryRepositoryProvider).load(),
);

class OrganizerController extends Notifier<OrganizerState> with LoggingMixin {
  int _analysisGeneration = 0;
  void Function()? _cancelAnalysis;

  void cancelSuggestions() => _cancelAnalysis?.call();

  @override
  OrganizerState build() => const OrganizerState();

  ConnectionSettings get config =>
      ref.read(connectionSettingsProvider).requireValue;
  WebDavClient client() => ref.read(webDavFactoryProvider)(config);

  void beginConnectionChange() {
    if (state.busy || state.executing) throw StateError('请等待当前操作完成');
    state = state.copyWith(busy: true);
  }

  void endConnectionChange({bool reset = false}) {
    if (reset) {
      _analysisGeneration++;
      state = const OrganizerState();
    } else {
      state = state.copyWith(busy: false);
    }
  }

  void disconnect() {
    if (state.busy || state.executing) return;
    _analysisGeneration++;
    state = const OrganizerState();
  }

  Future<void> open(String? path) async {
    if (state.busy || state.executing) return;
    _analysisGeneration++;
    state = state.copyWith(busy: true, message: '');
    WebDavClient? dav;
    try {
      dav = client();
      final directory = dav.normalize(
        path == null
            ? dav.root
            : path.endsWith('/')
            ? path
            : '$path/',
      );
      final entries = await dav.list(directory);
      state = state.copyWith(
        directory: directory,
        clearAnalysis: true,
        entries: entries,
        plan: [],
        message: '',
      );
    } catch (e) {
      state = state.copyWith(message: '读取目录失败：${serviceError(e)}');
    } finally {
      dav?.close();
      state = state.copyWith(busy: false);
    }
  }

  Future<void> propose({
    String instruction = '',
    FolderLayout? folderLayout,
    void Function(AgentActivity activity)? onActivity,
    void Function(FolderLayout layout)? onLayout,
  }) async {
    if (state.busy || state.executing || state.directory.isEmpty) return;
    final generation = ++_analysisGeneration;
    final startedAt = DateTime.now();
    final directory = state.directory;
    String? model;
    var succeeded = false;
    var cancelled = false;
    final cancellation = Completer<void>();
    Future<T> interruptible<T>(Future<T> future) => Future.any([
      future,
      cancellation.future.then<T>((_) => throw StateError('AI 建议已中断')),
    ]);
    state = state.copyWith(
      busy: true,
      analyzing: true,
      plan: [],
      message: '正在查询影视资料…',
      clearAnalysis: true,
    );
    Future<ModelPricing?>? pricing;
    WebDavClient? dav;
    TmdbClient? tmdb;
    RenameAgent? agent;
    void cancel() {
      if (cancelled) return;
      cancelled = true;
      succeeded = false;
      _analysisGeneration++;
      state = state.copyWith(plan: [], message: 'AI 建议已中断');
      cancellation.complete();
      agent?.close();
      tmdb?.close();
      dav?.close();
    }

    _cancelAnalysis = cancel;
    try {
      final settings = config;
      model = settings.model;
      pricing = ref.read(modelPricingLookupProvider)(settings).then((value) {
        if (generation == _analysisGeneration) {
          state = state.copyWith(pricing: value);
        }
        return value;
      });
      state = state.copyWith(aiUsage: const AiUsage());
      dav = client();
      tmdb = TmdbClient(
        settings,
        namingLanguage: ref.read(settingsProvider).namingLanguage,
      );
      agent = RenameAgent(
        settings,
        dav,
        tmdb,
        namingFormat: ref.read(settingsProvider).namingFormat,
      );
      var scan = AgentActivity(
        key: 'scan',
        kind: AgentActivityKind.scan,
        subject: displayDavPath(state.directory),
      );
      onActivity?.call(scan);
      final List<DavEntry> analysisEntries;
      final List<DavEntry> fresh;
      try {
        fresh = await interruptible(dav.list(state.directory));
        analysisEntries = <DavEntry>[...fresh];
        for (final folder in fresh.where((entry) => entry.directory)) {
          analysisEntries.addAll(await interruptible(dav.list(folder.path)));
        }
      } catch (error) {
        if (!cancelled) onActivity?.call(scan.fail(serviceError(error)));
        rethrow;
      }
      scan = scan.succeed(count: analysisEntries.length);
      onActivity?.call(scan);
      final plan = await interruptible(
        agent.propose(
          state.directory,
          analysisEntries,
          instruction: instruction,
          folderLayout: folderLayout,
          onLayout: (layout) {
            if (!cancelled) onLayout?.call(layout);
          },
          onStatus: (message) {
            if (!cancelled) state = state.copyWith(message: message);
          },
          onUsage: (usage) {
            if (!cancelled) state = state.copyWith(aiUsage: usage);
          },
          onActivity: (activity) {
            if (!cancelled) onActivity?.call(activity);
          },
        ),
      );
      if (cancelled) return;
      succeeded = true;
      state = state.copyWith(
        entries: fresh,
        analysisEntries: analysisEntries,
        plan: plan,
        message: plan.isEmpty ? '未找到可靠的重命名建议，请补充片名和年份或剧名和季数后重试' : '建议已生成',
      );
    } catch (e) {
      state = state.copyWith(
        message: cancelled ? 'AI 建议已中断' : '生成建议失败：${serviceError(e)}',
      );
    } finally {
      agent?.close();
      tmdb?.close();
      dav?.close();
      if (pricing != null && !cancelled) {
        try {
          await interruptible(pricing);
        } catch (_) {
          if (cancelled) state = state.copyWith(message: 'AI 建议已中断', plan: []);
        }
      }
      final usage = state.aiUsage;
      if (usage != null && usage.responses > 0 && model != null) {
        try {
          await ref
              .read(aiUsageRepositoryProvider)
              .append(
                AiUsageRecord(
                  startedAt: startedAt,
                  model: model,
                  directory: directory,
                  usage: usage,
                  succeeded: succeeded,
                  estimatedCost: state.pricing?.estimate(usage),
                  priceSource: state.pricing?.source,
                ),
              );
          ref.invalidate(aiUsageHistoryProvider);
        } catch (error, stack) {
          log.warning('保存 AI 用量失败', error, stack);
          state = state.copyWith(message: '${state.message}；保存 AI 用量失败');
        }
      }
      _cancelAnalysis = null;
      state = state.copyWith(busy: false, analyzing: false);
    }
  }

  void edit(int index, {String? name, bool? enabled}) {
    if (state.executing || state.busy) return;
    final plan = List<RenameItem>.of(state.plan);
    plan[index] = plan[index].copyWith(targetName: name, enabled: enabled);
    state = state.copyWith(plan: plan);
  }

  void setAllEnabled(bool enabled) {
    if (state.executing || state.busy) return;
    state = state.copyWith(
      plan: [for (final item in state.plan) item.copyWith(enabled: enabled)],
    );
  }

  /// Re-places the current plan with [layout], keeping manual edits.
  void applyLayout(FolderLayout layout) {
    if (state.executing || state.busy || state.directory.isEmpty) return;
    state = state.copyWith(
      plan: applyFolderLayout(state.plan, state.directory, layout),
    );
  }

  Future<void> _record(String entry) async {
    await ref
        .read(executionHistoryRepositoryProvider)
        .append('${DateTime.now().toLocal()} $entry');
    ref.invalidate(executionHistoryProvider);
  }

  Future<void> renameEntry(DavEntry entry, String name) async {
    if (state.busy || state.executing || state.directory.isEmpty) return;
    final issue = fileNameError(name);
    if (issue != null) {
      state = state.copyWith(message: issue);
      return;
    }
    if (name == entry.name) return;
    if (!state.entries.any((item) => item.path == entry.path)) {
      state = state.copyWith(message: '源文件已不存在，请刷新目录核对');
      return;
    }
    final target = childDavPath(
      state.directory,
      name,
      directory: entry.directory,
    );
    if (state.entries.any(
      (item) =>
          item.path != entry.path &&
          item.name.toLowerCase() == name.toLowerCase(),
    )) {
      state = state.copyWith(message: '目标已存在：$name');
      return;
    }
    await manage('move', entry.path, target: target);
  }

  Future<void> manage(
    String action,
    String source, {
    String? target,
    Stream<List<int>>? bytes,
    int? length,
  }) async {
    if (state.busy || state.executing || state.directory.isEmpty) return;
    state = state.copyWith(busy: true, message: '');
    WebDavClient? dav;
    try {
      dav = client();
      final normalized = dav.normalize(source);
      if (normalized == dav.root) throw StateError('不能修改 WebDAV 根目录');
      await _record(
        '准备 $action ${displayDavPath(source)} ${target == null ? '' : displayDavPath(target)}',
      );
      if (action == 'delete') {
        await dav.remove(source);
      } else if (action == 'move' && target != null) {
        dav.normalize(target);
        if (source.endsWith('/') && target.startsWith(source)) {
          throw StateError('不能移动目录到自身内部');
        }
        if (await dav.stat(source) == null) throw StateError('源文件已不存在');
        if (await dav.exists(target)) throw StateError('目标已存在');
        await dav.move(source, target);
      } else if (action == 'upload' && bytes != null && length != null) {
        if (await dav.exists(source)) throw StateError('目标已存在');
        await dav.upload(source, bytes, length);
      } else if (action == 'mkdir') {
        await dav.mkdir(source);
      } else {
        throw StateError('不支持的文件操作');
      }
      await _record(
        '完成 $action ${displayDavPath(source)} ${target == null ? '' : displayDavPath(target)}',
      );
      state = state.copyWith(
        entries: await dav.list(state.directory),
        plan: [],
        message: '操作完成',
      );
    } catch (e) {
      state = state.copyWith(message: '文件操作已停止：${serviceError(e)}；请刷新目录核对结果');
    } finally {
      dav?.close();
      state = state.copyWith(busy: false);
    }
  }

  Future<bool> download(String path, String destination) async {
    if (state.busy || state.executing) return false;
    state = state.copyWith(busy: true, message: '正在下载…');
    WebDavClient? dav;
    try {
      dav = client();
      await dav.download(path, destination);
      state = state.copyWith(message: '下载完成');
      return true;
    } catch (e) {
      state = state.copyWith(message: '下载失败：${serviceError(e)}');
      return false;
    } finally {
      dav?.close();
      state = state.copyWith(busy: false);
    }
  }

  Future<void> execute() async {
    if (state.executing || state.busy) return;
    final frozen = List<RenameItem>.unmodifiable(state.plan);
    final error = validatePlan(
      frozen,
      state.analysisEntries.isEmpty ? state.entries : state.analysisEntries,
    );
    if (error != null) {
      state = state.copyWith(message: error);
      return;
    }
    state = state.copyWith(executing: true, progress: '准备执行', message: '');
    WebDavClient? dav;
    try {
      dav = client();
      final result = await RenameExecutor(dav).execute(
        frozen,
        onStarting: (item) => _record(
          '准备重命名 ${displayDavPath(item.source)} → ${displayDavPath(item.target)}',
        ),
        onCompleted: (item) => _record(
          '完成重命名 ${displayDavPath(item.source)} → ${displayDavPath(item.target)}',
        ),
        onCreatingDirectory: (path) =>
            _record('准备 mkdir ${displayDavPath(path)} '),
        onDirectoryCreated: (path) =>
            _record('完成 mkdir ${displayDavPath(path)} '),
        onProgress: (done, total) =>
            state = state.copyWith(progress: '$done / $total'),
      );
      state = state.copyWith(
        message: result.error == null
            ? '已完成 ${result.completed.length} 项'
            : '已停止：${result.error}。请核对后再次确认执行剩余项',
        plan: frozen.where((e) => !result.completed.contains(e)).toList(),
      );
      final refreshed = await dav.list(state.directory);
      final remaining = state.plan;
      final sourceDirectories = {for (final item in remaining) item.parent};
      final analysisEntries = <DavEntry>[...refreshed];
      for (final path in sourceDirectories.where(
        (path) => path != state.directory,
      )) {
        analysisEntries.addAll(await dav.list(path));
      }
      state = state.copyWith(
        entries: refreshed,
        analysisEntries: analysisEntries,
      );
    } catch (e) {
      state = state.copyWith(message: '执行已停止：${serviceError(e)}；请刷新目录核对结果');
    } finally {
      dav?.close();
      state = state.copyWith(executing: false);
    }
  }

  Future<void> createDirectory(String name) async {
    try {
      await manage(
        'mkdir',
        childDavPath(state.directory, name, directory: true),
      );
    } catch (e) {
      state = state.copyWith(message: serviceError(e));
    }
  }
}
