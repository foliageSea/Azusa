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
import 'dav/directory_scan.dart';
import 'history/execution_history.dart';
import 'connections/http_clients.dart';
import 'rename_plan.dart';
import 'ai/tmdb.dart';
import 'dav/webdav.dart';
import 'scrape/scrape_cleaner.dart';
import 'scrape/scraper.dart';

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
    this.analysisDirectory = '',
    this.message = '',
    this.aiUsage,
    this.pricing,
    this.includeSubdirectories = true,
    this.selectedDirectories = const [],
  });
  final String directory, progress, message;
  final String analysisDirectory;
  final List<DavEntry> entries;
  final List<DavEntry> analysisEntries;
  final List<RenameItem> plan;
  final bool busy, executing;
  final bool analyzing;
  final AiUsage? aiUsage;
  final ModelPricing? pricing;
  final bool includeSubdirectories;
  final List<String> selectedDirectories;

  List<String> get organizingDirectories {
    final paths = selectedDirectories.isEmpty
        ? [if (directory.isNotEmpty) directory]
        : selectedDirectories;
    return [
      for (final path in paths)
        if (!includeSubdirectories ||
            !paths.any((other) => other != path && path.startsWith(other)))
          path,
    ];
  }

  bool get hasError =>
      RegExp('失败|停止|无效|错误|未找到|不能|冲突|已变化|已存在').hasMatch(message);

  OrganizerState copyWith({
    String? directory,
    String? progress,
    String? analysisDirectory,
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
    bool? includeSubdirectories,
    List<String>? selectedDirectories,
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
    analysisDirectory: clearAnalysis
        ? ''
        : analysisDirectory ?? this.analysisDirectory,
    message: message ?? this.message,
    aiUsage: clearAnalysis ? null : aiUsage ?? this.aiUsage,
    pricing: clearAnalysis ? null : pricing ?? this.pricing,
    includeSubdirectories: includeSubdirectories ?? this.includeSubdirectories,
    selectedDirectories: selectedDirectories ?? this.selectedDirectories,
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
final renameAgentFactoryProvider =
    Provider<
      RenameAgent Function(ConnectionSettings, WebDavClient, TmdbClient)
    >(
      (ref) =>
          (settings, dav, tmdb) => RenameAgent(
            settings,
            dav,
            tmdb,
            namingFormat: ref.read(settingsProvider).namingFormat,
          ),
    );
final tmdbFactoryProvider = Provider<TmdbClient Function(ConnectionSettings)>(
  (ref) =>
      (settings) => TmdbClient(
        settings,
        namingLanguage: ref.read(settingsProvider).namingLanguage,
      ),
);
final executionHistoryProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(executionHistoryRepositoryProvider).load(),
);

class OrganizerController extends Notifier<OrganizerState> with LoggingMixin {
  int _analysisGeneration = 0;
  void Function()? _cancelAnalysis;
  bool _maintenanceCancelled = false;
  Set<String> _emptyCandidates = {};
  String? _emptyScope;

  String get _cleanupScope =>
      '${config.connectionId}|${config.webdavUrl}|${config.username}|${state.directory}';

  void cancelMaintenance() => _maintenanceCancelled = true;

  void _checkMaintenance() {
    if (_maintenanceCancelled) throw StateError('清理已中止');
  }

  Future<List<String>> scanEmptyDirectories() async {
    if (state.busy || state.executing || state.directory.isEmpty) return [];
    _emptyCandidates = {};
    _emptyScope = null;
    _maintenanceCancelled = false;
    state = state.copyWith(busy: true, message: '', progress: '');
    WebDavClient? dav;
    try {
      dav = client();
      final result = await EmptyDirectoryCleaner(dav).scan(
        state.directory,
        checkCancelled: _checkMaintenance,
        onProgress: (path) =>
            state = state.copyWith(progress: displayDavPath(path)),
      );
      _emptyCandidates = result.toSet();
      _emptyScope = _cleanupScope;
      return result;
    } catch (e) {
      state = state.copyWith(message: '扫描已停止：${serviceError(e)}');
      return [];
    } finally {
      dav?.close();
      state = state.copyWith(busy: false, progress: '');
    }
  }

  Future<void> cleanEmptyDirectories(Iterable<String> selected) async {
    if (state.busy || state.executing || _emptyScope != _cleanupScope) return;
    final paths = selected.toSet();
    if (paths.isEmpty || !paths.every(_emptyCandidates.contains)) return;
    _maintenanceCancelled = false;
    state = state.copyWith(
      busy: true,
      message: '',
      progress: '0 / ${paths.length}',
    );
    WebDavClient? dav;
    var deleted = 0;
    var skipped = 0;
    try {
      dav = client();
      await EmptyDirectoryCleaner(dav).clean(
        state.directory,
        paths,
        checkCancelled: _checkMaintenance,
        onDeleting: (path) => _record('准备 delete ${displayDavPath(path)}'),
        onDeleted: (path) => _record('完成 delete ${displayDavPath(path)}'),
        onProgress: (done, ignored) {
          deleted = done;
          skipped = ignored;
          state = state.copyWith(
            progress: '${done + ignored} / ${paths.length}',
          );
        },
      );
      state = state.copyWith(message: '清理完成：已删除 $deleted 个空目录，跳过 $skipped 个目录');
    } catch (e) {
      state = state.copyWith(
        message: '清理已停止：已删除 $deleted 个空目录，跳过 $skipped 个目录；${serviceError(e)}',
      );
    } finally {
      _emptyCandidates = {};
      _emptyScope = null;
      try {
        if (dav != null) {
          state = state.copyWith(entries: await dav.list(state.directory));
        }
      } catch (e) {
        state = state.copyWith(
          message: '${state.message}；刷新目录失败：${serviceError(e)}',
        );
      }
      dav?.close();
      state = state.copyWith(busy: false, progress: '');
    }
  }

  ScrapeScan? _scrapeScan;
  String? _scrapeScope;
  Map<String, ScrapeArtifact> _scrapeArtifacts = {};
  String? _artifactScope;
  List<String> _scrapeDirectories = const [];
  List<String> _artifactDirectories = const [];

  /// Recursive scopes are normalized and parent selections cover descendants.
  List<String> _scrapeRoots(WebDavClient dav, Iterable<String>? directories) {
    final paths =
        (directories ??
                (state.selectedDirectories.isEmpty
                    ? [state.directory]
                    : state.selectedDirectories))
            .map((path) => dav.normalize(path.endsWith('/') ? path : '$path/'))
            .toSet()
            .toList()
          ..sort();
    return List.unmodifiable([
      for (final path in paths)
        if (!paths.any((other) => other != path && path.startsWith(other)))
          path,
    ]);
  }

  void _checkScrape() {
    if (_maintenanceCancelled) throw StateError('搜刮已中止');
  }

  /// Matches videos in the selected directories, or the current folder.
  Future<ScrapeScan?> scanScrapeTargets({Iterable<String>? directories}) async {
    if (state.busy || state.executing || state.directory.isEmpty) return null;
    _scrapeScan = null;
    _scrapeScope = null;
    _scrapeDirectories = const [];
    _maintenanceCancelled = false;
    state = state.copyWith(busy: true, message: '', progress: '');
    WebDavClient? dav;
    TmdbClient? tmdb;
    try {
      final settings = config;
      if (settings.tmdbToken.isEmpty) throw StateError('请配置 TMDB Token');
      dav = client();
      tmdb = ref.read(tmdbFactoryProvider)(settings);
      final roots = _scrapeRoots(dav, directories);
      if (roots.isEmpty) return null;
      final scraper = MetadataScraper(dav, tmdb);
      final targets = <ScrapeTarget>[];
      final unmatched = <String>[];
      for (final root in roots) {
        final scan = await scraper.scan(
          root,
          checkCancelled: _checkScrape,
          onProgress: (path, _) =>
              state = state.copyWith(progress: displayDavPath(path)),
        );
        targets.addAll(scan.targets);
        unmatched.addAll(scan.unmatched);
      }
      final result = ScrapeScan(targets, unmatched);
      _scrapeDirectories = roots;
      _scrapeScan = result;
      _scrapeScope = _cleanupScope;
      return result;
    } catch (e) {
      state = state.copyWith(message: '扫描已停止：${serviceError(e)}');
      return null;
    } finally {
      tmdb?.close();
      dav?.close();
      state = state.copyWith(busy: false, progress: '');
    }
  }

  /// Writes NFO files (and artwork when [artwork] is set) for the selected
  /// videos of the last scrape scan. Existing files are skipped.
  Future<void> executeScrape(
    Iterable<String> videos, {
    bool artwork = true,
  }) async {
    final scan = _scrapeScan;
    if (state.busy ||
        state.executing ||
        scan == null ||
        _scrapeScope != _cleanupScope) {
      return;
    }
    final paths = videos.toSet();
    final selected = scan.targets
        .where((target) => paths.contains(target.video))
        .toList();
    if (selected.isEmpty || selected.length != paths.length) return;
    _maintenanceCancelled = false;
    state = state.copyWith(busy: true, message: '', progress: '');
    WebDavClient? dav;
    TmdbClient? tmdb;
    var written = 0;
    var skipped = 0;
    try {
      dav = client();
      tmdb = ref.read(tmdbFactoryProvider)(config);
      final scraper = MetadataScraper(dav, tmdb);
      for (final root in _scrapeDirectories) {
        final batch = selected.where((t) => t.video.startsWith(root)).toList();
        if (batch.isEmpty) continue;
        final previousWritten = written;
        final previousSkipped = skipped;
        await scraper.write(
          root,
          batch,
          scan.targets.where((t) => t.video.startsWith(root)).toList(),
          artwork: artwork,
          checkCancelled: _checkScrape,
          onWriting: (path) => _record('准备 upload ${displayDavPath(path)} '),
          onWritten: (path) => _record('完成 upload ${displayDavPath(path)} '),
          onProgress: (done, ignored, total) {
            written = previousWritten + done;
            skipped = previousSkipped + ignored;
            state = state.copyWith(
              progress:
                  '${written + skipped} / ${previousWritten + previousSkipped + total}',
            );
          },
        );
      }
      state = state.copyWith(
        message: '搜刮完成：已写入 $written 个文件，跳过 $skipped 个已存在文件',
      );
    } catch (e) {
      state = state.copyWith(
        message: '搜刮已停止：已写入 $written 个文件，跳过 $skipped 个已存在文件；${serviceError(e)}',
      );
    } finally {
      _scrapeScan = null;
      _scrapeScope = null;
      _scrapeDirectories = const [];
      try {
        if (dav != null) {
          state = state.copyWith(entries: await dav.list(state.directory));
        }
      } catch (e) {
        state = state.copyWith(
          message: '${state.message}；刷新目录失败：${serviceError(e)}',
        );
      }
      tmdb?.close();
      dav?.close();
      state = state.copyWith(busy: false, progress: '');
    }
  }

  /// Finds NFO files and artwork in the selected directories.
  Future<List<ScrapeArtifact>> scanScrapeArtifacts({
    Iterable<String>? directories,
  }) async {
    if (state.busy || state.executing || state.directory.isEmpty) return [];
    _scrapeArtifacts = {};
    _artifactScope = null;
    _artifactDirectories = const [];
    _maintenanceCancelled = false;
    state = state.copyWith(busy: true, message: '', progress: '');
    WebDavClient? dav;
    try {
      dav = client();
      final roots = _scrapeRoots(dav, directories);
      if (roots.isEmpty) return [];
      final result = <ScrapeArtifact>[];
      final cleaner = ScrapeCleaner(dav);
      for (final root in roots) {
        result.addAll(
          await cleaner.scan(
            root,
            checkCancelled: _checkMaintenance,
            onProgress: (path) =>
                state = state.copyWith(progress: displayDavPath(path)),
          ),
        );
      }
      _artifactDirectories = roots;
      _scrapeArtifacts = {for (final item in result) item.path: item};
      _artifactScope = _cleanupScope;
      return result;
    } catch (e) {
      state = state.copyWith(message: '扫描已停止：${serviceError(e)}');
      return [];
    } finally {
      dav?.close();
      state = state.copyWith(busy: false, progress: '');
    }
  }

  Future<void> cleanScrapeArtifacts(Iterable<String> selected) async {
    if (state.busy || state.executing || _artifactScope != _cleanupScope) {
      return;
    }
    final paths = selected.toSet();
    if (paths.isEmpty || !paths.every(_scrapeArtifacts.containsKey)) return;
    final artifacts = [for (final path in paths) _scrapeArtifacts[path]!];
    _maintenanceCancelled = false;
    state = state.copyWith(
      busy: true,
      message: '',
      progress: '0 / ${paths.length}',
    );
    WebDavClient? dav;
    var deleted = 0;
    var skipped = 0;
    try {
      dav = client();
      final cleaner = ScrapeCleaner(dav);
      for (final root in _artifactDirectories) {
        final batch = artifacts.where((item) => item.path.startsWith(root));
        if (batch.isEmpty) continue;
        final previousDeleted = deleted;
        final previousSkipped = skipped;
        await cleaner.clean(
          root,
          batch,
          checkCancelled: _checkMaintenance,
          onDeleting: (path) => _record('准备 delete ${displayDavPath(path)} '),
          onDeleted: (path) => _record('完成 delete ${displayDavPath(path)} '),
          onProgress: (done, ignored) {
            deleted = previousDeleted + done;
            skipped = previousSkipped + ignored;
            state = state.copyWith(
              progress: '${deleted + skipped} / ${paths.length}',
            );
          },
        );
      }
      state = state.copyWith(
        message: '清理完成：已删除 $deleted 个搜刮文件，跳过 $skipped 个文件',
      );
    } catch (e) {
      state = state.copyWith(
        message: '清理已停止：已删除 $deleted 个搜刮文件，跳过 $skipped 个文件；${serviceError(e)}',
      );
    } finally {
      _scrapeArtifacts = {};
      _artifactScope = null;
      _artifactDirectories = const [];
      try {
        if (dav != null) {
          state = state.copyWith(entries: await dav.list(state.directory));
        }
      } catch (e) {
        state = state.copyWith(
          message: '${state.message}；刷新目录失败：${serviceError(e)}',
        );
      }
      dav?.close();
      state = state.copyWith(busy: false, progress: '');
    }
  }

  void cancelSuggestions() => _cancelAnalysis?.call();

  void selectDirectories(Iterable<String> paths) {
    if (state.busy || state.executing) return;
    final dav = client();
    try {
      final selected =
          paths
              .map(
                (path) => dav.normalize(path.endsWith('/') ? path : '$path/'),
              )
              .toSet()
              .toList()
            ..sort();
      state = state.copyWith(
        selectedDirectories: List.unmodifiable(selected),
        plan: [],
        clearAnalysis: true,
        message: '',
      );
    } finally {
      dav.close();
    }
  }

  void toggleDirectory(String path) {
    selectDirectories([
      for (final selected in state.selectedDirectories)
        if (selected != path) selected,
      if (!state.selectedDirectories.contains(path)) path,
    ]);
  }

  void setIncludeSubdirectories(bool value) {
    if (state.busy || state.executing) return;
    state = state.copyWith(
      includeSubdirectories: value,
      plan: [],
      clearAnalysis: true,
    );
  }

  void clearPlan() {
    if (state.busy || state.executing) return;
    state = state.copyWith(
      plan: [],
      clearAnalysis: true,
      progress: '',
      message: '',
    );
  }

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
    final directories = state.organizingDirectories;
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
      progress: '',
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
      var scan = AgentActivity(
        key: 'scan',
        kind: AgentActivityKind.scan,
        subject: displayDavPath(state.directory),
      );
      onActivity?.call(scan);
      final analysisEntries = <DavEntry>[];
      final batches = <(String, List<DavEntry>)>[];
      final List<DavEntry> fresh;
      try {
        fresh = await interruptible(dav.list(state.directory));
        for (final scope in directories) {
          final scanned = await interruptible(
            scanMediaDirectories(
              dav,
              scope,
              recursive: state.includeSubdirectories,
              checkCancelled: () {
                if (cancelled) throw StateError('AI 建议已中断');
              },
              onProgress: (path, count) {
                if (!cancelled) {
                  onActivity?.call(
                    AgentActivity(
                      key: 'scan',
                      kind: AgentActivityKind.scan,
                      subject: displayDavPath(path),
                      count: count,
                    ),
                  );
                }
              },
            ),
          );
          analysisEntries.addAll(scanned);
          batches.addAll([
            for (final batch in RenameAgent.batches(scope, scanned))
              (scope, batch),
          ]);
        }
      } catch (error) {
        if (!cancelled) onActivity?.call(scan.fail(serviceError(error)));
        rethrow;
      }
      scan = scan.succeed(count: analysisEntries.length);
      onActivity?.call(scan);
      final plan = <RenameItem>[];
      var accumulatedUsage = const AiUsage();
      var effectiveLayout = folderLayout;
      for (final (batchIndex, (scope, batch)) in batches.indexed) {
        if (cancelled) return;
        state = state.copyWith(
          progress: '${batchIndex + 1} / ${batches.length}',
          analysisDirectory: scope,
        );
        agent = ref.read(renameAgentFactoryProvider)(settings, dav, tmdb);
        final previousUsage = accumulatedUsage;
        var batchUsage = const AiUsage();
        final result = await interruptible(
          agent.propose(
            scope,
            batch,
            instruction: instruction,
            folderLayout: effectiveLayout,
            onLayout: (layout) {
              effectiveLayout = layout;
              if (!cancelled) onLayout?.call(layout);
            },
            onStatus: (message) {
              if (!cancelled) {
                state = state.copyWith(
                  message: '${batchIndex + 1}/${batches.length} · $message',
                );
              }
            },
            onUsage: (usage) {
              batchUsage = usage;
              if (!cancelled) {
                state = state.copyWith(aiUsage: previousUsage.plus(usage));
              }
            },
            onActivity: (activity) {
              if (!cancelled) {
                onActivity?.call(
                  AgentActivity(
                    key: 'batch-$batchIndex-${activity.key}',
                    kind: activity.kind,
                    status: activity.status,
                    subject: activity.subject,
                    number: activity.number,
                    count: activity.count,
                    title: activity.title,
                    date: activity.date,
                    error: activity.error,
                  ),
                );
              }
            },
          ),
        );
        accumulatedUsage = previousUsage.plus(batchUsage);
        agent.close();
        plan.addAll(result);
      }
      if (effectiveLayout != null) {
        var placed = plan;
        for (final scope in directories) {
          placed = applyFolderLayout(
            placed,
            scope,
            effectiveLayout!,
            root: dav.root,
          );
        }
        plan
          ..clear()
          ..addAll(placed);
      }
      if (cancelled) return;
      succeeded = true;
      state = state.copyWith(
        entries: fresh,
        analysisEntries: analysisEntries,
        plan: plan,
        message: batches.isEmpty
            ? '未找到视频文件，请检查所选目录或启用包含子目录'
            : plan.isEmpty
            ? '未找到可靠的重命名建议，请补充片名和年份或剧名和季数后重试'
            : '建议已生成',
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
      state = state.copyWith(busy: false, analyzing: false, progress: '');
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
    final base = Uri.parse(config.webdavUrl).path;
    final root = canonicalDavPath(base.endsWith('/') ? base : '$base/');
    var plan = state.plan;
    for (final scope in state.organizingDirectories) {
      plan = applyFolderLayout(plan, scope, layout, root: root);
    }
    state = state.copyWith(plan: plan);
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
