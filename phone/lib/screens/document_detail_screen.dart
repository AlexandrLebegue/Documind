import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/document.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/badges.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    super.key,
    required this.documentId,
    this.heroTag,
  });

  final String documentId;
  final String? heroTag;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  DocumentModel? _document;
  List<DocumentModel> _segments = const [];
  bool _loading = true;
  String? _error;
  bool _showFullText = false;
  bool _reprocessing = false;
  bool _deleting = false;
  bool _busyFile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    setState(() {
      _loading = _document == null;
      _error = null;
    });
    try {
      final doc = await api.document(widget.documentId);
      List<DocumentModel> segments = const [];
      if (doc.status == 'ready') {
        try {
          segments = await api.segments(doc.id);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _document = doc;
        _segments = segments;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = shortErrorMessage(error);
      });
    }
  }

  Future<void> _downloadAndOpen() async {
    final doc = _document;
    if (doc == null) return;
    final api = context.read<AppState>().api!;
    setState(() => _busyFile = true);
    try {
      final file = await api.downloadDocument(doc.id, doc.filename);
      if (!mounted) return;
      if (kIsWeb) {
        showAppSnack(context, 'Téléchargement non disponible sur le web.');
        return;
      }
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        showAppSnack(
          context,
          'Aucune application pour ouvrir ce fichier.',
          error: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, shortErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busyFile = false);
    }
  }

  Future<void> _share() async {
    final doc = _document;
    if (doc == null) return;
    final api = context.read<AppState>().api!;
    final box = context.findRenderObject() as RenderBox?;
    setState(() => _busyFile = true);
    try {
      final file = await api.downloadDocument(doc.id, doc.filename);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: doc.displayTitle,
          subject: doc.displayTitle,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Partage impossible : ${shortErrorMessage(error)}',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyFile = false);
    }
  }

  Future<void> _reprocess() async {
    final doc = _document;
    if (doc == null) return;
    final api = context.read<AppState>().api!;
    setState(() => _reprocessing = true);
    try {
      await api.reprocessDocument(doc.id);
      if (!mounted) return;
      showAppSnack(context, 'Re-analyse lancée');
      await Future<void>.delayed(const Duration(seconds: 1));
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, shortErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _reprocessing = false);
    }
  }

  Future<void> _delete() async {
    final doc = _document;
    if (doc == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        title: const Text('Supprimer ce document ?'),
        content: Text(
          '« ${doc.displayTitle} » et ses segments éventuels seront définitivement supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final api = context.read<AppState>().api!;
    setState(() => _deleting = true);
    try {
      await api.deleteDocument(doc.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showAppSnack(context, shortErrorMessage(error), error: true);
    }
  }

  Future<void> _editMetadata() async {
    final doc = _document;
    if (doc == null) return;
    final updates = await showMetadataEditor(context, doc);
    if (updates == null || !mounted) return;
    final api = context.read<AppState>().api!;
    try {
      final updated = await api.updateDocument(doc.id, updates);
      if (!mounted) return;
      setState(() => _document = updated);
      showAppSnack(context, 'Métadonnées enregistrées');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, shortErrorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: Shimmer(
            child: Column(
              children: [
                SkeletonBox(height: 240),
                SizedBox(height: 14),
                SkeletonBox(height: 28),
                SizedBox(height: 10),
                SkeletonBox(height: 90),
                SizedBox(height: 10),
                SkeletonBox(height: 90),
              ],
            ),
          ),
        ),
      );
    }
    if (_error != null || _document == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorState(
            message: _error ?? 'Document introuvable',
            onRetry: _load,
          ),
        ),
      );
    }

    final doc = _document!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document'),
        actions: [
          IconButton(
            tooltip: 'Télécharger',
            onPressed: _busyFile ? null : _downloadAndOpen,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Partager',
            onPressed: _busyFile ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reprocess') _reprocess();
              if (value == 'delete') _delete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'reprocess',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 19),
                    SizedBox(width: 10),
                    Text('Re-analyser'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 19,
                      color: AppColors.danger,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Supprimer',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _PreviewCard(
              document: doc,
              onOpen: _downloadAndOpen,
              busy: _busyFile,
            ),
            const SizedBox(height: 14),
            Hero(
              tag: widget.heroTag ?? 'document-${doc.id}',
              child: Material(
                color: Colors.transparent,
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              doc.displayTitle,
                              style: const TextStyle(
                                fontSize: 20,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(status: doc.status),
                        ],
                      ),
                      if (doc.title != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          doc.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.faint,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          DocTypeBadge(type: doc.docType),
                          if (doc.parentId != null)
                            const AlertBadge(urgency: 'info', label: 'Segment'),
                          if (doc.pageStart != null && doc.pageEnd != null)
                            AlertBadge(
                              urgency: 'info',
                              label: 'Pages ${doc.pageStart}–${doc.pageEnd}',
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ajouté le ${formatDateTime(doc.createdAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_deadlineBanner(doc) != null) ...[
              const SizedBox(height: 12),
              _deadlineBanner(doc)!,
            ],
            const SizedBox(height: 14),
            _MetadataSection(document: doc, onEdit: _editMetadata),
            if (doc.textContent != null && doc.textContent!.isNotEmpty) ...[
              const SizedBox(height: 14),
              _OcrTextSection(
                text: doc.textContent!,
                expanded: _showFullText,
                onToggle: () => setState(() => _showFullText = !_showFullText),
              ),
            ],
            if (_segments.isNotEmpty) ...[
              const SizedBox(height: 14),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_segments.length} document(s) dans ce fichier',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final segment in _segments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          segment.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: segment.pageStart != null
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
                ),
              ),
            ],
            const SizedBox(height: 18),
            AsyncButton(
              label: _reprocessing
                  ? 'Re-analyse en cours…'
                  : 'Re-analyser le document',
              icon: Icons.refresh,
              outlined: true,
              onPressed: _reprocessing ? null : _reprocess,
            ),
            const SizedBox(height: 10),
            AsyncButton(
              label: 'Supprimer le document',
              icon: Icons.delete_outline,
              outlined: true,
              danger: true,
              onPressed: _deleting ? null : _delete,
            ),
          ],
        ),
      ),
    );
  }

  Widget? _deadlineBanner(DocumentModel doc) {
    String? label;
    String? date;
    bool critical = false;
    if (doc.dateExpiration != null && isExpirableType(doc.docType)) {
      final days = daysUntil(doc.dateExpiration);
      if (days <= 30 && days >= -90) {
        label = days < 0
            ? 'Ce document a expiré il y a ${days.abs()} jours'
            : 'Ce document expire dans $days jours';
        date = 'Date d’expiration : ${formatLongDate(doc.dateExpiration)}';
        critical = days <= 7;
      }
    } else if (doc.dateEcheance != null) {
      final days = daysUntil(doc.dateEcheance);
      if (days <= 30 && days >= -90) {
        label = days < 0
            ? 'Échéance de paiement dépassée de ${days.abs()} jours'
            : 'Échéance de paiement dans $days jours';
        date = 'Date d’échéance : ${formatLongDate(doc.dateEcheance)}';
        critical = days <= 7;
      }
    }
    if (label == null) return null;
    final color = critical ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: critical ? AppColors.dangerBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (date != null)
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.document,
    required this.onOpen,
    required this.busy,
  });

  final DocumentModel document;
  final VoidCallback onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api!;
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.beige200,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.beige300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (document.isImage && !kIsWeb)
            Image.network(
              api.documentFileUrl(document.id),
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                );
              },
              errorBuilder: (_, _, _) => _fallback(document),
            )
          else
            _fallback(document),
          Positioned(
            right: 10,
            bottom: 10,
            child: FilledButton.icon(
              onPressed: busy ? null : onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.65),
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.open_in_new, size: 17),
              label: Text(
                document.isPdf ? 'Ouvrir le PDF' : 'Ouvrir le fichier',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(DocumentModel document) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            document.isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.insert_drive_file_outlined,
            size: 64,
            color: AppColors.muted,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              document.filename,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aperçu intégré indisponible pour ce format',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.document, required this.onEdit});

  final DocumentModel document;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: 'Type', value: docTypeLabel(document.docType)),
      (label: 'Émetteur', value: document.emetteur ?? '—'),
      (label: 'Destinataire', value: document.destinataire ?? '—'),
      (label: 'Date du document', value: formatDate(document.docDate)),
      (label: 'Montant', value: formatMoney(document.montant, fallback: '—')),
      (label: 'Référence', value: document.reference ?? '—'),
      (label: 'Expiration', value: formatDate(document.dateExpiration)),
      (label: 'Échéance', value: formatDate(document.dateEcheance)),
      (label: 'Résumé', value: document.resume ?? '—'),
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Métadonnées',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Modifier'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 116,
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (document.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in document.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OcrTextSection extends StatelessWidget {
  const _OcrTextSection({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final truncated = text.length > 600 && !expanded;
    final shown = truncated ? '${text.substring(0, 600)}…' : text;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.text_snippet_outlined,
                size: 18,
                color: AppColors.accent,
              ),
              SizedBox(width: 7),
              Text(
                'Texte extrait (OCR)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.beige50,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                color: AppColors.beige300.withValues(alpha: 0.4),
              ),
            ),
            child: SelectableText(
              shown,
              style: const TextStyle(
                fontSize: 12,
                height: 1.55,
                color: AppColors.ink,
              ),
            ),
          ),
          if (text.length > 600)
            TextButton(
              onPressed: onToggle,
              child: Text(expanded ? 'Voir moins' : 'Voir plus'),
            ),
        ],
      ),
    );
  }
}

