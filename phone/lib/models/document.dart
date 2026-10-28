class DocumentModel {
  const DocumentModel({
    required this.id,
    required this.filename,
    required this.filepath,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.textContent,
    this.docType,
    this.emetteur,
    this.docDate,
    this.montant,
    this.reference,
    this.destinataire,
    this.resume,
    this.tags = const [],
    this.dateExpiration,
    this.dateEcheance,
    this.parentId,
    this.pageStart,
    this.pageEnd,
    this.pagesDone = 0,
    this.pagesTotal = 0,
    this.ocrBackend,
    this.ocrSeconds,
    this.llmSeconds,
    this.totalSeconds,
    this.errorMessage,
  });

  final String id;
  final String filename;
  final String filepath;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? title;
  final String? textContent;
  final String? docType;
  final String? emetteur;
  final String? docDate;
  final double? montant;
  final String? reference;
  final String? destinataire;
  final String? resume;
  final List<String> tags;
  final String? dateExpiration;
  final String? dateEcheance;
  final String? parentId;
  final int? pageStart;
  final int? pageEnd;
  final int pagesDone;
  final int pagesTotal;
  final String? ocrBackend;
  final double? ocrSeconds;
  final double? llmSeconds;
  final double? totalSeconds;
  final String? errorMessage;

  String get displayTitle =>
      (title?.trim().isNotEmpty ?? false) ? title! : filename;

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'processing' || status == 'queued';
  bool get isImage {
    final ext = filename.split('.').last.toLowerCase();
    return const ['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(ext);
  }

  bool get isPdf => filename.toLowerCase().endsWith('.pdf');

  double get progress {
    if (pagesTotal <= 0) return 0;
    return (pagesDone / pagesTotal).clamp(0.0, 1.0);
  }

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: (json['id'] ?? '').toString(),
      filename: (json['filename'] ?? '').toString(),
      filepath: (json['filepath'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      updatedAt: _date(json['updated_at']) ?? DateTime.now(),
      title: _string(json['title']),
      textContent: _string(json['text_content']),
      docType: _string(json['doc_type']),
      emetteur: _string(json['emetteur']),
      docDate: _string(json['doc_date']),
      montant: _double(json['montant']),
      reference: _string(json['reference']),
      destinataire: _string(json['destinataire']),
      resume: _string(json['resume']),
      tags: _list(json['tags']),
      dateExpiration: _string(json['date_expiration']),
      dateEcheance: _string(json['date_echeance']),
      parentId: _string(json['parent_id']),
      pageStart: _int(json['page_start']),
      pageEnd: _int(json['page_end']),
      pagesDone: _int(json['pages_done']) ?? 0,
      pagesTotal: _int(json['pages_total']) ?? 0,
      ocrBackend: _string(json['ocr_backend']),
      ocrSeconds: _double(json['ocr_seconds']),
      llmSeconds: _double(json['llm_seconds']),
      totalSeconds: _double(json['total_seconds']),
      errorMessage: _string(json['error_message']),
    );
  }

  Map<String, dynamic> toUpdateJson() => {
    if (title != null) 'title': title,
    if (docType != null) 'doc_type': docType,
    if (emetteur != null) 'emetteur': emetteur,
    if (docDate != null) 'doc_date': docDate,
    if (montant != null) 'montant': montant,
    if (reference != null) 'reference': reference,
    if (destinataire != null) 'destinataire': destinataire,
    if (resume != null) 'resume': resume,
    'tags': tags,
    if (dateExpiration != null) 'date_expiration': dateExpiration,
    if (dateEcheance != null) 'date_echeance': dateEcheance,
  };

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static double? _double(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static List<String> _list(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }
}

class DocumentPage {
  const DocumentPage({
    required this.documents,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<DocumentModel> documents;
  final int total;
  final int limit;
  final int offset;

  factory DocumentPage.fromJson(Map<String, dynamic> json) {
    final docs = (json['documents'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DocumentModel.fromJson)
        .toList();
    return DocumentPage(
      documents: docs,
      total: (json['total'] as num?)?.toInt() ?? docs.length,
      limit: (json['limit'] as num?)?.toInt() ?? docs.length,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}
