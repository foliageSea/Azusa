enum AgentActivityKind {
  scan,
  model,
  searchMovie,
  getMovie,
  searchTv,
  getSeason,
  listDirectory,
}

enum AgentActivityStatus { running, succeeded, failed, stopped }

/// A real step taken while generating suggestions, reported as it happens.
class AgentActivity {
  const AgentActivity({
    required this.key,
    required this.kind,
    this.status = AgentActivityStatus.running,
    this.subject,
    this.number,
    this.count,
    this.title,
    this.date,
    this.error,
  });

  /// Identifies the step within one run, so later updates replace it.
  final String key;
  final AgentActivityKind kind;
  final AgentActivityStatus status;
  final String? subject, title, date, error;
  final int? number, count;

  AgentActivity copyWith({
    AgentActivityStatus? status,
    int? count,
    String? title,
    String? date,
    String? error,
  }) => AgentActivity(
    key: key,
    kind: kind,
    status: status ?? this.status,
    subject: subject,
    number: number,
    count: count ?? this.count,
    title: title ?? this.title,
    date: date ?? this.date,
    error: error ?? this.error,
  );

  AgentActivity succeed({int? count, String? title, String? date}) => copyWith(
    status: AgentActivityStatus.succeeded,
    count: count,
    title: title,
    date: date,
  );

  AgentActivity fail(String error) =>
      copyWith(status: AgentActivityStatus.failed, error: error);
}
