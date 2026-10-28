import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/transfer_state.dart';
import '../theme/app_colors.dart';
import 'document_detail_screen.dart';

Future<void> showTransferSheet(BuildContext context) async {
  final transfers = context.read<AppState>().transfers;
  if (transfers == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => TransferSheet(transfers: transfers),
  );
}

class TransferSheet extends StatelessWidget {
  const TransferSheet({super.key, required this.transfers});

  final TransferState transfers;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: AnimatedBuilder(
          animation: transfers,
          builder: (context, _) => Column(
            children: [
              ListTile(
                title: const Text('Envois et file d’attente'),
                subtitle: Text('${transfers.busyCount} en cours'),
                trailing: IconButton(
                  tooltip: 'Fermer le suivi',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: transfers.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (transfers.pollError != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              transfers.pollError!,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                            TextButton(
                              onPressed: transfers.refresh,
                              child: const Text('Réessayer le suivi'),
                            ),
                          ],
                        ),
                      for (final task in transfers.tasks)
                        _UploadCard(task: task, transfers: transfers),
                      const SizedBox(height: 12),
                      const Text(
                        'File de traitement du serveur',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (transfers.queue?.active case final active?)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.autorenew),
                          title: Text(active.label),
                          subtitle: const Text('En cours'),
                        ),
                      for (final job in transfers.queue?.pending ?? [])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text('#${job.position}'),
                          title: Text(job.label),
                          subtitle: Text('En file · position ${job.position}'),
                        ),
                      if (transfers.queue?.isBusy == false)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Aucun document en attente.'),
                        ),
                      if (transfers.queue?.history.isNotEmpty == true) ...[
                        const Text(
                          'Traitements récents',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        for (final job in transfers.queue!.history.reversed)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(job.label),
                            subtitle: Text(
                              job.error ??
                                  (job.status == 'done'
                                      ? 'Terminé'
                                      : job.status == 'error'
                                      ? 'Erreur'
                                      : job.status),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.task, required this.transfers});

  final UploadTask task;
  final TransferState transfers;

  String get status {
    if (task.sending) return 'Envoi…';
    if (task.error != null) return 'Erreur';
    final doc = task.document;
    if (doc?.isReady == true) return 'Terminé';
    if (doc?.status == 'segmented') return 'Fiches détectées dans le scan';
    if (doc?.status == 'processing') {
      if (doc!.pagesTotal > 0 && doc.pagesDone >= doc.pagesTotal) {
        return 'Analyse LLM…';
      }
      return doc.pagesTotal > 0
          ? 'OCR page ${doc.pagesDone}/${doc.pagesTotal}'
          : 'OCR en cours…';
    }
    // Queue job ids are independent of document ids. The server labels upload
    // jobs with the filename; do not compare these unrelated ids.
    final filename = doc?.filename ?? task.input.name;
    for (final job in transfers.queue?.pending ?? []) {
      if (job.label == filename) return 'En file · position ${job.position}';
    }
    return 'En file d’attente';
  }

  @override
  Widget build(BuildContext context) {
    final doc = task.document;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.input.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(status),
            if (task.sending) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: task.total > 0
                    ? (task.sent / task.total).clamp(0, 1)
                    : null,
              ),
              Text('${task.sent} / ${task.total} octets'),
            ] else if (doc?.status == 'processing' && doc!.pagesTotal > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: doc.progress),
            ],
            if (task.error != null) ...[
              Text(
                task.error!,
                style: const TextStyle(color: AppColors.danger),
              ),
              TextButton(
                onPressed: () => transfers.retry(task),
                child: const Text('Réessayer'),
              ),
            ],
            if (!task.sending && task.isComplete)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentDetailScreen(documentId: doc!.id),
                  ),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Voir la fiche'),
              ),
          ],
        ),
      ),
    );
  }
}
