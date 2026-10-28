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
import 'procedure_detail_screen.dart';
import 'procedure_editor_screen.dart';

class ProceduresScreen extends StatefulWidget {
  const ProceduresScreen({super.key});

  @override
  State<ProceduresScreen> createState() => _ProceduresScreenState();
}

class _ProceduresScreenState extends State<ProceduresScreen> {
  List<Procedure> _procedures = const [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    setState(() {
      _loading = _procedures.isEmpty;
      _error = null;
    });
    try {
      final procedures = await api.procedures(limit: 200);
      if (!mounted) return;
      setState(() {
        _procedures = procedures;
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

  List<Procedure> get _filtered => _filter.isEmpty
      ? _procedures
      : _procedures.where((p) => p.procedureType == _filter).toList();

  Future<void> _create() async {
    final created = await Navigator.of(
      context,
    ).push<Procedure>(slideFadeRoute(const ProcedureEditorScreen()));
    if (created != null && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Démarches'),
        actions: [
          IconButton(
            tooltip: 'Nouvelle démarche',
            onPressed: _create,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Shimmer(
                child: Column(
                  children: [
                    SkeletonBox(height: 44),
                    SizedBox(height: 14),
                    SkeletonBox(height: 130),
                    SizedBox(height: 10),
                    SkeletonBox(height: 130),
                    SizedBox(height: 10),
                    SkeletonBox(height: 130),
                  ],
                ),
              ),
            )
          : _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorState(message: _error!, onRetry: _load),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    '${_procedures.length} démarche'
                    '${_procedures.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip('Toutes', _filter.isEmpty, () {
                          setState(() => _filter = '');
                        }),
                        for (final entry in procedureTypeLabels.entries)
                          _chip(entry.value, _filter == entry.key, () {
                            setState(() => _filter = entry.key);
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_filtered.isEmpty)
                    SectionCard(
                      child: EmptyState(
                        icon: Icons.assignment_outlined,
                        title: 'Aucune démarche',
                        message: _filter.isEmpty
                            ? 'Créez une démarche pour rassembler les documents nécessaires.'
                            : 'Aucune démarche de ce type.',
                        action: _filter.isEmpty
                            ? FilledButton.icon(
                                onPressed: _create,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Créer une démarche'),
                              )
                            : null,
                      ),
                    )
                  else
                    for (final procedure in _filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ProcedureCard(
                          procedure: procedure,
                          onTap: () async {
                            await Navigator.of(context).push(
                              slideFadeRoute(
                                ProcedureDetailScreen(
                                  procedureId: procedure.id,
                                ),
                              ),
                            );
                            if (mounted) _load();
                          },
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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

class _ProcedureCard extends StatelessWidget {
  const _ProcedureCard({required this.procedure, required this.onTap});

  final Procedure procedure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: AppColors.beige300.withValues(alpha: 0.6),
            ),
          ),
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
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ProcedureTypeBadge(type: procedure.procedureType),
                ],
              ),
              if (procedure.description != null &&
                  procedure.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  procedure.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.muted,
                  ),
                ),
              ],
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${procedure.requiredDocuments.length} document(s) requis',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatRelativeDate(procedure.updatedAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.faint,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.faint,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
