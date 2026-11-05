// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addDirectories => 'Add folders';

  @override
  String removeSelectedDirectory(String name) {
    return 'Remove folder: $name';
  }

  @override
  String get assistantEmptyTitleMultiple =>
      'How should these folders be organized?';

  @override
  String get assistantPromptOrganizeMultiple =>
      'Identify and organize these folders';

  @override
  String get selectAllDirectories => 'Select folders';

  @override
  String get clearDirectorySelection => 'Clear selection';

  @override
  String selectedDirectoryCount(int count) {
    return '$count folders selected';
  }

  @override
  String organizeSelectedDirectories(int count) {
    return 'Organize selected folders ($count)';
  }

  @override
  String get includeSubdirectories => 'Include subdirectories';

  @override
  String analysisBatchProgress(String progress) {
    return 'Analyzing batch $progress';
  }

  @override
  String get noVideoFilesFound =>
      'No video files found. Check the selected folder or enable subdirectories.';

  @override
  String get cleanupCancelled => 'Cleanup cancelled';

  @override
  String get cleanupOutsideScope => 'Folder is outside the cleanup scope';

  @override
  String cleanupScanStopped(String error) {
    return 'Scan stopped: $error';
  }

  @override
  String cleanupCompleted(String deleted, String skipped) {
    return 'Cleanup complete: deleted $deleted empty folders, skipped $skipped folders';
  }

  @override
  String cleanupStopped(String deleted, String skipped, String error) {
    return 'Cleanup stopped: deleted $deleted empty folders, skipped $skipped folders; $error';
  }

  @override
  String get analyzeRecursiveDetail =>
      'All subdirectories will be scanned. Directory paths, video filenames and your instructions will be sent to the configured AI service; file contents will not be uploaded. Suggestions require confirmation before execution.';

  @override
  String get cleanEmptyDirectories => 'Clean empty folders';

  @override
  String get scanningOrCleaning => 'Scanning / cleaning…';

  @override
  String get noEmptyDirectories => 'No empty folders found';

  @override
  String emptyDirectoriesFound(int count) {
    return 'Found $count empty folders';
  }

  @override
  String cleanSelectedDirectories(int count) {
    return 'Clean selected ($count)';
  }

  @override
  String get confirmDeleteEmptyDirectories => 'Confirm deletion';

  @override
  String get emptyDirectoryDeleteWarning =>
      'Selected folders will be deleted permanently, deepest first. Contents are checked again before deletion; non-empty folders are skipped. WebDAV folder deletion can be recursive: do not write files into these folders during cleanup.';

  @override
  String get appTitle => 'Azusa';

  @override
  String get overview => 'Overview';

  @override
  String get components => 'Components';

  @override
  String get examples => 'Examples';

  @override
  String get settings => 'Settings';

  @override
  String get general => 'General';

  @override
  String get explore => 'Explore components';

  @override
  String get openTasks => 'Open task workspace';

  @override
  String get allTasks => 'All tasks';

  @override
  String get completed => 'Completed';

  @override
  String get pending => 'In progress';

  @override
  String get taskWorkspace => 'Task workspace';

  @override
  String get newTask => 'New task';

  @override
  String get editTask => 'Edit task';

  @override
  String get title => 'Title';

  @override
  String get description => 'Description';

  @override
  String get dueDate => 'Due date';

  @override
  String get save => 'Save';

  @override
  String get saving => 'Saving…';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get requiredTitle => 'Enter a title.';

  @override
  String get searchTasks => 'Search tasks…';

  @override
  String get emptyTasks => 'No tasks yet';

  @override
  String get noResults => 'No matching results';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get deleteTitle => 'Delete this task?';

  @override
  String get deleteBody => 'This task will be removed from this device.';

  @override
  String get noDate => 'No due date';

  @override
  String get errorTitle => 'Something needs attention';

  @override
  String get retry => 'Try again';

  @override
  String get storageError =>
      'Could not save or read local data. Your current input is preserved. Please try again.';

  @override
  String get networkError =>
      'Connection failed. Check your network and try again.';

  @override
  String get timeoutError => 'The request timed out. Please try again.';

  @override
  String get serverError => 'The server returned an error. Please try again.';

  @override
  String get invalidDataError => 'The response or configuration is invalid.';

  @override
  String get cancelledError => 'Request cancelled.';

  @override
  String get searchComponents => 'Search components…';

  @override
  String get all => 'All';

  @override
  String get basic => 'Essentials';

  @override
  String get input => 'Forms';

  @override
  String get content => 'Content';

  @override
  String get navigation => 'Navigation';

  @override
  String get feedback => 'Feedback';

  @override
  String get preview => 'Live preview';

  @override
  String get source => 'Source code';

  @override
  String get copyCode => 'Copy code';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get documentation => 'Documentation';

  @override
  String get back => 'Back';

  @override
  String get defaultState => 'Default';

  @override
  String get disabled => 'Disabled';

  @override
  String get loading => 'Loading…';

  @override
  String get selected => 'Selected';

  @override
  String get action => 'Try it';

  @override
  String get success => 'Success';

  @override
  String get sampleText => 'Make room for good ideas.';

  @override
  String get name => 'Name';

  @override
  String get email => 'Email';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String get submit => 'Submit';

  @override
  String get submitted => 'Form submitted';

  @override
  String get optionA => 'Design';

  @override
  String get optionB => 'Develop';

  @override
  String get optionC => 'Ship';

  @override
  String get openOverlay => 'Open overlay';

  @override
  String get close => 'Close';

  @override
  String get appearance => 'Appearance';

  @override
  String get fontSize => 'Font size';

  @override
  String get fontSizeSmall => 'Small';

  @override
  String get fontSizeStandard => 'Standard';

  @override
  String get fontSizeLarge => 'Large';

  @override
  String get fontSizePreview => 'Preview';

  @override
  String get theme => 'Theme';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get namingLanguage => 'Naming language';

  @override
  String get namingFormat => 'Naming format';

  @override
  String get namingFormatStandard => 'Standard';

  @override
  String get namingFormatCompact => 'Compact';

  @override
  String get namingFormatDotted => 'Dot-separated';

  @override
  String get namingFormatDottedCompact => 'Dot-separated - compact';

  @override
  String get namingFormatExamples => 'Naming format examples';

  @override
  String get namingExampleMovieStandard => 'Interstellar (2014).mkv';

  @override
  String get namingExampleMovieDotted => 'Interstellar.2014.mkv';

  @override
  String get namingExampleTvStandard => 'Breaking Bad - S01E01 - Pilot.mkv';

  @override
  String get namingExampleTvCompact => 'Breaking Bad - S01E01.mkv';

  @override
  String get namingExampleTvDotted => 'Breaking.Bad.S01E01.Pilot.mkv';

  @override
  String get namingExampleTvDottedCompact => 'Breaking.Bad.S01E01.mkv';

  @override
  String get organizeSeries => 'Organize media';

  @override
  String get sortDirectory => 'Sort';

  @override
  String get viewOnTmdb => 'View on TMDB';

  @override
  String get originalPath => 'Original path';

  @override
  String get newPath => 'New path';

  @override
  String get copyPath => 'Copy path';

  @override
  String completedAtTime(String time) {
    return 'Completed at $time';
  }

  @override
  String get stopSuggestions => 'Stop generating';

  @override
  String get suggestionsCancelled => 'AI suggestions cancelled';

  @override
  String get sortName => 'Name';

  @override
  String get sortModified => 'Modified';

  @override
  String get sortSize => 'Size';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get parentDirectories => 'Parent directories';

  @override
  String get sortNameAscending => 'Name: A to Z';

  @override
  String get sortNameDescending => 'Name: Z to A';

  @override
  String get sortModifiedDescending => 'Modified: newest first';

  @override
  String get sortModifiedAscending => 'Modified: oldest first';

  @override
  String get sortSizeDescending => 'Size: largest first';

  @override
  String get sortSizeAscending => 'Size: smallest first';

  @override
  String get sortSaveFailed => 'Could not save sort settings. Try again';

  @override
  String get executionHistory => 'Execution history';

  @override
  String get aiUsage => 'AI usage';

  @override
  String get switchLight => 'Switch to light mode';

  @override
  String get switchDark => 'Switch to dark mode';

  @override
  String get minimizeWindow => 'Minimize';

  @override
  String get maximizeWindow => 'Maximize / Restore';

  @override
  String get previousStep => 'Back to previous step';

  @override
  String get saveThemeFailed => 'Could not save theme. Please try again.';

  @override
  String get webdavUrl => 'WebDAV URL';

  @override
  String get webdavConnection => 'WebDAV connection';

  @override
  String get manageWebdavConnections => 'Manage connections';

  @override
  String get switchConnection => 'Switch connection';

  @override
  String get searchConnections => 'Search connections';

  @override
  String get noConnectionsFound => 'No matching connections';

  @override
  String get useConnection => 'Use connection';

  @override
  String connectionActions(String name) {
    return 'Connection actions for $name';
  }

  @override
  String get connectionName => 'Connection name';

  @override
  String get connectionNameHint => 'Enter a connection name';

  @override
  String get webdavUrlHint => 'Enter a WebDAV URL';

  @override
  String get usernameHint => 'Enter a username';

  @override
  String get passwordHint => 'Enter a password';

  @override
  String get invalidCredentialVault => 'The credential vault format is invalid';

  @override
  String get credentialMigrationVerificationFailed =>
      'Credential vault migration verification failed';

  @override
  String get aiUrlHint => 'Enter an AI service URL';

  @override
  String get modelNameHint => 'Enter a model name';

  @override
  String get apiKeyHint => 'Enter an API Key';

  @override
  String get tmdbTokenHint => 'Enter an API Key or Read Access Token';

  @override
  String get proxyUrlHint => 'Enter a proxy URL';

  @override
  String get addWebdavConnection => 'Add WebDAV';

  @override
  String get currentConnection => 'Current connection';

  @override
  String get editConnection => 'Edit';

  @override
  String get deleteConnection => 'Delete';

  @override
  String get discardConnectionPreview =>
      'Discard the current rename preview and change connection?';

  @override
  String deleteConnectionConfirmation(String name) {
    return 'Delete connection “$name”? Its active rename preview will also be cleared.';
  }

  @override
  String get connectionNameRequired => 'Enter a connection name';

  @override
  String get connectionMissing => 'The connection no longer exists';

  @override
  String get waitForCurrentOperation =>
      'Wait for the current operation to finish';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get aiBaseUrl => 'OpenAI-compatible API base URL';

  @override
  String get modelName => 'Model name';

  @override
  String get fetchModels => 'Fetch models';

  @override
  String get selectModel => 'Select model';

  @override
  String get searchModels => 'Search models';

  @override
  String get noMatchingModels => 'No matching models found';

  @override
  String get noModelsAvailable =>
      'The service returned no available models. You can still enter a model name manually.';

  @override
  String fetchModelsFailed(Object error) {
    return 'Could not fetch models: $error';
  }

  @override
  String get showApiKey => 'Show API key';

  @override
  String get hideApiKey => 'Hide API key';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get testWebdav => 'Test WebDAV';

  @override
  String get testAi => 'Test AI';

  @override
  String get testTmdb => 'Test TMDB';

  @override
  String get saveConfiguration => 'Save configuration';

  @override
  String get configurationSaved => 'Configuration saved';

  @override
  String get httpProxy => 'HTTP proxy';

  @override
  String get proxyMode => 'Proxy mode';

  @override
  String get directConnection => 'Direct';

  @override
  String get systemProxyMode => 'System proxy';

  @override
  String get manualProxyMode => 'Manual proxy';

  @override
  String get proxyAddress => 'Proxy URL (http://host:port)';

  @override
  String get proxyAi => 'Use proxy for AI';

  @override
  String get proxyTmdb => 'Use proxy for TMDB';

  @override
  String get proxyWebdav => 'Use proxy for WebDAV';

  @override
  String get appAbout => 'About';

  @override
  String get misansLicense => 'MiSans font license';

  @override
  String get tmdbDisclaimer =>
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';

  @override
  String saveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String connectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String configurationLoadFailed(String error) {
    return 'Could not load configuration: $error';
  }

  @override
  String connectionSucceeded(String route) {
    return 'Connected · $route';
  }

  @override
  String get warning => 'Warning';

  @override
  String get information => 'Information';

  @override
  String get noticeError => 'Error';

  @override
  String get favoriteSaveFailed =>
      'Could not save favorites. Please try again.';

  @override
  String get favorites => 'Favorites';

  @override
  String get favoritesLoadFailed => 'Could not load favorites';

  @override
  String get noFavorites => 'No favorite directories';

  @override
  String removeFavorite(String path) {
    return 'Remove favorite $path';
  }

  @override
  String get confirmAction => 'Confirm';

  @override
  String get analyzeDirectory => 'Send this directory to AI for analysis?';

  @override
  String get analyzeDirectoryDetail =>
      'Paths and file names in the selected directory and its immediate subfolders will be sent to your configured AI service. File contents will not be uploaded.';

  @override
  String get startAnalysis => 'Start analysis';

  @override
  String get executeRenames => 'Execute selected renames?';

  @override
  String get executeRenamesDetail =>
      'Files will be renamed as previewed. Files in subfolders will move into the selected directory; original subfolders remain. Execution stops on failure and never overwrites existing files.';

  @override
  String get startExecution => 'Start execution';

  @override
  String get configureConnection => 'Configure connection';

  @override
  String get noConnectionConfigured => 'No NAS connection configured';

  @override
  String get executionSafety =>
      'Rename one by one, stop on failure, and never overwrite existing files.';

  @override
  String get confirmAndExecute => 'Confirm and execute';

  @override
  String get organizeDirectory => 'Organize this directory';

  @override
  String get parentDirectory => 'Parent directory';

  @override
  String get refreshDirectory => 'Refresh directory';

  @override
  String get unfavoriteDirectory => 'Unfavorite current directory';

  @override
  String get favoriteDirectory => 'Favorite current directory';

  @override
  String get nasDirectory => 'Directory selection';

  @override
  String get organizingRequirements => 'Organizing requirements';

  @override
  String get renamePreview => 'Rename preview';

  @override
  String get renaming => 'Renaming files';

  @override
  String get processing => 'Processing…';

  @override
  String get rootDirectory => 'Root';

  @override
  String directoryCounts(int folders, int files) {
    return '$folders folders · $files files';
  }

  @override
  String get disconnect => 'Disconnect';

  @override
  String get connectNas => 'Connect NAS';

  @override
  String get filterByName => 'Search files or folders';

  @override
  String get browseNasHint => 'Not connected to NAS';

  @override
  String get directoryEmpty => 'This directory is empty';

  @override
  String get noNameMatches => 'No matching files or folders found';

  @override
  String get openSeriesDirectory => 'Select a media directory first';

  @override
  String get openNonemptyDirectory => 'No files to organize in this directory';

  @override
  String get selectDirectory => 'Select directory';

  @override
  String get selectCurrentDirectory => 'Select this directory';

  @override
  String get noSubdirectories => 'No subdirectories';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get aiSuggestions => 'AI organizing suggestions';

  @override
  String get optionalRequirements => 'Organizing requirements (optional)';

  @override
  String get requirementsHint => 'Title, year, season, or naming requirements';

  @override
  String get generateSuggestions => 'Generate rename suggestions';

  @override
  String get viewRenamePreview => 'View rename preview';

  @override
  String get noPendingChanges => 'No pending changes';

  @override
  String get backToRequirements => 'Back to requirements';

  @override
  String get backToNasDirectory => 'Back to directory selection';

  @override
  String selectedChanges(int selected, int total, int changes) {
    return '$selected / $total selected · $changes changes';
  }

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get selectAll => 'Select all';

  @override
  String get cannotExecute => 'Cannot execute yet';

  @override
  String get inputTokens => 'Input tokens';

  @override
  String get outputTokens => 'Output tokens';

  @override
  String get averageTps => 'Average TPS';

  @override
  String get estimatedCost => 'Estimated cost';

  @override
  String get analysisUsage => 'AI analysis usage';

  @override
  String get folder => 'Folder';

  @override
  String openEntry(String name) {
    return 'Open $name';
  }

  @override
  String get pendingRenameShort => 'Pending';

  @override
  String get pendingRename => 'Pending rename';

  @override
  String get unchanged => 'Unchanged';

  @override
  String get newFileName => 'New file name';

  @override
  String get fileExtension => 'Extension';

  @override
  String get renameEntry => 'Rename';

  @override
  String entryActions(String name) {
    return 'More actions for $name';
  }

  @override
  String get usageLoadFailed => 'Could not load AI usage';

  @override
  String get analysisCount => 'Analyses';

  @override
  String get modelRequests => 'Model requests';

  @override
  String get totalInputTokens => 'Total input tokens';

  @override
  String get totalOutputTokens => 'Total output tokens';

  @override
  String get totalEstimatedCost => 'Estimated total cost (USD)';

  @override
  String get analysisHistory => 'Analysis history';

  @override
  String get usageWeek => 'Last 7 days';

  @override
  String get usageMonth => 'Last 30 days';

  @override
  String get usageStatus => 'Status';

  @override
  String get usageAverageCost => 'Average cost / priced analysis';

  @override
  String get usageRequestsPerAnalysis => 'Requests / analysis';

  @override
  String get usageCachedTokens => 'Cached input tokens';

  @override
  String get usageCacheRate => 'Cache hit rate';

  @override
  String get usageModelPerformance => 'Model performance';

  @override
  String get usageAverageRequestTime => 'Average request time';

  @override
  String get usageModelTime => 'Model request time';

  @override
  String get usageTrend => 'Usage trend';

  @override
  String get usageModels => 'Model breakdown';

  @override
  String get usageTokens => 'Tokens';

  @override
  String get usageDirectorySearch => 'Search directories';

  @override
  String get usageNewest => 'Newest first';

  @override
  String get usageHighestCost => 'Highest cost first';

  @override
  String get usageLoadMore => 'Load more';

  @override
  String get usageNoMatches => 'No matching usage records found';

  @override
  String get usagePriceSource => 'Price source';

  @override
  String get usageTime => 'Time';

  @override
  String get usageRefresh => 'Refresh usage';

  @override
  String incompleteUsageCount(int count) {
    return '$count with incomplete usage';
  }

  @override
  String unknownCostCount(int count) {
    return '$count with unknown cost';
  }

  @override
  String get noAiUsage => 'No AI usage records yet';

  @override
  String get failed => 'Failed';

  @override
  String usageInput(String tokens) {
    return 'Input $tokens tokens';
  }

  @override
  String usageOutput(String tokens) {
    return 'Output $tokens tokens';
  }

  @override
  String get unknownCost => 'Cost —';

  @override
  String modelRequestCount(int count) {
    return '$count model requests';
  }

  @override
  String historyLoadFailed(String error) {
    return 'Could not load history: $error';
  }

  @override
  String get noExecutionHistory => 'No execution history yet';

  @override
  String operationCount(int count) {
    return '$count operations';
  }

  @override
  String get otherRecords => 'Other records';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get initiated => 'Started';

  @override
  String get collapseHistory => 'Collapse record details';

  @override
  String get expandHistory => 'Expand record details';

  @override
  String startedAtTime(String time) {
    return 'Started at $time';
  }

  @override
  String get renameAction => 'Rename';

  @override
  String get moveAction => 'Move / Rename';

  @override
  String get moveOnlyAction => 'Move';

  @override
  String get moveAndRenameAction => 'Move and rename';

  @override
  String get uploadAction => 'Upload file';

  @override
  String get createDirectory => 'New folder';

  @override
  String get operationRecord => 'Operation record';

  @override
  String get invalidDirectoryPath => 'Invalid directory path';

  @override
  String get favoriteOutsideRoot =>
      'The favorite directory is outside the NAS root';

  @override
  String get webdavUrlParameters =>
      'The WebDAV URL cannot contain query parameters';

  @override
  String get pathOutsideConnection =>
      'The path is outside the WebDAV connection directory';

  @override
  String get invalidWebdavProperties =>
      'WebDAV did not return valid file properties';

  @override
  String get unknownFileStatus =>
      'Could not determine file status. Check WebDAV permissions';

  @override
  String get moveUnconfirmed =>
      'Move was not confirmed. Refresh the directory to verify';

  @override
  String get directoryCreationUnconfirmed =>
      'Directory creation was not confirmed';

  @override
  String get deleteUnconfirmed =>
      'Deletion was not confirmed. Refresh the directory to verify';

  @override
  String get uploadUnconfirmed =>
      'Upload was not confirmed. Refresh the directory to verify';

  @override
  String get absoluteWebdavPathRequired => 'WebDAV paths must be absolute';

  @override
  String get unsafeWebdavPath => 'The WebDAV path contains unsafe characters';

  @override
  String get networkClientClosed => 'Network client is closed';

  @override
  String get systemProxyTimeout => 'Reading the system proxy timed out';

  @override
  String get invalidSystemProxy =>
      'The system proxy returned no valid configuration';

  @override
  String get systemProxyUnsupported =>
      'Reading the system proxy is not supported on this platform';

  @override
  String get systemProxyReadFailed => 'Could not read the system proxy';

  @override
  String get environmentProxyUnsupported =>
      'Environment proxies must be unauthenticated HTTP proxies';

  @override
  String get systemProxyTypeUnsupported =>
      'The system proxy type is unsupported. Only unauthenticated HTTP proxies are supported';

  @override
  String get databaseClosed => 'Database is closed';

  @override
  String get databaseVersionTooNew => 'The database version is too new';

  @override
  String get targetFileExists => 'The target file already exists';

  @override
  String get queryingMetadata => 'Looking up movie and series metadata…';

  @override
  String get suggestionsGenerated => 'Suggestions generated';

  @override
  String get noReliableSuggestions =>
      'No reliable rename suggestions found. Add a movie title and year or a series name and season, then try again.';

  @override
  String get usageSaveFailed => 'Could not save AI usage';

  @override
  String get operationCompleted => 'Operation completed';

  @override
  String get downloading => 'Downloading…';

  @override
  String get downloadCompleted => 'Download complete';

  @override
  String get preparingExecution => 'Preparing execution';

  @override
  String directoryReadFailed(String error) {
    return 'Could not read directory: $error';
  }

  @override
  String suggestionsFailed(String error) {
    return 'Could not generate suggestions: $error';
  }

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String fileOperationStopped(String error) {
    return 'File operation stopped: $error; refresh the directory to verify the results';
  }

  @override
  String executionStopped(String error) {
    return 'Execution stopped: $error; refresh the directory to verify the results';
  }

  @override
  String remainingExecutionStopped(String error) {
    return 'Stopped: $error. Verify the results before confirming the remaining changes';
  }

  @override
  String completedItemCount(int count) {
    return 'Completed $count items';
  }

  @override
  String aiAnalyzing(int count) {
    return 'AI analysis ($count/8)';
  }

  @override
  String queryingTool(String name) {
    return 'Querying: $name';
  }

  @override
  String matchEvidence(String season, String episode, String title, String id) {
    return 'Match: season $season, episode $episode · $title\nTMDB $id';
  }

  @override
  String authenticationFailed(String code) {
    return 'Authentication failed or access denied (HTTP $code)';
  }

  @override
  String get proxyAuthenticationUnsupported =>
      'The proxy requires authentication. Only unauthenticated HTTP proxies are supported';

  @override
  String get remoteFileChanged =>
      'The file changed or the target exists. Refresh the directory to verify';

  @override
  String get rateLimited => 'Too many requests. Please try again later';

  @override
  String get networkConnectionFailed =>
      'Connection failed or timed out. Check the service URL and HTTP proxy';

  @override
  String httpStatusError(String code) {
    return 'The service returned HTTP $code';
  }

  @override
  String get operationFailed => 'Operation failed. Please try again';

  @override
  String get invalidServiceUrl =>
      'Enter a valid HTTPS URL (WebDAV also supports HTTP)';

  @override
  String get invalidProxyUrl => 'Proxy URL must use http://host:port';

  @override
  String get proxyUrlRequired => 'Enter a proxy URL';

  @override
  String get invalidAiModels => 'AI /models did not return valid JSON';

  @override
  String get aiClientClosed => 'AI client is closed';

  @override
  String get aiAlreadyRunning => 'AI analysis is already running';

  @override
  String get modelNameRequired => 'Enter an AI model name';

  @override
  String get tooManyFiles =>
      'This directory contains more than 500 files. Select a smaller directory';

  @override
  String get aiCallLimit => 'AI tool call limit exceeded';

  @override
  String get invalidAiSuggestions =>
      'AI returned no valid suggestions or reached its execution limit';

  @override
  String get missingTmdbEvidence =>
      'AI suggestions lack valid TMDB episode evidence. Please try again';

  @override
  String get tmdbTokenRequired => 'Configure a TMDB token';

  @override
  String get invalidMovieQuery => 'Invalid movie query';

  @override
  String get invalidMovieId => 'Invalid movie ID';

  @override
  String get invalidMovieDetails => 'Invalid TMDB movie details';

  @override
  String get invalidMediaType =>
      'The AI suggestion has an invalid media type. Try again';

  @override
  String get missingMovieEvidence =>
      'The AI suggestion has no verified TMDB movie evidence. Try again';

  @override
  String movieMatchEvidence(String title, String date, String id) {
    return 'Movie match: $title · $date\nTMDB $id';
  }

  @override
  String subtitleRenamedWithVideo(String name) {
    return 'Rename with video · $name';
  }

  @override
  String get invalidSeriesQuery => 'Invalid series query';

  @override
  String get invalidSeasonNumber => 'Invalid series or season number';

  @override
  String get duplicateSource => 'The same source file appears more than once';

  @override
  String get sourceAttributesChanged =>
      'Source file attributes changed. Generate suggestions again';

  @override
  String get targetConflict => 'The target conflicts with another pending file';

  @override
  String get taskAlreadyRunning => 'An organizing task is already running';

  @override
  String get sourceMissing => 'The source file no longer exists';

  @override
  String get sourceChanged => 'Source file attributes changed';

  @override
  String get targetExists => 'The target already exists';

  @override
  String get rootModificationForbidden =>
      'Cannot modify the WebDAV root directory';

  @override
  String get moveIntoSelfForbidden => 'Cannot move a directory inside itself';

  @override
  String get unsupportedFileOperation => 'Unsupported file operation';

  @override
  String get invalidFileNameEmpty =>
      'Invalid file name: the name cannot be empty';

  @override
  String get invalidFileNameControl =>
      'Invalid file name: control characters are not allowed';

  @override
  String get invalidFileNameEnding =>
      'Invalid file name: cannot end with a space or period';

  @override
  String get invalidFileNameCharacters =>
      'The file name contains invalid characters';

  @override
  String sourcePathChanged(String path) {
    return 'Source file changed: $path';
  }

  @override
  String extensionRequired(String extension) {
    return 'Keep the original extension: $extension';
  }

  @override
  String duplicateTargetName(String name) {
    return 'Duplicate target file name: $name';
  }

  @override
  String targetNameExists(String name) {
    return 'Target already exists: $name';
  }

  @override
  String invalidFileNameReserved(String name) {
    return 'Invalid file name: “$name” is not allowed';
  }

  @override
  String invalidFileNameReplace(String character, String replacement) {
    return 'Invalid file name: replace “$character” with “$replacement” or “-”';
  }

  @override
  String get compactSidebar => 'Compact sidebar';

  @override
  String get about => 'About this template';

  @override
  String get version => 'Version';

  @override
  String get openSourceLicenses => 'Third-party notices';

  @override
  String get fonts => 'Font notice';

  @override
  String get fontNotice =>
      'This app uses the MiSans font. © Xiaomi Technology Co., Ltd. Used under the MiSans Font Intellectual Property License Agreement.';

  @override
  String get runtimeEnvironment => 'Runtime environment';

  @override
  String get operatingSystem => 'Operating system';

  @override
  String get systemVersion => 'System version';

  @override
  String get dartVersion => 'Dart version';

  @override
  String get buildMode => 'Build mode';

  @override
  String get buildModeDebug => 'Debug';

  @override
  String get buildModeProfile => 'Profile';

  @override
  String get buildModeRelease => 'Release';

  @override
  String get processorCount => 'Logical processors';

  @override
  String get windowSize => 'Window size (logical pixels)';

  @override
  String get devicePixelRatio => 'Device pixel ratio';

  @override
  String get systemLocale => 'System locale';

  @override
  String get appLocale => 'App language';

  @override
  String get openDocs => 'Forui documentation';

  @override
  String get linkError => 'Could not open the link.';

  @override
  String get networkDemo => 'Network playground';

  @override
  String get mockMode => 'Offline mock';

  @override
  String get liveMode => 'Live API';

  @override
  String get empty => 'Empty';

  @override
  String get timeout => 'Timeout';

  @override
  String get serverFailure => 'Server error';

  @override
  String get reload => 'Reload';

  @override
  String get emptyNetwork => 'The request succeeded with no items.';

  @override
  String get tasks => 'Tasks';

  @override
  String get network => 'Network';

  @override
  String get minimize => 'Minimize';

  @override
  String get maximize => 'Maximize';

  @override
  String get restore => 'Restore';

  @override
  String get notFound => 'Page not found';

  @override
  String get goHome => 'Go to overview';

  @override
  String get themeColor => 'Theme color';

  @override
  String get radiusScale => 'Corner radius scale';

  @override
  String get colorNeutral => 'Neutral';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorViolet => 'Violet';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorRose => 'Rose';

  @override
  String get logs => 'Logs';

  @override
  String get searchLogs => 'Search logs';

  @override
  String get pauseLogs => 'Pause';

  @override
  String get resumeLogs => 'Resume';

  @override
  String get autoScrollLogs => 'Auto-scroll';

  @override
  String get copyVisibleLogs => 'Copy results';

  @override
  String get copyLogEntry => 'Copy log entry';

  @override
  String get clearLogView => 'Clear view';

  @override
  String get noLiveLogs => 'No logs to display';

  @override
  String get noMatchingLogs => 'No matching logs found';

  @override
  String get logCopyError => 'Could not copy logs. Please try again.';

  @override
  String logEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get exportLogs => 'Export logs';

  @override
  String get exportingLogs => 'Exporting logs…';

  @override
  String get noLogsToExport => 'No logs available to export.';

  @override
  String get logsExported => 'Log archive saved.';

  @override
  String get logsShared => 'Log archive shared.';

  @override
  String get logShareOpened =>
      'Log sharing opened. Complete the export in the system share sheet.';

  @override
  String get logExportError =>
      'Could not export logs. Check available storage and try again.';

  @override
  String get assistantTab => 'Assistant';

  @override
  String get filesTab => 'Files';

  @override
  String get assistantInputHint => 'Describe how to organize';

  @override
  String get assistantSend => 'Send';

  @override
  String get assistantStop => 'Stop';

  @override
  String get assistantNewConversation => 'New conversation';

  @override
  String get assistantEmptyTitle => 'How should this directory be organized?';

  @override
  String get assistantPromptOrganize => 'Identify and organize this directory';

  @override
  String get assistantPromptSeriesOnly =>
      'Only organize series and skip movies';

  @override
  String get assistantPromptMoviesOnly =>
      'Only organize movies and skip series';

  @override
  String get activityScan => 'Read directory';

  @override
  String activityModel(int round) {
    return 'AI analysis · round $round';
  }

  @override
  String activitySearchMovie(String query) {
    return 'Search movies for \"$query\"';
  }

  @override
  String activitySearchMovieYear(String query, int year) {
    return 'Search movies for \"$query\" · $year';
  }

  @override
  String activitySearchTv(String query) {
    return 'Search series for \"$query\"';
  }

  @override
  String get activityGetMovie => 'Verify movie details';

  @override
  String activityMovieVerified(String title) {
    return 'Verify movie \"$title\"';
  }

  @override
  String activitySeason(int season) {
    return 'Load season $season';
  }

  @override
  String activitySeasonOf(String title, int season) {
    return 'Load \"$title\" season $season';
  }

  @override
  String get activityListDirectory => 'Review directory listing';

  @override
  String activityEntries(int count) {
    return '$count entries';
  }

  @override
  String activityCandidates(int count) {
    return '$count candidates';
  }

  @override
  String activityEpisodes(int count) {
    return '$count episodes';
  }

  @override
  String get activityStopped => 'Stopped';

  @override
  String get runWorking => 'Working';

  @override
  String runDone(int count) {
    return 'Completed $count lookups';
  }

  @override
  String get runFailed => 'Did not finish';

  @override
  String get runStopped => 'Stopped';

  @override
  String runSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String get showActivity => 'Show steps';

  @override
  String get hideActivity => 'Hide steps';

  @override
  String get replyPlan => 'The plan is ready. Review it before executing.';

  @override
  String get replyPlanRevised => 'Updated the plan with your new requirements.';

  @override
  String planVersion(int version) {
    return 'Plan · version $version';
  }

  @override
  String planMovies(int count) {
    return '$count movies';
  }

  @override
  String planSeries(int count) {
    return '$count series';
  }

  @override
  String planChanges(int count) {
    return '$count files will change';
  }

  @override
  String planUnchanged(int count) {
    return '$count unchanged';
  }

  @override
  String get planSuperseded => 'Replaced';

  @override
  String planRemaining(int count) {
    return '$count items not executed';
  }

  @override
  String get viewChanges => 'Review changes';

  @override
  String get planPanelTitle => 'Plan';

  @override
  String get noPlanYet => 'No plan yet';

  @override
  String get movieLabel => 'Movie';

  @override
  String get seriesLabel => 'Series';

  @override
  String get otherFiles => 'Other files';

  @override
  String seasonLabel(int season) {
    return 'Season $season';
  }

  @override
  String get assistantPromptFolders =>
      'Create a folder per title and group seasons';

  @override
  String get folderLayout => 'Folders';

  @override
  String get folderMovies => 'Folder per movie';

  @override
  String get folderSeries => 'Folder per series';

  @override
  String get folderSeasons => 'Folder per season';

  @override
  String planFolders(int count) {
    return '$count new folders';
  }

  @override
  String get replyLayout => 'Updated the folder structure.';

  @override
  String get newFolderBadge => 'New';

  @override
  String get executeOrganizeDetail =>
      'New folders will be created and files moved or renamed as planned; original folders remain. Execution stops on failure and never overwrites existing files.';
}
