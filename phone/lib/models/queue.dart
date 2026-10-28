class QueueJob {
  const QueueJob({
    required this.id,
    required this.label,
    required this.status,
    required this.position,
    this.error,
  });

  final String id;
  final String label;
  final String status;
  final int position;
  final String? error;

  factory QueueJob.fromJson(Map<String, dynamic> json) {
    return QueueJob(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      position: (json['position'] as num?)?.toInt() ?? 0,
      error: json['error']?.toString(),
    );
  }
}

class QueueStatus {
  const QueueStatus({
    required this.pending,
    required this.totalPending,
    required this.totalActive,
    this.active,
    this.history = const [],
  });

  final List<QueueJob> pending;
  final List<QueueJob> history;
  final int totalPending;
  final int totalActive;
  final QueueJob? active;

  bool get isBusy => totalActive > 0 || totalPending > 0;

  factory QueueStatus.fromJson(Map<String, dynamic> json) {
    final active = json['active'];
    return QueueStatus(
      pending: (json['pending'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(QueueJob.fromJson)
          .toList(),
      history: (json['history'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(QueueJob.fromJson)
          .toList(),
      totalPending: (json['total_pending'] as num?)?.toInt() ?? 0,
      totalActive: (json['total_active'] as num?)?.toInt() ?? 0,
      active: active is Map<String, dynamic> ? QueueJob.fromJson(active) : null,
    );
  }
}
