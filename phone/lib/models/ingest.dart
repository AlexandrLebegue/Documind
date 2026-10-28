class IngestMark {
  const IngestMark({
    required this.sha256,
    required this.verdict,
    required this.firstSeen,
    required this.updatedAt,
    required this.hasFile,
    this.docId,
    this.reason,
    this.source,
    this.originPath,
    this.filename,
    this.confidence,
    this.verdictAt,
    this.title,
  });

  final String sha256;
  final String verdict;
  final DateTime firstSeen;
  final DateTime updatedAt;
  final bool hasFile;
  final String? docId;
  final String? reason;
  final String? source;
  final String? originPath;
  final String? filename;
  final double? confidence;
  final DateTime? verdictAt;
  final String? title;

  String get label => filename ?? title ?? sha256.substring(0, 12);

  factory IngestMark.fromJson(Map<String, dynamic> json) {
    return IngestMark(
      sha256: (json['sha256'] ?? '').toString(),
      verdict: (json['verdict'] ?? 'error').toString(),
      firstSeen:
          DateTime.tryParse((json['first_seen'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
      hasFile: json['has_file'] == true,
      docId: json['doc_id']?.toString(),
      reason: json['reason']?.toString(),
      source: json['source']?.toString(),
      originPath: json['origin_path']?.toString(),
      filename: json['filename']?.toString(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      verdictAt: DateTime.tryParse((json['verdict_at'] ?? '').toString()),
      title: json['title']?.toString(),
    );
  }
}

class IngestMarksResponse {
  const IngestMarksResponse({
    required this.marks,
    required this.total,
    required this.counts,
  });

  final List<IngestMark> marks;
  final int total;
  final Map<String, int> counts;

  factory IngestMarksResponse.fromJson(Map<String, dynamic> json) {
    return IngestMarksResponse(
      marks: (json['marks'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(IngestMark.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      counts: (json['counts'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
      ),
    );
  }
}
