enum FailureKind { network, timeout, server, storage, invalidData, cancelled }

class AppException implements Exception {
  const AppException(this.kind, [this.cause]);
  final FailureKind kind;
  final Object? cause;
  @override
  String toString() => 'AppException(${kind.name})';
}