Future<Map<String, dynamic>?> showMetadataEditor(
  BuildContext context,
  DocumentModel document,
) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _MetadataEditorSheet(document: document),
  );
}

class _MetadataEditorSheet extends StatefulWidget {
  const _MetadataEditorSheet({required this.document});

  final DocumentModel document;

  @override
  State<_MetadataEditorSheet> createState() => _MetadataEditorSheetState();
}

class _MetadataEditorSheetState extends State<_MetadataEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _emetteur;
  late final TextEditingController _destinataire;
  late final TextEditingController _reference;
  late final TextEditingController _montant;
  late final TextEditingController _resume;
  late final TextEditingController _tags;
  String? _docType;
  String? _docDate;
  String? _dateExpiration;
  String? _dateEcheance;

  @override
  void initState() {
    super.initState();
    final doc = widget.document;
    _title = TextEditingController(text: doc.title ?? '');
    _emetteur = TextEditingController(text: doc.emetteur ?? '');
    _destinataire = TextEditingController(text: doc.destinataire ?? '');
    _reference = TextEditingController(text: doc.reference ?? '');
    _montant = TextEditingController(
      text: doc.montant == null ? '' : doc.montant!.toStringAsFixed(2),
    );
    _resume = TextEditingController(text: doc.resume ?? '');
    _tags = TextEditingController(text: doc.tags.join(', '));
    _docType = doc.docType;
    _docDate = doc.docDate;
    _dateExpiration = doc.dateExpiration;
    _dateEcheance = doc.dateEcheance;
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _emetteur,
      _destinataire,
      _reference,
      _montant,
      _resume,
      _tags,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<String?> _pickDate(String? current) async {
    final initial = parseDate(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
      locale: const Locale('fr', 'FR'),
    );
    if (picked == null) return current;
    return picked.toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.beige300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Modifier les métadonnées',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _field('Titre', _title),
            _field('Émetteur', _emetteur),
            _field('Destinataire', _destinataire),
            _field('Référence', _reference),
            _field(
              'Montant (€)',
              _montant,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 4),
            const _SheetLabel('Type'),
            DropdownButtonFormField<String>(
              initialValue:
                  _docType == null ||
                      !docTypeOptions.any((item) => item.key == _docType)
                  ? null
                  : _docType,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Type de document'),
              items: docTypeOptions
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.key,
                      child: Text(item.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _docType = value),
            ),
            const SizedBox(height: 10),
            _dateTile('Date du document', _docDate, (value) {
              setState(() => _docDate = value);
            }),
            _dateTile('Date d’expiration', _dateExpiration, (value) {
              setState(() => _dateExpiration = value);
            }),
            _dateTile('Date d’échéance', _dateEcheance, (value) {
              setState(() => _dateEcheance = value);
            }),
            const SizedBox(height: 4),
            _field('Résumé', _resume, maxLines: 3),
            _field('Tags (séparés par des virgules)', _tags),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      final updates = <String, dynamic>{
                        'title': _nullIfEmpty(_title.text),
                        'emetteur': _nullIfEmpty(_emetteur.text),
                        'destinataire': _nullIfEmpty(_destinataire.text),
                        'reference': _nullIfEmpty(_reference.text),
                        'resume': _nullIfEmpty(_resume.text),
                        'doc_type': _docType,
                        'doc_date': _docDate,
                        'date_expiration': _dateExpiration,
                        'date_echeance': _dateEcheance,
                        'montant': _montant.text.trim().isEmpty
                            ? null
                            : double.tryParse(
                                _montant.text.trim().replaceAll(',', '.'),
                              ),
                        'tags': _tags.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                      };
                      Navigator.of(context).pop(updates);
                    },
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetLabel(label),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(hintText: label),
          ),
        ],
      ),
    );
  }

  Widget _dateTile(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () async {
          final picked = await _pickDate(value);
          onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppColors.beige300),
            color: AppColors.beige50,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDate(value),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.calendar_today_outlined,
                size: 17,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
