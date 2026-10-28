import 'document.dart';

class ProcedureRequiredDocument {
  const ProcedureRequiredDocument({
    required this.docType,
    required this.label,
    this.description,
  });

  final String docType;
  final String label;
  final String? description;

  factory ProcedureRequiredDocument.fromJson(Map<String, dynamic> json) {
    return ProcedureRequiredDocument(
      docType: (json['doc_type'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      description: json['description']?.toString(),
    );
  }
}

class Procedure {
  const Procedure({
    required this.id,
    required this.name,
    required this.procedureType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.requiredDocuments = const [],
    this.remarks,
  });

  final String id;
  final String name;
  final String procedureType;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  final List<ProcedureRequiredDocument> requiredDocuments;
  final String? remarks;

  factory Procedure.fromJson(Map<String, dynamic> json) {
    return Procedure(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Procédure').toString(),
      procedureType: (json['procedure_type'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
      description: json['description']?.toString(),
      requiredDocuments: (json['required_documents'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProcedureRequiredDocument.fromJson)
          .toList(),
      remarks: json['remarks']?.toString(),
    );
  }
}

class MatchedDocument {
  const MatchedDocument({
    required this.requiredDocType,
    required this.requiredLabel,
    required this.found,
    this.document,
  });

  final String requiredDocType;
  final String requiredLabel;
  final bool found;
  final DocumentModel? document;

  factory MatchedDocument.fromJson(Map<String, dynamic> json) {
    final doc = json['document'];
    return MatchedDocument(
      requiredDocType: (json['required_doc_type'] ?? '').toString(),
      requiredLabel: (json['required_label'] ?? '').toString(),
      found: json['found'] == true,
      document: doc is Map<String, dynamic>
          ? DocumentModel.fromJson(doc)
          : null,
    );
  }
}

class ProcedureExecution {
  const ProcedureExecution({
    required this.id,
    required this.procedureId,
    required this.personName,
    required this.matchedDocuments,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String procedureId;
  final String personName;
  final List<MatchedDocument> matchedDocuments;
  final String status;
  final DateTime createdAt;

  factory ProcedureExecution.fromJson(Map<String, dynamic> json) {
    return ProcedureExecution(
      id: (json['id'] ?? '').toString(),
      procedureId: (json['procedure_id'] ?? '').toString(),
      personName: (json['person_name'] ?? '').toString(),
      matchedDocuments: (json['matched_documents'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MatchedDocument.fromJson)
          .toList(),
      status: (json['status'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
