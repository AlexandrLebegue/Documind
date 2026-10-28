import 'package:flutter/material.dart';

import '../models/document.dart';
import '../screens/document_detail_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import 'badges.dart';

class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    this.view = DocumentViewMode.grid,
    this.heroTag,
  });

  final DocumentModel document;
  final DocumentViewMode view;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final content = view == DocumentViewMode.grid
        ? _GridCard(document: document)
        : _ListCard(document: document);
    final tag = heroTag ?? 'document-${document.id}';
    return Hero(
      tag: tag,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: () => Navigator.of(context).push(
            slideFadeRoute(
              DocumentDetailScreen(documentId: document.id, heroTag: tag),
              name: 'document/${document.id}',
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

enum DocumentViewMode { grid, list }

class _ListCard extends StatelessWidget {
  const _ListCard({required this.document});

  final DocumentModel document;

  @override
  Widget build(BuildContext context) {
    final date = formatDate(document.docDate);
    final money = formatMoney(document.montant);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.beige100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 21,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (document.emetteur != null || date != '—') ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (document.emetteur != null) document.emetteur!,
                      if (date != '—') date,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DocTypeBadge(type: document.docType),
                    if (_expiryLabel(document) != null)
                      AlertBadge(
                        urgency: _expiryUrgency(document),
                        label: _expiryLabel(document),
                      ),
                    if (document.dateEcheance != null &&
                        _echeanceLabel(document) != null)
                      AlertBadge(
                        urgency: _echeanceUrgency(document),
                        label: _echeanceLabel(document),
                      ),
                    if (document.status != 'ready')
                      StatusBadge(status: document.status),
                  ],
                ),
                if (document.isProcessing && document.pagesTotal > 0) ...[
                  const SizedBox(height: 8),
                  _OcrProgress(document: document),
                ],
              ],
            ),
          ),
          if (money.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              money,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({required this.document});

  final DocumentModel document;

  @override
  Widget build(BuildContext context) {
    final date = formatDate(document.docDate);
    final money = formatMoney(document.montant);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              DocTypeBadge(type: document.docType),
              if (_expiryLabel(document) != null)
                AlertBadge(
                  urgency: _expiryUrgency(document),
                  label: _expiryLabel(document),
                ),
              if (document.dateEcheance != null &&
                  _echeanceLabel(document) != null)
                AlertBadge(
                  urgency: _echeanceUrgency(document),
                  label: _echeanceLabel(document),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            document.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (document.emetteur != null || date != '—') ...[
            const SizedBox(height: 4),
            Text(
              [
                if (document.emetteur != null) document.emetteur!,
                if (date != '—') date,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
          if (document.resume != null) ...[
            const SizedBox(height: 7),
            Text(
              document.resume!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppColors.muted,
              ),
            ),
          ],
          const Spacer(),
          if (document.isProcessing && document.pagesTotal > 0)
            _OcrProgress(document: document),
          if (document.status != 'ready' && !document.isProcessing) ...[
            const SizedBox(height: 6),
            StatusBadge(status: document.status),
          ],
          if (money.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 7),
            Text(
              money,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OcrProgress extends StatelessWidget {
  const _OcrProgress({required this.document});

  final DocumentModel document;

  @override
  Widget build(BuildContext context) {
    final percent = (document.progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'OCR page ${document.pagesDone}/${document.pagesTotal}',
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ),
            Text(
              '$percent %',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: document.progress,
            minHeight: 5,
            backgroundColor: AppColors.beige200,
          ),
        ),
      ],
    );
  }
}

BoxDecoration get _decoration => BoxDecoration(
  color: AppColors.white,
  borderRadius: BorderRadius.circular(AppTheme.radius),
  border: Border.all(color: AppColors.beige300.withValues(alpha: 0.55)),
  boxShadow: const [
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ],
);

String? _expiryLabel(DocumentModel document) {
  if (document.dateExpiration == null) return null;
  if (!isExpirableType(document.docType)) return null;
  final days = daysUntil(document.dateExpiration);
  if (days < -90 || days > 30) return null;
  if (days < 0) return 'Expiré';
  return 'Expire dans ${days}j';
}

String _expiryUrgency(DocumentModel document) {
  final days = daysUntil(document.dateExpiration);
  return days <= 7 ? 'critical' : 'warning';
}

String? _echeanceLabel(DocumentModel document) {
  if (document.dateEcheance == null) return null;
  final days = daysUntil(document.dateEcheance);
  if (days < -90 || days > 30) return null;
  if (days < 0) return 'En retard';
  return 'Échéance ${days}j';
}

String _echeanceUrgency(DocumentModel document) {
  final days = daysUntil(document.dateEcheance);
  return days <= 7 ? 'critical' : 'warning';
}
