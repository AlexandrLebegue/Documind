import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/procedure.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../widgets/badges.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';
import 'document_detail_screen.dart';
import 'procedure_editor_screen.dart';

class ProcedureDetailScreen extends StatefulWidget {
  const ProcedureDetailScreen({super.key, required this.procedureId});

  final String procedureId;

  @override
  State<ProcedureDetailScreen> createState() => _ProcedureDetailScreenState();
}

class _ProcedureDetailScreenState extends State<ProcedureDetailScreen> {
  Procedure? _procedure;
  ProcedureExecution? _execution;
  bool _loading = true;
  bool _executing = false;
  bool _deleting = false;
  bool _showExecute = false;
  String? _error;
  final _personName = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _personName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    setState(() {
      _loading = _procedure == null;
      _error = null;
    });
    try {
      final procedure = await api.procedure(widget.procedureId);
      if (!mounted) return;
      setState(() {
        _procedure = procedure;
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

  Future<void> _execute() async {
    final name = _personName.text.trim();
    if (name.isEmpty) return;
    final api = context.read<AppState>().api!;
    setState(() {
      _executing = true;
      _error = null;
    });
    try {
      final execution = await api.executeProcedure(widget.procedureId, name);
      if (!mounted) return;
      setState(() {
        _execution = execution;
        _showExecute = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = shortErrorMessage(error));
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  Future<void> _edit() async {
    final procedure = _procedure;
    if (procedure == null) return;
    final updated = await Navigator.of(context).push<Procedure>(
      slideFadeRoute(ProcedureEditorScreen(procedure: procedure)),
    );
    if (updated != null && mounted) {
      setState(() => _procedure = updated);
    }
  }

  Future<void> _delete() async {
    final procedure = _procedure;
    if (procedure == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette démarche ?'),
        content: Text(
          '« ${procedure.name} » et ses exécutions seront supprimés.',
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
    if (confirmed != true || !mounted) return;
    final api = context.read<AppState>().api!;
    setState(() => _deleting = true);
    try {
      await api.deleteProcedure(procedure.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
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
                SkeletonBox(height: 130),
                SizedBox(height: 12),
                SkeletonBox(height: 220),
              ],
            ),
          ),
        ),
      );
    }
    final procedure = _procedure;
    if (procedure == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorState(
            message: _error ?? 'Démarche introuvable',
            onRetry: _load,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Démarche'),
        actions: [
          IconButton(
            tooltip: 'Modifier',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: _deleting ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          procedure.name,
                          style: const TextStyle(
                            fontSize: 19,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ProcedureTypeBadge(type: procedure.procedureType),
                    ],
                  ),
                  if (procedure.description != null &&
                      procedure.description!.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      procedure.description!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Mise à jour le ${formatDateTime(procedure.updatedAt)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.faint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Documents requis (${procedure.requiredDocuments.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (procedure.requiredDocuments.isEmpty)
                    const Text(
                      'Aucun document requis.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    )
                  else
                    for (final doc in procedure.requiredDocuments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 17,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doc.label,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (doc.description != null &&
                                      doc.description!.isNotEmpty)
                                    Text(
                                      doc.description!,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        height: 1.35,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  Text(
                                    docTypeLabel(doc.docType),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.faint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            if (procedure.remarks != null && procedure.remarks!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Remarques',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      procedure.remarks!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (!_showExecute && _execution == null)
              AsyncButton(
                label: 'Lancer la démarche',
                icon: Icons.play_arrow,
                onPressed: () async {
                  setState(() => _showExecute = true);
                },
              ),
            if (_showExecute) ...[
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nom de la personne',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Le serveur recherchera les documents les plus récents correspondant à chaque exigence.',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _personName,
                      textCapitalization: TextCapitalization.words,
                      autofocus: true,
                      onSubmitted: (_) => _execute(),
                      decoration: const InputDecoration(
                        hintText: 'Prénom et nom',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _executing
                                ? null
                                : () => setState(() => _showExecute = false),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _executing ? null : _execute,
                            icon: _executing
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.search, size: 18),
                            label: Text(
                              _executing ? 'Recherche…' : 'Rechercher',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (_execution != null) ...[
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Résultat',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        AlertBadge(
                          urgency: _execution!.status == 'complete'
                              ? 'info'
                              : 'warning',
                          label: _execution!.status == 'complete'
                              ? 'Complet'
                              : 'Incomplet',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pour ${_execution!.personName}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final match in _execution!.matchedDocuments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Material(
                          color: match.found
                              ? AppColors.successBg
                              : AppColors.warningBg,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSmall,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSmall,
                            ),
                            onTap: match.document == null
                                ? null
                                : () => Navigator.of(context).push(
                                    slideFadeRoute(
                                      DocumentDetailScreen(
                                        documentId: match.document!.id,
                                      ),
                                    ),
                                  ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Icon(
                                    match.found
                                        ? Icons.check_circle
                                        : Icons.error_outline,
                                    size: 18,
                                    color: match.found
                                        ? AppColors.success
                                        : AppColors.warning,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          match.requiredLabel,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          match.document?.displayTitle ??
                                              'Document non trouvé',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (match.document != null)
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 17,
                                      color: AppColors.faint,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _execution = null;
                        _showExecute = true;
                        _personName.clear();
                      }),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Relancer'),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
