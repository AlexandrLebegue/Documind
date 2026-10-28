import 'document.dart';

class AlertItem {
  const AlertItem({
    required this.document,
    required this.alertType,
    required this.targetDate,
    required this.daysRemaining,
    required this.urgency,
  });

  final DocumentModel document;
  final String alertType;
  final String targetDate;
  final int daysRemaining;
  final String urgency;

  bool get isExpiration => alertType == 'expiration';

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      document: DocumentModel.fromJson(
        (json['document'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      alertType: (json['alert_type'] ?? 'expiration').toString(),
      targetDate: (json['target_date'] ?? '').toString(),
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
      urgency: (json['urgency'] ?? 'info').toString(),
    );
  }
}

class AlertsResponse {
  const AlertsResponse({
    required this.alerts,
    required this.total,
    required this.expiringCount,
    required this.overdueCount,
    required this.upcomingPayments,
  });

  final List<AlertItem> alerts;
  final int total;
  final int expiringCount;
  final int overdueCount;
  final int upcomingPayments;

  factory AlertsResponse.fromJson(Map<String, dynamic> json) {
    return AlertsResponse(
      alerts: (json['alerts'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AlertItem.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      expiringCount: (json['expiring_count'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
      upcomingPayments: (json['upcoming_payments'] as num?)?.toInt() ?? 0,
    );
  }
}

class RenewalSuggestion {
  const RenewalSuggestion({
    required this.document,
    required this.reason,
    this.suggestedProcedureId,
    this.suggestedProcedureName,
  });

  final DocumentModel document;
  final String reason;
  final String? suggestedProcedureId;
  final String? suggestedProcedureName;

  factory RenewalSuggestion.fromJson(Map<String, dynamic> json) {
    final procedure = json['suggested_procedure'] as Map<String, dynamic>?;
    return RenewalSuggestion(
      document: DocumentModel.fromJson(
        (json['document'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      reason: (json['reason'] ?? '').toString(),
      suggestedProcedureId: procedure?['id']?.toString(),
      suggestedProcedureName: procedure?['name']?.toString(),
    );
  }
}

class GapAlert {
  const GapAlert({
    required this.docType,
    required this.expectedDate,
    required this.message,
    this.destinataire,
    this.lastSeenDate,
  });

  final String docType;
  final String expectedDate;
  final String message;
  final String? destinataire;
  final String? lastSeenDate;

  factory GapAlert.fromJson(Map<String, dynamic> json) {
    return GapAlert(
      docType: (json['doc_type'] ?? '').toString(),
      expectedDate: (json['expected_date'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      destinataire: json['destinataire']?.toString(),
      lastSeenDate: json['last_seen_date']?.toString(),
    );
  }
}
