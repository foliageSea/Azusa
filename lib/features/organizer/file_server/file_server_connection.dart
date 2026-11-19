/// Protocol-specific configuration for connecting to a file server.
abstract class FileServerConnection {
  String get id;
  String get name;
  String get protocol;
}
