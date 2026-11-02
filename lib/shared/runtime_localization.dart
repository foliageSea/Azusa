import '../l10n/generated/app_localizations.dart';
import '../l10n/generated/app_localizations_zh.dart';

/// Localizes legacy service messages at the presentation boundary. Internal
/// status checks and stored history retain their original, stable format.
String localizeRuntimeMessage(AppLocalizations l, String message) {
  if (l.localeName.startsWith('zh') || message.isEmpty) return message;
  final zh = AppLocalizationsZh();
  final messages = <String, String>{
    zh.invalidDirectoryPath: l.invalidDirectoryPath,
    zh.favoriteOutsideRoot: l.favoriteOutsideRoot,
    zh.webdavUrlParameters: l.webdavUrlParameters,
    zh.pathOutsideConnection: l.pathOutsideConnection,
    zh.invalidWebdavProperties: l.invalidWebdavProperties,
    zh.unknownFileStatus: l.unknownFileStatus,
    zh.moveUnconfirmed: l.moveUnconfirmed,
    zh.directoryCreationUnconfirmed: l.directoryCreationUnconfirmed,
    zh.deleteUnconfirmed: l.deleteUnconfirmed,
    zh.uploadUnconfirmed: l.uploadUnconfirmed,
    zh.absoluteWebdavPathRequired: l.absoluteWebdavPathRequired,
    zh.unsafeWebdavPath: l.unsafeWebdavPath,
    zh.networkClientClosed: l.networkClientClosed,
    zh.systemProxyTimeout: l.systemProxyTimeout,
    zh.invalidSystemProxy: l.invalidSystemProxy,
    zh.systemProxyUnsupported: l.systemProxyUnsupported,
    zh.systemProxyReadFailed: l.systemProxyReadFailed,
    zh.environmentProxyUnsupported: l.environmentProxyUnsupported,
    zh.systemProxyTypeUnsupported: l.systemProxyTypeUnsupported,
    zh.databaseClosed: l.databaseClosed,
    zh.databaseVersionTooNew: l.databaseVersionTooNew,
    zh.targetFileExists: l.targetFileExists,
    zh.queryingMetadata: l.queryingMetadata,
    zh.suggestionsGenerated: l.suggestionsGenerated,
    zh.noReliableSuggestions: l.noReliableSuggestions,
    zh.usageSaveFailed: l.usageSaveFailed,
    zh.operationCompleted: l.operationCompleted,
    zh.downloading: l.downloading,
    zh.downloadCompleted: l.downloadCompleted,
    zh.preparingExecution: l.preparingExecution,
    zh.proxyAuthenticationUnsupported: l.proxyAuthenticationUnsupported,
    zh.remoteFileChanged: l.remoteFileChanged,
    zh.rateLimited: l.rateLimited,
    zh.networkConnectionFailed: l.networkConnectionFailed,
    zh.operationFailed: l.operationFailed,
    zh.invalidServiceUrl: l.invalidServiceUrl,
    zh.invalidProxyUrl: l.invalidProxyUrl,
    zh.proxyUrlRequired: l.proxyUrlRequired,
    zh.invalidAiModels: l.invalidAiModels,
    zh.aiClientClosed: l.aiClientClosed,
    zh.aiAlreadyRunning: l.aiAlreadyRunning,
    zh.modelNameRequired: l.modelNameRequired,
    zh.tooManyFiles: l.tooManyFiles,
    zh.aiCallLimit: l.aiCallLimit,
    zh.invalidAiSuggestions: l.invalidAiSuggestions,
    zh.missingTmdbEvidence: l.missingTmdbEvidence,
    zh.invalidMovieQuery: l.invalidMovieQuery,
    zh.invalidMovieId: l.invalidMovieId,
    zh.invalidMovieDetails: l.invalidMovieDetails,
    zh.invalidMediaType: l.invalidMediaType,
    zh.missingMovieEvidence: l.missingMovieEvidence,
    zh.tmdbTokenRequired: l.tmdbTokenRequired,
    zh.invalidSeriesQuery: l.invalidSeriesQuery,
    zh.invalidSeasonNumber: l.invalidSeasonNumber,
    zh.duplicateSource: l.duplicateSource,
    zh.sourceAttributesChanged: l.sourceAttributesChanged,
    zh.targetConflict: l.targetConflict,
    zh.taskAlreadyRunning: l.taskAlreadyRunning,
    zh.sourceMissing: l.sourceMissing,
    zh.sourceChanged: l.sourceChanged,
    zh.targetExists: l.targetExists,
    zh.rootModificationForbidden: l.rootModificationForbidden,
    zh.moveIntoSelfForbidden: l.moveIntoSelfForbidden,
    zh.unsupportedFileOperation: l.unsupportedFileOperation,
    zh.invalidFileNameEmpty: l.invalidFileNameEmpty,
    zh.invalidFileNameControl: l.invalidFileNameControl,
    zh.invalidFileNameEnding: l.invalidFileNameEnding,
    zh.invalidFileNameCharacters: l.invalidFileNameCharacters,
  };
  final exact = messages[message];
  if (exact != null) return exact;
  final usageSuffix = '；${zh.usageSaveFailed}';
  if (message.endsWith(usageSuffix)) {
    return '${localizeRuntimeMessage(l, message.substring(0, message.length - usageSuffix.length))}; ${l.usageSaveFailed}';
  }

  // Match translated templates rather than replacing text inside user data
  // (file names and paths must never be translated).
  String? template(String source, String Function(List<String>) translate) {
    final parts = source.split(RegExp(r'\{\d+\}'));
    final pattern = parts.map(RegExp.escape).join('([\\s\\S]*?)');
    final match = RegExp('^$pattern\$').firstMatch(message);
    return match == null
        ? null
        : translate([
            for (var i = 1; i <= match.groupCount; i++) match.group(i)!,
          ]);
  }

  String nested(String text) => localizeRuntimeMessage(l, text);
  return template(
        zh.directoryReadFailed('{0}'),
        (a) => l.directoryReadFailed(nested(a[0])),
      ) ??
      template(
        zh.suggestionsFailed('{0}'),
        (a) => l.suggestionsFailed(nested(a[0])),
      ) ??
      template(
        zh.downloadFailed('{0}'),
        (a) => l.downloadFailed(nested(a[0])),
      ) ??
      template(
        zh.fileOperationStopped('{0}'),
        (a) => l.fileOperationStopped(nested(a[0])),
      ) ??
      template(
        zh.executionStopped('{0}'),
        (a) => l.executionStopped(nested(a[0])),
      ) ??
      template(
        zh.remainingExecutionStopped('{0}'),
        (a) => l.remainingExecutionStopped(nested(a[0])),
      ) ??
      template(
        zh.authenticationFailed('{0}'),
        (a) => l.authenticationFailed(a[0]),
      ) ??
      template(zh.httpStatusError('{0}'), (a) => l.httpStatusError(a[0])) ??
      template(zh.queryingTool('{0}'), (a) => l.queryingTool(a[0])) ??
      template(zh.sourcePathChanged('{0}'), (a) => l.sourcePathChanged(a[0])) ??
      template(zh.extensionRequired('{0}'), (a) => l.extensionRequired(a[0])) ??
      template(
        zh.duplicateTargetName('{0}'),
        (a) => l.duplicateTargetName(a[0]),
      ) ??
      template(zh.targetNameExists('{0}'), (a) => l.targetNameExists(a[0])) ??
      template(
        zh.invalidFileNameReserved('{0}'),
        (a) => l.invalidFileNameReserved(a[0]),
      ) ??
      template(
        zh.invalidFileNameReplace('{0}', '{1}'),
        (a) => l.invalidFileNameReplace(a[0], a[1]),
      ) ??
      template(
        zh.movieMatchEvidence('{0}', '{1}', '{2}'),
        (a) => l.movieMatchEvidence(a[0], a[1], a[2]),
      ) ??
      template(
        zh.subtitleRenamedWithVideo('{0}'),
        (a) => l.subtitleRenamedWithVideo(a[0]),
      ) ??
      template(
        zh.matchEvidence('{0}', '{1}', '{2}', '{3}'),
        (a) => l.matchEvidence(a[0], a[1], a[2], a[3]),
      ) ??
      _numericTemplate(
        message,
        RegExp(r'^已完成 (\d+) 项$'),
        l.completedItemCount,
      ) ??
      _numericTemplate(message, RegExp(r'^AI 分析中（(\d+)/8）$'), l.aiAnalyzing) ??
      message;
}

String? _numericTemplate(
  String message,
  RegExp pattern,
  String Function(int) translate,
) {
  final match = pattern.firstMatch(message);
  return match == null ? null : translate(int.parse(match.group(1)!));
}
