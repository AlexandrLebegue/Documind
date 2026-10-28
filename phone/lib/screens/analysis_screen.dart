import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/queue.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/badges.dart';
import '../widgets/common.dart';
import 'document_detail_screen.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.documentIds});

  final List<String> documentIds;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  Timer? _timer;
  final Map<String, DocumentModel> _documents = {};
  final Map<String, List<DocumentModel>> _segments = {};
  QueueStatus? _queue;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _allDone =>
      _documents.length == widget.documentIds.length &&
      _documents.values.every((doc) => !doc.isProcessing);

  Future<void> _refresh() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final results = await Future.wait([
        for (final id in widget.documentIds) api.document(id),
      ]);
      QueueStatus? queue;
      try {
        queue = await api.queue();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _error = null;
        _queue = queue;
        for (final doc in results) {
          _documents[doc.id] = doc;
          if (doc.isReady && doc.status == 'ready') {
            // Segments are loaded lazily once the parent is ready.
            if (!_segments.containsKey(doc.id)) {
              _loadSegments(api, doc.id);
            }
          }
        }
      });
      if (_allDone && _timer != null) {
        _timer?.cancel();
        _timer = null;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = shortErrorMessage(error));
    }
  }

  Future<void> _loadSegments(dynamic api, String id) async {
    try {
      final segments = await api.segments(id) as List<DocumentModel>;
      if (!mounted) return;
      if (segments.isEmpty) {
        _segments[id] = const [];
        return;
      }
      setState(() => _segments[id] = segments);
    } catch (_) {
      if (mounted) _segments[id] = const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyse en cours'),
        actions: [
          if (_allDone)
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Terminer'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: _allDone
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 30,
                          )
                        : const CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.accent,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _allDone
                              ? 'Analyse terminée'
                              : 'OCR et analyse IA en cours',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _allDone
                              ? 'Les documents sont prêts dans votre bibliothèque.'
                              : 'Le serveur traite une page à la fois. Vous pouvez fermer cet écran, le traitement continue.',
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_queue?.isBusy == true) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.hourglass_top,
                    size: 14,
                    color: AppColors.faint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _queue!.active != null
                        ? 'File : ${_queue!.active!.label} · ${_queue!.totalPending} en attente'
                        : 'File : ${_queue!.totalPending} document(s) en attente',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.faint,
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorState(message: _error!, onRetry: _refresh),
            ],
            const SizedBox(height: 16),
            for (final id in widget.documentIds) ...[
              _AnalysisCard(
                document: _documents[id],
                segments: _segments[id] ?? const [],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({this.document, required this.segments});

  final DocumentModel? document;
  final List<DocumentModel> segments;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.beige100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  doc?.isPdf == true
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc?.displayTitle ?? 'Document',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (doc != null)
                      Row(
                        children: [
                          StatusBadge(status: doc.status),
                          if (doc.ocrBackend != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              doc.ocrBackend == 'ovis'
                                  ? 'OvisOCR3'
                                  : doc.ocrBackend!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.faint,
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      const Text(
                        'Envoi en cours…',
                        style: TextStyle(fontSize: 11, color: AppColors.faint),
                      ),
                  ],
                ),
              ),
              if (doc?.isReady == true)
                IconButton(
                  tooltip: 'Ouvrir la fiche',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DocumentDetailScreen(documentId: doc!.id),
                    ),
                  ),
                  icon: const Icon(
                    Icons.arrow_forward,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
          if (doc != null && doc.pagesTotal > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pages traitées ${doc.pagesDone}/${doc.pagesTotal}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                if (doc.totalSeconds != null)
                  Text(
                    '${doc.totalSeconds!.toStringAsFixed(1)} s',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.faint,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: doc.progress,
                minHeight: 6,
                backgroundColor: AppColors.beige200,
              ),
            ),
          ],
          if (doc?.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              doc!.errorMessage!,
              style: const TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ],
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${segments.length} document(s) détecté(s) dans ce fichier :',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            const SizedBox(height: 6),
            for (final segment in segments)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  segment.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: segment.pageStart != null && segment.pageEnd != null
                    ? Text(
                        'Pages ${segment.pageStart}–${segment.pageEnd}',
                        style: const TextStyle(fontSize: 10),
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DocumentDetailScreen(documentId: segment.id),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
