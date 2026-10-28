import 'document.dart';

class Stats {
  const Stats({
    required this.totalDocuments,
    required this.countByType,
    required this.countByMonth,
    required this.recentDocuments,
    required this.expiringSoonCount,
    required this.overdueCount,
  });

  final int totalDocuments;
  final Map<String, int> countByType;
  final Map<String, int> countByMonth;
  final List<DocumentModel> recentDocuments;
  final int expiringSoonCount;
  final int overdueCount;

  int get alertCount => expiringSoonCount + overdueCount;

  factory Stats.fromJson(Map<String, dynamic> json) {
    return Stats(
      totalDocuments: (json['total_documents'] as num?)?.toInt() ?? 0,
      countByType: _intMap(json['count_by_type']),
      countByMonth: _intMap(json['count_by_month']),
      recentDocuments: (json['recent_documents'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DocumentModel.fromJson)
          .toList(),
      expiringSoonCount: (json['expiring_soon_count'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, int> _intMap(dynamic value) {
    if (value is! Map) return const {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        val is num ? val.toInt() : int.tryParse(val.toString()) ?? 0,
      ),
    );
  }
}

class Health {
  const Health({
    required this.status,
    required this.llmLoaded,
    required this.embeddingModelLoaded,
    required this.totalDocuments,
    this.version,
  });

  final String status;
  final bool llmLoaded;
  final bool embeddingModelLoaded;
  final int totalDocuments;
  final String? version;

  factory Health.fromJson(Map<String, dynamic> json) {
    return Health(
      status: (json['status'] ?? 'unknown').toString(),
      llmLoaded: json['llm_loaded'] == true,
      embeddingModelLoaded: json['embedding_model_loaded'] == true,
      totalDocuments: (json['total_documents'] as num?)?.toInt() ?? 0,
      version: json['version']?.toString(),
    );
  }
}
