import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ingest.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../widgets/badges.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';
import 'document_detail_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  IngestMarksResponse? _data;
  bool _loading = true;
  String? _error;
  String _filter = '';
  String? _busy;
  Timer? _timer;

  static const _filters = [
    ('', 'Tous'),
    ('pending', 'À valider'),
    ('accepted', 'Acceptés'),
    ('rejected', 'Refusés'),
    ('error', 'Erreurs'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load(showSpinner: true);
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final data = await api.ingestMarks(
        verdict: _filter.isEmpty ? null : _filter,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = shortErrorMessage(error);
      });
    }
  }

  Future<void> _act(IngestMark mark, String action) async {
    final api = context.read<AppState>().api!;
    setState(() => _busy = mark.sha256);
    try {
      switch (action) {
        case 'accept':
          await api.acceptIngestMark(mark.sha256);
          if (mounted) showAppSnack(context, 'Acceptation mise en file');
        case 'reject':
          await api.rejectIngestMark(mark.sha256);
          if (mounted) showAppSnack(context, 'Fichier refusé');
        case 'reevaluate':
          await api.reevaluateIngestMark(mark.sha256);
          if (mounted) showAppSnack(context, 'Réévaluation demandée');
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, shortErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final marks = _data?.marks ?? const <IngestMark>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Shimmer(
                child: Column(
                  children: [
                    SkeletonBox(height: 80),
                    SizedBox(height: 12),
                    SkeletonBox(height: 40),
                    SizedBox(height: 12),
                    SkeletonBox(height: 120),
                    SizedBox(height: 10),
                    SkeletonBox(height: 120),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(showSpinner: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const Text(
                    'Fichiers reçus des dossiers surveillés, verdicts du juge '
                    'et validation manuelle.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _summary(),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter in _filters)
                          _chip(filter.$2, _filter == filter.$1, () {
                            setState(() => _filter = filter.$1);
                            _load(showSpinner: true);
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (marks.isEmpty)
                    const SectionCard(
                      child: EmptyState(
                        icon: Icons.sync_outlined,
                        title: 'Aucun fichier',
                        message:
                            'Le client PC envoie les nouveaux fichiers selon '
                            'l’intervalle configuré sur le serveur.',
                      ),
                    )
                  else
                    for (final mark in marks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MarkCard(
                          mark: mark,
                          busy: _busy == mark.sha256,
                          onAccept: () => _act(mark, 'accept'),
                          onReject: () => _act(mark, 'reject'),
                          onReevaluate: () => _act(mark, 'reevaluate'),
                          onOpen: mark.docId == null
                              ? null
                              : () => Navigator.of(context).push(
                                  slideFadeRoute(
                                    DocumentDetailScreen(
                                      documentId: mark.docId!,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _summary() {
    final counts = _data?.counts ?? const <String, int>{};
    final items = [
      ('À valider', counts['pending'] ?? 0, AppColors.warning),
      ('Acceptés', counts['accepted'] ?? 0, AppColors.success),
      ('Refusés', counts['rejected'] ?? 0, AppColors.danger),
      ('Erreurs', counts['error'] ?? 0, AppColors.muted),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: AppColors.beige300.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '${items[i].$2}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: items[i].$3,
                    ),
                  ),
                  Text(
                    items[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.beige300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkCard extends StatelessWidget {
  const _MarkCard({
    required this.mark,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onReevaluate,
    required this.onOpen,
  });

  final IngestMark mark;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onReevaluate;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  mark.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              VerdictBadge(verdict: mark.verdict),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (mark.confidence != null) ...[
                Text(
                  'Confiance ${(mark.confidence! * 100).round()} %',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  '${mark.source ?? 'machine inconnue'} · '
                  '${formatShortDateTime(mark.firstSeen.toIso8601String())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.faint),
                ),
              ),
            ],
          ),
          if (mark.originPath != null) ...[
            const SizedBox(height: 3),
            Text(
              mark.originPath!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.faint),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            mark.reason ?? '—',
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mark.sha256,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8.5,
              color: AppColors.faint,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (mark.verdict == 'pending') ...[
                _action(
                  'Accepter',
                  AppColors.success,
                  Icons.check,
                  busy ? null : onAccept,
                ),
                _action(
                  'Refuser',
                  AppColors.danger,
                  Icons.close,
                  busy ? null : onReject,
                ),
              ] else
                OutlinedButton(
                  onPressed: busy ? null : onReevaluate,
                  child: const Text('Réévaluer'),
                ),
              if (onOpen != null)
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Ouvrir'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    String label,
    Color color,
    IconData icon,
    VoidCallback? onPressed,
  ) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(0, 40),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
