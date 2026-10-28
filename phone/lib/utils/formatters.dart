import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';

class DocTypeStyle {
  const DocTypeStyle(this.label, this.color, this.background);
  final String label;
  final Color color;
  final Color background;
}

const _docTypeStyles = <String, DocTypeStyle>{
  'facture': DocTypeStyle('Facture', Color(0xFF2E75B6), Color(0xFFDBEAFE)),
  'fiche_de_paie': DocTypeStyle(
    'Bulletin de paie',
    Color(0xFF059669),
    Color(0xFFD1FAE5),
  ),
  'avis_imposition': DocTypeStyle(
    'Avis d’imposition',
    Color(0xFF0891B2),
    Color(0xFFCFFAFE),
  ),
  'contrat': DocTypeStyle('Contrat', Color(0xFF7C3AED), Color(0xFFEDE9FE)),
  'attestation': DocTypeStyle(
    'Attestation',
    Color(0xFFD97706),
    Color(0xFFFEF3C7),
  ),
  'courrier': DocTypeStyle('Courrier', Color(0xFFDC2626), Color(0xFFFEE2E2)),
  'banque': DocTypeStyle('Banque', Color(0xFFBE185D), Color(0xFFFCE7F3)),
  'quittance': DocTypeStyle('Quittance', Color(0xFF4F46E5), Color(0xFFE0E7FF)),
  'identite': DocTypeStyle('Identité', Color(0xFF0D9488), Color(0xFFCCFBF1)),
  'scolarite': DocTypeStyle('Scolarité', Color(0xFFB45309), Color(0xFFFFEDD5)),
  'sante': DocTypeStyle('Santé', Color(0xFFBE123C), Color(0xFFFFE4E6)),
  'logement': DocTypeStyle('Logement', Color(0xFF4D7C0F), Color(0xFFECFCCB)),
  'emploi': DocTypeStyle('Emploi', Color(0xFF4338CA), Color(0xFFE0E7FF)),
  'administratif': DocTypeStyle(
    'Administratif',
    Color(0xFF475569),
    Color(0xFFE2E8F0),
  ),
  'autre': DocTypeStyle('Autre', Color(0xFF6B7280), Color(0xFFF3F4F6)),
};

const _legacyAliases = <String, String>{
  'releve_bancaire': 'banque',
  'bulletin_de_paie': 'fiche_de_paie',
  'bulletin_de_salaire': 'fiche_de_paie',
  'rib': 'banque',
  'cni': 'identite',
  'passeport': 'identite',
};

String resolveDocType(String? type) {
  if (type == null || type.isEmpty) return 'autre';
  return _legacyAliases[type] ?? type;
}

DocTypeStyle docTypeStyle(String? type) =>
    _docTypeStyles[resolveDocType(type)] ?? _docTypeStyles['autre']!;

String docTypeLabel(String? type) => docTypeStyle(type).label;

List<MapEntry<String, String>> get docTypeOptions => _docTypeStyles.entries
    .map((entry) => MapEntry(entry.key, entry.value.label))
    .toList();

const procedureTypeLabels = <String, String>{
  'administrative': 'Administrative',
  'contrat': 'Contrat',
  'bancaire': 'Bancaire',
  'sante': 'Santé',
  'emploi': 'Emploi',
  'immobilier': 'Immobilier',
};

const procedureTypeColors = <String, (Color, Color)>{
  'administrative': (Color(0xFF2E75B6), Color(0xFFDBEAFE)),
  'contrat': (Color(0xFF7C3AED), Color(0xFFEDE9FE)),
  'bancaire': (Color(0xFF059669), Color(0xFFD1FAE5)),
  'sante': (Color(0xFFDC2626), Color(0xFFFEE2E2)),
  'emploi': (Color(0xFFD97706), Color(0xFFFEF3C7)),
  'immobilier': (Color(0xFF0891B2), Color(0xFFCFFAFE)),
};

const _expirableTypes = {
  'identite',
  'sante',
  'logement',
  'emploi',
  'scolarite',
  'contrat',
  'attestation',
};

bool isExpirableType(String? type) =>
    _expirableTypes.contains(resolveDocType(type));

DateTime? parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed;
  return DateFormat('dd/MM/yyyy').parseLoose(value);
}

String formatDate(String? value, {String fallback = '—'}) {
  final date = parseDate(value);
  if (date == null) return fallback;
  return DateFormat('d MMM y', 'fr_FR').format(date);
}

String formatLongDate(String? value, {String fallback = '—'}) {
  final date = parseDate(value);
  if (date == null) return fallback;
  return DateFormat('d MMMM y', 'fr_FR').format(date);
}

String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  return DateFormat('d MMM y · HH:mm', 'fr_FR').format(date.toLocal());
}

String formatShortDateTime(String? value) {
  final date = parseDate(value);
  if (date == null) return '—';
  return DateFormat('dd/MM/yy HH:mm', 'fr_FR').format(date.toLocal());
}

String formatMoney(double? value, {String fallback = ''}) {
  if (value == null) return fallback;
  return NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(value);
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
}

int daysUntil(String? value) {
  final date = parseDate(value);
  if (date == null) return 0;
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final target = DateTime(date.year, date.month, date.day);
  return target.difference(start).inDays;
}

Color urgencyColor(String urgency) => switch (urgency) {
  'critical' => AppColors.danger,
  'warning' => AppColors.warning,
  _ => AppColors.info,
};

Color urgencyBackground(String urgency) => switch (urgency) {
  'critical' => AppColors.dangerBg,
  'warning' => AppColors.warningBg,
  _ => const Color(0xFFDBEAFE),
};

String urgencyLabel(String urgency) => switch (urgency) {
  'critical' => 'Urgent',
  'warning' => 'Bientôt',
  _ => 'À surveiller',
};
