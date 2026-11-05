// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get includeSubdirectories => '包含子目录';

  @override
  String analysisBatchProgress(String progress) {
    return '正在分析第 $progress 批';
  }

  @override
  String get noVideoFilesFound => '未找到视频文件，请检查所选目录或启用包含子目录';

  @override
  String get cleanupCancelled => '清理已中止';

  @override
  String get cleanupOutsideScope => '目录超出清理范围';

  @override
  String cleanupScanStopped(String error) {
    return '扫描已停止：$error';
  }

  @override
  String cleanupCompleted(String deleted, String skipped) {
    return '清理完成：已删除 $deleted 个空目录，跳过 $skipped 个目录';
  }

  @override
  String cleanupStopped(String deleted, String skipped, String error) {
    return '清理已停止：已删除 $deleted 个空目录，跳过 $skipped 个目录；$error';
  }

  @override
  String get analyzeRecursiveDetail =>
      '将递归扫描所有子目录，并向配置的 AI 服务发送目录路径、视频文件名和整理要求，不会上传文件内容。生成的建议需经确认后才会执行。';

  @override
  String get cleanEmptyDirectories => '清理空目录';

  @override
  String get scanningOrCleaning => '正在扫描 / 清理…';

  @override
  String get noEmptyDirectories => '未发现空目录';

  @override
  String emptyDirectoriesFound(int count) {
    return '发现 $count 个空目录';
  }

  @override
  String cleanSelectedDirectories(int count) {
    return '清理选中项（$count）';
  }

  @override
  String get confirmDeleteEmptyDirectories => '确认删除';

  @override
  String get emptyDirectoryDeleteWarning =>
      '选中目录将从最深层开始永久删除。删除前会重新检查，非空目录会跳过。WebDAV 删除目录可能递归删除内容，清理期间请勿向这些目录写入文件。';

  @override
  String get appTitle => 'Azusa';

  @override
  String get overview => '概览';

  @override
  String get components => '组件';

  @override
  String get examples => '示例';

  @override
  String get settings => '设置';

  @override
  String get general => '常规';

  @override
  String get explore => '探索组件';

  @override
  String get openTasks => '打开任务空间';

  @override
  String get allTasks => '全部任务';

  @override
  String get completed => '已完成';

  @override
  String get pending => '进行中';

  @override
  String get taskWorkspace => '任务空间';

  @override
  String get newTask => '新建任务';

  @override
  String get editTask => '编辑任务';

  @override
  String get title => '标题';

  @override
  String get description => '描述';

  @override
  String get dueDate => '截止日期';

  @override
  String get save => '保存';

  @override
  String get saving => '保存中…';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get requiredTitle => '请输入标题。';

  @override
  String get searchTasks => '搜索任务…';

  @override
  String get emptyTasks => '暂无任务';

  @override
  String get noResults => '没有匹配的结果';

  @override
  String get clearFilters => '清除筛选';

  @override
  String get deleteTitle => '删除这条任务？';

  @override
  String get deleteBody => '这条任务将从当前设备中移除。';

  @override
  String get noDate => '未设置截止日期';

  @override
  String get errorTitle => '遇到了一点问题';

  @override
  String get retry => '重试';

  @override
  String get storageError => '无法保存或读取本地数据。当前输入已保留，请重试。';

  @override
  String get networkError => '连接失败，请检查网络并重试。';

  @override
  String get timeoutError => '请求超时，请重试。';

  @override
  String get serverError => '服务端返回错误，请重试。';

  @override
  String get invalidDataError => '返回数据或配置无效。';

  @override
  String get cancelledError => '请求已取消。';

  @override
  String get searchComponents => '搜索组件…';

  @override
  String get all => '全部';

  @override
  String get basic => '基础展示';

  @override
  String get input => '表单输入';

  @override
  String get content => '内容组织';

  @override
  String get navigation => '导航布局';

  @override
  String get feedback => '反馈浮层';

  @override
  String get preview => '交互预览';

  @override
  String get source => '示例源码';

  @override
  String get copyCode => '复制代码';

  @override
  String get copied => '已复制到剪贴板';

  @override
  String get documentation => '官方文档';

  @override
  String get back => '返回';

  @override
  String get defaultState => '默认';

  @override
  String get disabled => '禁用';

  @override
  String get loading => '加载中…';

  @override
  String get selected => '已选择';

  @override
  String get action => '试试看';

  @override
  String get success => '成功';

  @override
  String get sampleText => '让好想法发生。';

  @override
  String get name => '名称';

  @override
  String get email => '邮箱';

  @override
  String get emailInvalid => '请输入有效邮箱。';

  @override
  String get submit => '提交';

  @override
  String get submitted => '表单已提交';

  @override
  String get optionA => '设计';

  @override
  String get optionB => '开发';

  @override
  String get optionC => '发布';

  @override
  String get openOverlay => '打开浮层';

  @override
  String get close => '关闭';

  @override
  String get appearance => '外观';

  @override
  String get fontSize => '字体大小';

  @override
  String get fontSizeSmall => '小';

  @override
  String get fontSizeStandard => '标准';

  @override
  String get fontSizeLarge => '大';

  @override
  String get fontSizePreview => '预览';

  @override
  String get theme => '主题';

  @override
  String get system => '跟随系统';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get language => '语言';

  @override
  String get namingLanguage => '命名语言';

  @override
  String get namingFormat => '命名格式';

  @override
  String get namingFormatStandard => '标准';

  @override
  String get namingFormatCompact => '简洁';

  @override
  String get namingFormatDotted => '点分隔';

  @override
  String get namingFormatDottedCompact => '点分隔-简洁';

  @override
  String get namingFormatExamples => '命名格式示例';

  @override
  String get namingExampleMovieStandard => '星际穿越 (2014).mkv';

  @override
  String get namingExampleMovieDotted => '星际穿越.2014.mkv';

  @override
  String get namingExampleTvStandard => '绝命毒师 - S01E01 - 试播集.mkv';

  @override
  String get namingExampleTvCompact => '绝命毒师 - S01E01.mkv';

  @override
  String get namingExampleTvDotted => '绝命毒师.S01E01.试播集.mkv';

  @override
  String get namingExampleTvDottedCompact => '绝命毒师.S01E01.mkv';

  @override
  String get organizeSeries => '影视整理';

  @override
  String get sortDirectory => '排序';

  @override
  String get viewOnTmdb => '在 TMDB 查看';

  @override
  String get originalPath => '原路径';

  @override
  String get newPath => '新路径';

  @override
  String get copyPath => '复制路径';

  @override
  String completedAtTime(String time) {
    return '完成于 $time';
  }

  @override
  String get stopSuggestions => '停止生成';

  @override
  String get suggestionsCancelled => 'AI 建议已中断';

  @override
  String get sortName => '名称';

  @override
  String get sortModified => '修改时间';

  @override
  String get sortSize => '大小';

  @override
  String get sortAscending => '升序';

  @override
  String get sortDescending => '降序';

  @override
  String get parentDirectories => '上级目录';

  @override
  String get sortNameAscending => '名称：升序';

  @override
  String get sortNameDescending => '名称：降序';

  @override
  String get sortModifiedDescending => '修改时间：最新在前';

  @override
  String get sortModifiedAscending => '修改时间：最早在前';

  @override
  String get sortSizeDescending => '大小：从大到小';

  @override
  String get sortSizeAscending => '大小：从小到大';

  @override
  String get sortSaveFailed => '保存排序设置失败，请重试';

  @override
  String get executionHistory => '执行记录';

  @override
  String get aiUsage => 'AI 用量';

  @override
  String get switchLight => '切换亮色模式';

  @override
  String get switchDark => '切换暗色模式';

  @override
  String get minimizeWindow => '最小化';

  @override
  String get maximizeWindow => '最大化 / 还原';

  @override
  String get previousStep => '返回上一步';

  @override
  String get saveThemeFailed => '保存主题设置失败，请重试';

  @override
  String get webdavUrl => 'WebDAV 地址';

  @override
  String get webdavConnection => 'WebDAV 连接';

  @override
  String get manageWebdavConnections => '管理连接';

  @override
  String get switchConnection => '切换连接';

  @override
  String get searchConnections => '搜索连接';

  @override
  String get noConnectionsFound => '未找到匹配的连接';

  @override
  String get useConnection => '使用此连接';

  @override
  String connectionActions(String name) {
    return '$name 的连接操作';
  }

  @override
  String get connectionName => '连接名称';

  @override
  String get connectionNameHint => '请输入连接名称';

  @override
  String get webdavUrlHint => '请输入 WebDAV 地址';

  @override
  String get usernameHint => '请输入用户名';

  @override
  String get passwordHint => '请输入密码';

  @override
  String get invalidCredentialVault => '凭据仓库格式无效';

  @override
  String get credentialMigrationVerificationFailed => '凭据仓库迁移验证失败';

  @override
  String get aiUrlHint => '请输入 AI 服务地址';

  @override
  String get modelNameHint => '请输入模型名称';

  @override
  String get apiKeyHint => '请输入 API Key';

  @override
  String get tmdbTokenHint => '请输入 API Key 或 Read Access Token';

  @override
  String get proxyUrlHint => '请输入代理地址';

  @override
  String get addWebdavConnection => '新增 WebDAV';

  @override
  String get currentConnection => '当前连接';

  @override
  String get editConnection => '编辑';

  @override
  String get deleteConnection => '删除';

  @override
  String get discardConnectionPreview => '放弃当前重命名预览并更换连接？';

  @override
  String deleteConnectionConfirmation(String name) {
    return '删除连接“$name”？当前连接的重命名预览也将清空。';
  }

  @override
  String get connectionNameRequired => '请输入连接名称';

  @override
  String get connectionMissing => '连接已不存在';

  @override
  String get waitForCurrentOperation => '请等待当前操作完成';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get aiBaseUrl => 'OpenAI 兼容 API 基础地址';

  @override
  String get modelName => '模型名称';

  @override
  String get fetchModels => '获取模型';

  @override
  String get selectModel => '选择模型';

  @override
  String get searchModels => '搜索模型';

  @override
  String get noMatchingModels => '未找到匹配的模型';

  @override
  String get noModelsAvailable => '服务未返回可用模型，仍可手动填写模型名称。';

  @override
  String fetchModelsFailed(Object error) {
    return '获取模型失败：$error';
  }

  @override
  String get showApiKey => '显示 API Key';

  @override
  String get hideApiKey => '隐藏 API Key';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get testWebdav => '测试 WebDAV';

  @override
  String get testAi => '测试 AI';

  @override
  String get testTmdb => '测试 TMDB';

  @override
  String get saveConfiguration => '保存配置';

  @override
  String get configurationSaved => '配置已保存';

  @override
  String get httpProxy => 'HTTP 代理';

  @override
  String get proxyMode => '代理模式';

  @override
  String get directConnection => '直连';

  @override
  String get systemProxyMode => '系统代理';

  @override
  String get manualProxyMode => '手动代理';

  @override
  String get proxyAddress => '代理地址（http://主机:端口）';

  @override
  String get proxyAi => 'AI 使用代理';

  @override
  String get proxyTmdb => 'TMDB 使用代理';

  @override
  String get proxyWebdav => 'WebDAV 使用代理';

  @override
  String get appAbout => '关于';

  @override
  String get misansLicense => 'MiSans 字体许可';

  @override
  String get tmdbDisclaimer =>
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String connectionFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String configurationLoadFailed(String error) {
    return '读取配置失败：$error';
  }

  @override
  String connectionSucceeded(String route) {
    return '连接成功 · $route';
  }

  @override
  String get warning => '警告';

  @override
  String get information => '信息';

  @override
  String get noticeError => '错误';

  @override
  String get favoriteSaveFailed => '保存收藏失败，请重试';

  @override
  String get favorites => '收藏列表';

  @override
  String get favoritesLoadFailed => '读取收藏失败';

  @override
  String get noFavorites => '暂无收藏目录';

  @override
  String removeFavorite(String path) {
    return '移除收藏 $path';
  }

  @override
  String get confirmAction => '确认';

  @override
  String get analyzeDirectory => '将此目录发送给 AI 分析？';

  @override
  String get analyzeDirectoryDetail =>
      '所选目录及直接子文件夹的路径、文件名将发送至你配置的 AI 服务，文件内容不会上传。';

  @override
  String get startAnalysis => '开始分析';

  @override
  String get executeRenames => '执行已选择的重命名？';

  @override
  String get executeRenamesDetail =>
      '将按预览逐项重命名文件；子文件夹内的文件会移到当前目录，原文件夹保留。遇到失败立即停止，不覆盖已有文件。';

  @override
  String get startExecution => '开始执行';

  @override
  String get configureConnection => '配置连接';

  @override
  String get noConnectionConfigured => '尚未配置 NAS 连接';

  @override
  String get executionSafety => '逐项修改，遇到失败立即停止，不覆盖已有文件。';

  @override
  String get confirmAndExecute => '确认并执行';

  @override
  String get organizeDirectory => '整理此目录';

  @override
  String get parentDirectory => '返回上级';

  @override
  String get refreshDirectory => '刷新目录';

  @override
  String get unfavoriteDirectory => '取消收藏当前目录';

  @override
  String get favoriteDirectory => '收藏当前目录';

  @override
  String get nasDirectory => '目录选择';

  @override
  String get organizingRequirements => '整理要求';

  @override
  String get renamePreview => '修改预览';

  @override
  String get renaming => '正在执行重命名';

  @override
  String get processing => '正在处理…';

  @override
  String get rootDirectory => '根目录';

  @override
  String directoryCounts(int folders, int files) {
    return '$folders 个文件夹 · $files 个文件';
  }

  @override
  String get disconnect => '断开连接';

  @override
  String get connectNas => '连接 NAS';

  @override
  String get filterByName => '搜索文件或文件夹';

  @override
  String get browseNasHint => '尚未连接 NAS';

  @override
  String get directoryEmpty => '此目录为空';

  @override
  String get noNameMatches => '未找到匹配的文件或文件夹';

  @override
  String get openSeriesDirectory => '请先选择影视目录';

  @override
  String get openNonemptyDirectory => '当前目录没有可整理的文件';

  @override
  String get selectDirectory => '选择目录';

  @override
  String get selectCurrentDirectory => '选择此目录';

  @override
  String get noSubdirectories => '没有子目录';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get aiSuggestions => 'AI 整理建议';

  @override
  String get optionalRequirements => '整理要求（可选）';

  @override
  String get requirementsHint => '片名、年份、季数或命名要求';

  @override
  String get generateSuggestions => 'AI 生成重命名建议';

  @override
  String get viewRenamePreview => '查看修改预览';

  @override
  String get noPendingChanges => '暂无待执行的修改';

  @override
  String get backToRequirements => '返回整理要求';

  @override
  String get backToNasDirectory => '返回目录选择';

  @override
  String selectedChanges(int selected, int total, int changes) {
    return '已选 $selected / $total 项 · $changes 项将被修改';
  }

  @override
  String get deselectAll => '全不选';

  @override
  String get selectAll => '全选';

  @override
  String get cannotExecute => '暂时无法执行';

  @override
  String get inputTokens => '输入 Tok';

  @override
  String get outputTokens => '输出 Tok';

  @override
  String get averageTps => '平均 TPS';

  @override
  String get estimatedCost => '预估花费';

  @override
  String get analysisUsage => 'AI 分析用量';

  @override
  String get folder => '文件夹';

  @override
  String openEntry(String name) {
    return '打开 $name';
  }

  @override
  String get pendingRenameShort => '待改';

  @override
  String get pendingRename => '待重命名';

  @override
  String get unchanged => '未变化';

  @override
  String get newFileName => '新文件名';

  @override
  String get fileExtension => '扩展名';

  @override
  String get renameEntry => '重命名';

  @override
  String entryActions(String name) {
    return '$name 的更多操作';
  }

  @override
  String get usageLoadFailed => '读取 AI 用量失败';

  @override
  String get analysisCount => '分析次数';

  @override
  String get modelRequests => '模型请求';

  @override
  String get totalInputTokens => '累计输入 Tok';

  @override
  String get totalOutputTokens => '累计输出 Tok';

  @override
  String get totalEstimatedCost => '预估总花费（USD）';

  @override
  String get analysisHistory => '分析记录';

  @override
  String get usageWeek => '近 7 天';

  @override
  String get usageMonth => '近 30 天';

  @override
  String get usageStatus => '状态';

  @override
  String get usageAverageCost => '已计价分析均价';

  @override
  String get usageRequestsPerAnalysis => '每次分析平均请求';

  @override
  String get usageCachedTokens => '缓存输入 Token';

  @override
  String get usageCacheRate => '缓存命中率';

  @override
  String get usageModelPerformance => '模型性能';

  @override
  String get usageAverageRequestTime => '平均请求耗时';

  @override
  String get usageModelTime => '模型请求耗时';

  @override
  String get usageTrend => '用量趋势';

  @override
  String get usageModels => '模型汇总';

  @override
  String get usageTokens => 'Token';

  @override
  String get usageDirectorySearch => '搜索目录';

  @override
  String get usageNewest => '时间倒序';

  @override
  String get usageHighestCost => '花费从高到低';

  @override
  String get usageLoadMore => '加载更多';

  @override
  String get usageNoMatches => '未找到匹配的用量记录';

  @override
  String get usagePriceSource => '价格来源';

  @override
  String get usageTime => '时间';

  @override
  String get usageRefresh => '刷新用量';

  @override
  String incompleteUsageCount(int count) {
    return '$count 次用量不完整';
  }

  @override
  String unknownCostCount(int count) {
    return '$count 次花费未知';
  }

  @override
  String get noAiUsage => '暂无 AI 用量记录';

  @override
  String get failed => '失败';

  @override
  String usageInput(String tokens) {
    return '输入 $tokens Tok';
  }

  @override
  String usageOutput(String tokens) {
    return '输出 $tokens Tok';
  }

  @override
  String get unknownCost => '花费 —';

  @override
  String modelRequestCount(int count) {
    return '$count 次模型请求';
  }

  @override
  String historyLoadFailed(String error) {
    return '读取记录失败：$error';
  }

  @override
  String get noExecutionHistory => '暂无执行记录';

  @override
  String operationCount(int count) {
    return '$count 项操作';
  }

  @override
  String get otherRecords => '其他记录';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get initiated => '已发起';

  @override
  String get collapseHistory => '收起记录详情';

  @override
  String get expandHistory => '展开记录详情';

  @override
  String startedAtTime(String time) {
    return '开始于 $time';
  }

  @override
  String get renameAction => '重命名';

  @override
  String get moveAction => '移动 / 重命名';

  @override
  String get moveOnlyAction => '移动';

  @override
  String get moveAndRenameAction => '移动并重命名';

  @override
  String get uploadAction => '上传文件';

  @override
  String get createDirectory => '新建文件夹';

  @override
  String get operationRecord => '操作记录';

  @override
  String get invalidDirectoryPath => '目录路径无效';

  @override
  String get favoriteOutsideRoot => '收藏目录超出 NAS 根目录';

  @override
  String get webdavUrlParameters => 'WebDAV 地址不能包含参数';

  @override
  String get pathOutsideConnection => '路径不在 WebDAV 连接目录内';

  @override
  String get invalidWebdavProperties => 'WebDAV 未返回有效属性';

  @override
  String get unknownFileStatus => '无法确定文件状态，请检查 WebDAV 权限';

  @override
  String get moveUnconfirmed => '移动未确认成功，请刷新目录核对';

  @override
  String get directoryCreationUnconfirmed => '创建目录未确认成功';

  @override
  String get deleteUnconfirmed => '删除未确认成功，请刷新目录核对';

  @override
  String get uploadUnconfirmed => '上传未确认成功，请刷新目录核对';

  @override
  String get absoluteWebdavPathRequired => 'WebDAV 路径必须为绝对路径';

  @override
  String get unsafeWebdavPath => 'WebDAV 路径包含不安全的字符';

  @override
  String get networkClientClosed => '网络客户端已关闭';

  @override
  String get systemProxyTimeout => '读取系统代理超时';

  @override
  String get invalidSystemProxy => '系统代理未返回有效配置';

  @override
  String get systemProxyUnsupported => '当前平台不支持读取系统代理';

  @override
  String get systemProxyReadFailed => '读取系统代理失败';

  @override
  String get environmentProxyUnsupported => '系统环境代理仅支持无认证 HTTP 代理';

  @override
  String get systemProxyTypeUnsupported => '系统代理包含不支持的类型，仅支持无认证 HTTP 代理';

  @override
  String get databaseClosed => '数据库已关闭';

  @override
  String get databaseVersionTooNew => '数据库版本过高';

  @override
  String get targetFileExists => '目标文件已存在';

  @override
  String get queryingMetadata => '正在查询影视资料…';

  @override
  String get suggestionsGenerated => '建议已生成';

  @override
  String get noReliableSuggestions => '未找到可靠的重命名建议，请补充片名和年份或剧名和季数后重试';

  @override
  String get usageSaveFailed => '保存 AI 用量失败';

  @override
  String get operationCompleted => '操作完成';

  @override
  String get downloading => '正在下载…';

  @override
  String get downloadCompleted => '下载完成';

  @override
  String get preparingExecution => '准备执行';

  @override
  String directoryReadFailed(String error) {
    return '读取目录失败：$error';
  }

  @override
  String suggestionsFailed(String error) {
    return '生成建议失败：$error';
  }

  @override
  String downloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String fileOperationStopped(String error) {
    return '文件操作已停止：$error；请刷新目录核对结果';
  }

  @override
  String executionStopped(String error) {
    return '执行已停止：$error；请刷新目录核对结果';
  }

  @override
  String remainingExecutionStopped(String error) {
    return '已停止：$error。请核对后再次确认执行剩余项';
  }

  @override
  String completedItemCount(int count) {
    return '已完成 $count 项';
  }

  @override
  String aiAnalyzing(int count) {
    return 'AI 分析中（$count/8）';
  }

  @override
  String queryingTool(String name) {
    return '查询：$name';
  }

  @override
  String matchEvidence(String season, String episode, String title, String id) {
    return '匹配结果：第 $season 季第 $episode 集 · $title\nTMDB $id';
  }

  @override
  String authenticationFailed(String code) {
    return '认证失败或没有访问权限（HTTP $code）';
  }

  @override
  String get proxyAuthenticationUnsupported => '代理要求认证，当前仅支持无认证 HTTP 代理';

  @override
  String get remoteFileChanged => '文件已变化或目标已存在，请刷新目录核对';

  @override
  String get rateLimited => '请求过于频繁，请稍后再试';

  @override
  String get networkConnectionFailed => '网络连接失败或超时，请检查服务地址与 HTTP 代理';

  @override
  String httpStatusError(String code) {
    return '服务返回 HTTP $code';
  }

  @override
  String get operationFailed => '操作失败，请重试';

  @override
  String get invalidServiceUrl => '请输入有效的 HTTPS 地址（WebDAV 可使用 HTTP）';

  @override
  String get invalidProxyUrl => '代理地址应为 http://主机:端口';

  @override
  String get proxyUrlRequired => '请输入代理地址';

  @override
  String get invalidAiModels => 'AI /models 未返回有效 JSON';

  @override
  String get aiClientClosed => 'AI 客户端已关闭';

  @override
  String get aiAlreadyRunning => 'AI 正在分析';

  @override
  String get modelNameRequired => '请填写 AI 模型名称';

  @override
  String get tooManyFiles => '当前目录文件超过 500 个，请选择更小的影视目录';

  @override
  String get aiCallLimit => 'AI 工具调用次数超过限制';

  @override
  String get invalidAiSuggestions => 'AI 未返回有效建议或已达到执行限制';

  @override
  String get missingTmdbEvidence => 'AI 建议缺少有效 TMDB 集数依据，请重试';

  @override
  String get tmdbTokenRequired => '请配置 TMDB Token';

  @override
  String get invalidMovieQuery => '电影查询无效';

  @override
  String get invalidMovieId => '电影编号无效';

  @override
  String get invalidMovieDetails => 'TMDB 电影详情无效';

  @override
  String get invalidMediaType => 'AI 建议媒体类型无效，请重试';

  @override
  String get missingMovieEvidence => 'AI 建议缺少有效 TMDB 电影依据，请重试';

  @override
  String movieMatchEvidence(String title, String date, String id) {
    return '电影匹配：$title · $date\nTMDB $id';
  }

  @override
  String subtitleRenamedWithVideo(String name) {
    return '随视频重命名 · $name';
  }

  @override
  String get invalidSeriesQuery => '剧集查询无效';

  @override
  String get invalidSeasonNumber => '剧集或季编号无效';

  @override
  String get duplicateSource => '同一源文件出现多次';

  @override
  String get sourceAttributesChanged => '源文件属性已变化，请重新生成建议';

  @override
  String get targetConflict => '目标与待处理文件冲突';

  @override
  String get taskAlreadyRunning => '整理任务正在执行';

  @override
  String get sourceMissing => '源文件已不存在';

  @override
  String get sourceChanged => '源文件属性已变化';

  @override
  String get targetExists => '目标已存在';

  @override
  String get rootModificationForbidden => '不能修改 WebDAV 根目录';

  @override
  String get moveIntoSelfForbidden => '不能移动目录到自身内部';

  @override
  String get unsupportedFileOperation => '不支持的文件操作';

  @override
  String get invalidFileNameEmpty => '文件名无效：文件名不能为空';

  @override
  String get invalidFileNameControl => '文件名无效：不能包含控制字符';

  @override
  String get invalidFileNameEnding => '文件名无效：不能以空格或句点结尾';

  @override
  String get invalidFileNameCharacters => '文件名包含非法字符';

  @override
  String sourcePathChanged(String path) {
    return '源文件已变化：$path';
  }

  @override
  String extensionRequired(String extension) {
    return '必须保留扩展名：$extension';
  }

  @override
  String duplicateTargetName(String name) {
    return '目标文件名重复：$name';
  }

  @override
  String targetNameExists(String name) {
    return '目标已存在：$name';
  }

  @override
  String invalidFileNameReserved(String name) {
    return '文件名无效：不能使用“$name”';
  }

  @override
  String invalidFileNameReplace(String character, String replacement) {
    return '文件名无效：不能包含“$character”，请替换为“$replacement”或“-”';
  }

  @override
  String get compactSidebar => '紧凑侧栏';

  @override
  String get about => '关于模板';

  @override
  String get version => '版本';

  @override
  String get openSourceLicenses => '第三方开源声明';

  @override
  String get fonts => '字体声明';

  @override
  String get fontNotice =>
      '本应用使用 MiSans 字体，© 小米科技有限责任公司，遵循《MiSans 字体知识产权许可协议》。';

  @override
  String get runtimeEnvironment => '运行环境';

  @override
  String get operatingSystem => '操作系统';

  @override
  String get systemVersion => '系统版本';

  @override
  String get dartVersion => 'Dart 版本';

  @override
  String get buildMode => '构建模式';

  @override
  String get buildModeDebug => '调试（Debug）';

  @override
  String get buildModeProfile => '性能分析（Profile）';

  @override
  String get buildModeRelease => '发布（Release）';

  @override
  String get processorCount => '逻辑处理器数量';

  @override
  String get windowSize => '窗口尺寸（逻辑像素）';

  @override
  String get devicePixelRatio => '设备像素比';

  @override
  String get systemLocale => '系统区域设置';

  @override
  String get appLocale => '应用语言';

  @override
  String get openDocs => 'Forui 文档';

  @override
  String get linkError => '无法打开链接。';

  @override
  String get networkDemo => '网络演示';

  @override
  String get mockMode => '离线模拟';

  @override
  String get liveMode => '真实接口';

  @override
  String get empty => '空数据';

  @override
  String get timeout => '超时';

  @override
  String get serverFailure => '服务端错误';

  @override
  String get reload => '重新加载';

  @override
  String get emptyNetwork => '请求成功，暂无数据。';

  @override
  String get tasks => '任务';

  @override
  String get network => '网络';

  @override
  String get minimize => '最小化';

  @override
  String get maximize => '最大化';

  @override
  String get restore => '还原';

  @override
  String get notFound => '页面不存在';

  @override
  String get goHome => '返回概览';

  @override
  String get themeColor => '主题色';

  @override
  String get radiusScale => '圆角系数';

  @override
  String get colorNeutral => '中性';

  @override
  String get colorBlue => '蓝色';

  @override
  String get colorGreen => '绿色';

  @override
  String get colorViolet => '紫色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorRose => '玫红';

  @override
  String get logs => '日志';

  @override
  String get searchLogs => '搜索日志';

  @override
  String get pauseLogs => '暂停';

  @override
  String get resumeLogs => '恢复';

  @override
  String get autoScrollLogs => '自动滚动';

  @override
  String get copyVisibleLogs => '复制结果';

  @override
  String get copyLogEntry => '复制此条日志';

  @override
  String get clearLogView => '清空视图';

  @override
  String get noLiveLogs => '暂无日志';

  @override
  String get noMatchingLogs => '未找到匹配的日志';

  @override
  String get logCopyError => '无法复制日志，请重试。';

  @override
  String logEntryCount(int count) {
    return '$count 条';
  }

  @override
  String get exportLogs => '导出日志';

  @override
  String get exportingLogs => '正在导出日志…';

  @override
  String get noLogsToExport => '暂无可导出的日志。';

  @override
  String get logsExported => '日志压缩包已保存。';

  @override
  String get logsShared => '日志压缩包已分享。';

  @override
  String get logShareOpened => '已打开日志分享，请在系统分享面板中完成导出。';

  @override
  String get logExportError => '无法导出日志，请检查可用存储空间后重试。';

  @override
  String get assistantTab => '整理助手';

  @override
  String get filesTab => '文件管理';

  @override
  String get assistantInputHint => '输入整理要求';

  @override
  String get assistantSend => '发送';

  @override
  String get assistantStop => '停止';

  @override
  String get assistantNewConversation => '新对话';

  @override
  String get assistantEmptyTitle => '要怎么整理这个目录？';

  @override
  String get assistantPromptOrganize => '识别并整理这个目录';

  @override
  String get assistantPromptSeriesOnly => '只整理剧集，跳过电影';

  @override
  String get assistantPromptMoviesOnly => '只整理电影，跳过剧集';

  @override
  String get activityScan => '读取目录';

  @override
  String activityModel(int round) {
    return 'AI 分析 · 第 $round 轮';
  }

  @override
  String activitySearchMovie(String query) {
    return '搜索电影「$query」';
  }

  @override
  String activitySearchMovieYear(String query, int year) {
    return '搜索电影「$query」· $year';
  }

  @override
  String activitySearchTv(String query) {
    return '搜索剧集「$query」';
  }

  @override
  String get activityGetMovie => '核对电影详情';

  @override
  String activityMovieVerified(String title) {
    return '核对电影「$title」';
  }

  @override
  String activitySeason(int season) {
    return '获取第 $season 季资料';
  }

  @override
  String activitySeasonOf(String title, int season) {
    return '获取「$title」第 $season 季';
  }

  @override
  String get activityListDirectory => '查看目录清单';

  @override
  String activityEntries(int count) {
    return '$count 个条目';
  }

  @override
  String activityCandidates(int count) {
    return '$count 个候选';
  }

  @override
  String activityEpisodes(int count) {
    return '$count 集';
  }

  @override
  String get activityStopped => '已停止';

  @override
  String get runWorking => '正在处理';

  @override
  String runDone(int count) {
    return '已完成 $count 次查询';
  }

  @override
  String get runFailed => '未完成';

  @override
  String get runStopped => '已停止';

  @override
  String runSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get showActivity => '展开过程';

  @override
  String get hideActivity => '收起过程';

  @override
  String get replyPlan => '已生成整理方案，请核对后执行。';

  @override
  String get replyPlanRevised => '已按新要求更新整理方案。';

  @override
  String planVersion(int version) {
    return '整理方案 · 第 $version 版';
  }

  @override
  String planMovies(int count) {
    return '$count 部电影';
  }

  @override
  String planSeries(int count) {
    return '$count 部剧集';
  }

  @override
  String planChanges(int count) {
    return '$count 个文件将修改';
  }

  @override
  String planUnchanged(int count) {
    return '$count 个无需修改';
  }

  @override
  String get planSuperseded => '已替换';

  @override
  String planRemaining(int count) {
    return '剩余 $count 项未执行';
  }

  @override
  String get viewChanges => '查看变更';

  @override
  String get planPanelTitle => '整理方案';

  @override
  String get noPlanYet => '暂无整理方案';

  @override
  String get movieLabel => '电影';

  @override
  String get seriesLabel => '剧集';

  @override
  String get otherFiles => '其他文件';

  @override
  String seasonLabel(int season) {
    return '第 $season 季';
  }

  @override
  String get assistantPromptFolders => '按作品建立文件夹并分季整理';

  @override
  String get folderLayout => '目录结构';

  @override
  String get folderMovies => '电影独立文件夹';

  @override
  String get folderSeries => '剧集独立文件夹';

  @override
  String get folderSeasons => '按季分文件夹';

  @override
  String planFolders(int count) {
    return '新建 $count 个文件夹';
  }

  @override
  String get replyLayout => '已调整目录结构。';

  @override
  String get newFolderBadge => '新建';

  @override
  String get executeOrganizeDetail =>
      '将按方案新建文件夹并逐项移动、重命名文件；原文件夹保留。遇到失败立即停止，不覆盖已有文件。';
}
