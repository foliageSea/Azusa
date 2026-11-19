/// A file or directory on a connected file server.
class FileServerEntry {
  const FileServerEntry(
    this.path,
    this.directory, {
    this.versionToken,
    this.size,
    this.modified,
  });

  final String path;
  final bool directory;

  /// Opaque version marker scoped to this entry and server, when available.
  final String? versionToken;
  final String? modified;
  final int? size;

  String get name => Uri.decodeComponent(
    path.split('/').where((segment) => segment.isNotEmpty).last,
  );

  String? get fingerprint =>
      versionToken ??
      (size == null && modified == null ? null : '$size:$modified');
}

/// A session with a single file server. Paths are absolute, with each segment
/// percent-encoded and a trailing slash on directories. Implementations must
/// reject paths outside their configured root.
abstract class FileServerClient {
  String get root;
  String normalize(String path);

  /// Lists immediate children for display; may omit hidden or system entries.
  Future<List<FileServerEntry>> list(String path);

  /// Lists all immediate children, including hidden entries. Throws if the
  /// server response does not establish a complete list; used before deletion.
  Future<List<FileServerEntry>> listAll(String path);

  /// Returns null only if the server confirms the entry does not exist.
  Future<FileServerEntry?> stat(String path);
  Future<bool> exists(String path) async => await stat(path) != null;

  /// Moves an entry without overwriting a destination. If the backend supports
  /// a conditional move for [versionToken], it must enforce that precondition.
  Future<void> move(String from, String to, {String? versionToken});
  Future<void> mkdir(String path);
  Future<void> remove(String path);

  /// Creates a file without overwriting an existing entry.
  Future<void> upload(String path, Stream<List<int>> bytes, int length);
  Future<void> download(String path, String destination);
  void close();
}

/// Identifies a directory-favorites namespace without requiring consumers to
/// interpret the endpoint. Adapters must namespace new endpoint formats by
/// protocol and keep credentials out of this value.
typedef FileServerScope = ({String endpoint, String username, String root});
