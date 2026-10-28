import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../widgets/badges.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';
import 'document_detail_screen.dart';

enum _AlertTab { alerts, suggestions, gaps }

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertsResponse? _response;
  List<RenewalSuggestion> _suggestions = const [];
  List<GapAlert> _gaps = const [];
  bool _loading = true;
  String? _error;
  _AlertTab _tab = _AlertTab.alerts;
  String _urgency = 'all';
  String _type = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    setState(() {
      _loading = _response == null;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        api.alerts(daysAhead: 365, limit: 100),
        api.renewalSuggestions().catchError((_) => <RenewalSuggestion>[]),
        api.gapAlerts().catchError((_) => <GapAlert>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _response = results[0] as AlertsResponse;
        _suggestions = results[1] as List<RenewalSuggestion>;
        _gaps = results[2] as List<GapAlert>;
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

  List<AlertItem> get _filtered {
    final alerts = _response?.alerts ?? const <AlertItem>[];
    return alerts.where((alert) {
      if (_urgency != 'all' && alert.urgency != _urgency) return false;
      if (_type != 'all' && alert.alertType != _type) return false;
      return true;
    }).toList();
  }

  Future<void> _dismiss(AlertItem alert) async {
    final api = context.read<AppState>().api!;
    try {
      await api.dismissAlert(alert.document.id, alert.alertType);
      if (!mounted) return;
      setState(() {
        final response = _response;
        if (response == null) return;
        _response = AlertsResponse(
          alerts: response.alerts
              .where(
                (item) =>
                    item.document.id != alert.document.id ||
                    item.alertType != alert.alertType,
              )
              .toList(),
          total: response.total,
          expiringCount: response.expiringCount,
          overdueCount: response.overdueCount,
          upcomingPayments: response.upcomingPayments,
        );
      });
      showAppSnack(context, 'Alerte ignorée');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, shortErrorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 30),
              SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: SkeletonBox(height: 76)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 76)),
                ],
              ),
              SizedBox(height: 10),
              SkeletonBox(height: 76),
              SizedBox(height: 18),
              SkeletonBox(height: 44),
              SizedBox(height: 10),
              SkeletonBox(height: 70),
              SizedBox(height: 10),
              SkeletonBox(height: 70),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorState(message: _error!, onRetry: _load),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Text(
            'Alertes',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Expirations, échéances et documents manquants.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _summary(),
          const SizedBox(height: 16),
          _tabs(),
          const SizedBox(height: 14),
          if (_tab == _AlertTab.alerts) ..._alertsTab(),
          if (_tab == _AlertTab.suggestions) ..._suggestionsTab(),
          if (_tab == _AlertTab.gaps) ..._gapsTab(),
        ],
      ),
    );
  }

  Widget _summary() {
    final response = _response;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Expirés',
                response?.overdueCount ?? 0,
                Icons.error_outline,
                AppColors.danger,
                response != null && response.overdueCount > 0,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _statCard(
                'Expirent',
                response?.expiringCount ?? 0,
                Icons.warning_amber,
                AppColors.warning,
                response != null && response.expiringCount > 0,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _statCard(
                'Échéances',
                response?.upcomingPayments ?? 0,
                Icons.schedule,
                AppColors.accent,
                response != null && response.upcomingPayments > 0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(
    String label,
    int value,
    IconData icon,
    Color color,
    bool highlighted,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      decoration: BoxDecoration(
        color: highlighted ? color.withValues(alpha: 0.08) : AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: highlighted
              ? color.withValues(alpha: 0.28)
              : AppColors.beige300.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: highlighted ? color : AppColors.muted),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 21,
              height: 1,
              fontWeight: FontWeight.w800,
              color: highlighted ? color : AppColors.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    final tabs = [
      (_AlertTab.alerts, 'Alertes', _response?.alerts.length ?? 0),
      (_AlertTab.suggestions, 'Renouvellements', _suggestions.length),
      (_AlertTab.gaps, 'Manquants', _gaps.length),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.beige100,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = tab.$1),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _tab == tab.$1
                        ? AppColors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          tab.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: _tab == tab.$1
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _tab == tab.$1
                                ? AppColors.ink
                                : AppColors.muted,
                          ),
                        ),
                      ),
                      if (tab.$3 > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          '${tab.$3}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _tab == tab.$1
                                ? AppColors.accent
                                : AppColors.faint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _alertsTab() {
    final filtered = _filtered;
    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('Toutes', _urgency == 'all', () {
              setState(() => _urgency = 'all');
            }),
            _filterChip('Urgentes', _urgency == 'critical', () {
              setState(() => _urgency = 'critical');
            }),
            _filterChip('Bientôt', _urgency == 'warning', () {
              setState(() => _urgency = 'warning');
            }),
            _filterChip('À surveiller', _urgency == 'info', () {
              setState(() => _urgency = 'info');
            }),
            const SizedBox(width: 10),
            _filterChip('Tout', _type == 'all', () {
              setState(() => _type = 'all');
            }),
            _filterChip('Expirations', _type == 'expiration', () {
              setState(() => _type = 'expiration');
            }),
            _filterChip('Échéances', _type == 'echeance', () {
              setState(() => _type = 'echeance');
            }),
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (filtered.isEmpty)
        const SectionCard(
          child: EmptyState(
            icon: Icons.check_circle_outline,
            title: 'Tout est en ordre',
            message: 'Aucun document ne nécessite votre attention.',
          ),
        )
      else
        for (final alert in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _AlertCard(
              alert: alert,
              onTap: () => Navigator.of(context).push(
                slideFadeRoute(
                  DocumentDetailScreen(documentId: alert.document.id),
                ),
              ),
              onDismiss: () => _dismiss(alert),
            ),
          ),
    ];
  }

  List<Widget> _suggestionsTab() {
    if (_suggestions.isEmpty) {
      return const [
        SectionCard(
          child: EmptyState(
            icon: Icons.autorenew,
            title: 'Aucun renouvellement suggéré',
            message:
                'Les suggestions apparaîtront lorsqu’un document '
                'arrivera à échéance.',
          ),
        ),
      ];
    }
    return [
      for (final suggestion in _suggestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SectionCard(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                slideFadeRoute(
                  DocumentDetailScreen(documentId: suggestion.document.id),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          suggestion.document.displayTitle,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.faint,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    suggestion.reason,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),
                  if (suggestion.suggestedProcedureName != null) ...[
                    const SizedBox(height: 7),
                    AlertBadge(
                      urgency: 'info',
                      label: suggestion.suggestedProcedureName!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _gapsTab() {
    if (_gaps.isEmpty) {
      return const [
        SectionCard(
          child: EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'Aucun document manquant',
            message: 'Les documents attendus sont bien présents.',
          ),
        ),
      ];
    }
    return [
      for (final gap in _gaps)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.help_outline,
                  size: 19,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              gap.message,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DocTypeBadge(type: gap.docType),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Attendu le ${formatLongDate(gap.expectedDate)}'
                        '${gap.destinataire != null ? ' · ${gap.destinataire}' : ''}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
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

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.onTap,
    required this.onDismiss,
  });

  final AlertItem alert;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final document = alert.document;
    final critical = alert.urgency == 'critical';
    final warning = alert.urgency == 'warning';
    final color = critical
        ? AppColors.danger
        : warning
        ? AppColors.warning
        : AppColors.accent;
    final days = alert.daysRemaining;
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: critical
                  ? AppColors.danger.withValues(alpha: 0.3)
                  : AppColors.beige300.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  alert.isExpiration ? Icons.event_busy : Icons.schedule,
                  size: 21,
                  color: color,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${alert.isExpiration ? 'Expire' : 'Échéance'} le '
                      '${formatLongDate(alert.targetDate)}'
                      '${document.emetteur != null ? ' · ${document.emetteur}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        AlertBadge(
                          urgency: alert.urgency,
                          label: days < 0
                              ? 'Expiré depuis ${days.abs()} j'
                              : 'Dans $days j',
                        ),
                        DocTypeBadge(type: document.docType),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'dismiss') onDismiss();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'dismiss',
                    child: Text('Ignorer cette alerte'),
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
