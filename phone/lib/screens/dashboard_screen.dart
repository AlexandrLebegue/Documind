import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../models/stats.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../widgets/badges.dart';
import '../widgets/common.dart';
import '../widgets/document_card.dart';
import '../widgets/skeleton.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Stats? _stats;
  Health? _health;
  List<AlertItem> _alerts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    if (mounted) setState(() => _error = null);
    try {
      final results = await Future.wait([
        api.stats(),
        api.health(),
        api
            .alerts(daysAhead: 90, limit: 5)
            .catchError(
              (_) => const AlertsResponse(
                alerts: [],
                total: 0,
                expiringCount: 0,
                overdueCount: 0,
                upcomingPayments: 0,
              ),
            ),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Stats;
        _health = results[1] as Health;
        _alerts = (results[2] as AlertsResponse).alerts;
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

  Future<void> _dismiss(AlertItem alert) async {
    final api = context.read<AppState>().api!;
    try {
      await api.dismissAlert(alert.document.id, alert.alertType);
      if (!mounted) return;
      setState(() {
        _alerts = _alerts
            .where(
              (a) =>
                  !(a.document.id == alert.document.id &&
                      a.alertType == alert.alertType),
            )
            .toList();
      });
      showAppSnack(context, 'Alerte masquée');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, shortErrorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 30, width: 190),
                SizedBox(height: 8),
                SkeletonBox(height: 14, width: 250),
                SizedBox(height: 20),
                SkeletonBox(height: 52),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 76)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonBox(height: 76)),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 76)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonBox(height: 76)),
                  ],
                ),
                SizedBox(height: 22),
                SkeletonBox(height: 90),
                SizedBox(height: 12),
                SkeletonBox(height: 90),
                SizedBox(height: 12),
                SkeletonBox(height: 90),
              ],
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [ErrorState(message: _error!, onRetry: _load)],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const PageHeader(
            title: 'Tableau de bord',
            subtitle: 'Vue d’ensemble de vos documents',
          ),
          const SizedBox(height: 16),
          _SearchButton(onSearch: widget.onSearch),
          const SizedBox(height: 18),
          _StatsGrid(stats: _stats, health: _health),
          if (_alerts.isNotEmpty) ...[
            const SizedBox(height: 18),
            _AlertsPanel(alerts: _alerts, onDismiss: _dismiss),
          ],
          const SizedBox(height: 22),
          const _SectionTitle('Documents récents'),
          const SizedBox(height: 10),
          if (_stats?.recentDocuments.isNotEmpty ?? false)
            ...(_stats!.recentDocuments
                .take(8)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CascadeIn(
                      index: entry.key,
                      child: DocumentCard(
                        document: entry.value,
                        view: DocumentViewMode.list,
                        heroTag: 'dashboard-${entry.value.id}',
                      ),
                    ),
                  ),
                ))
          else
            const SectionCard(
              child: EmptyState(
                icon: Icons.description_outlined,
                title: 'Aucun document',
                message:
                    'Ajoutez votre premier document avec le bouton + pour l’analyser.',
              ),
            ),
          const SizedBox(height: 22),
          const _SectionTitle('Répartition par type'),
          const SizedBox(height: 10),
          SectionCard(
            child: _TypeDonut(counts: _stats?.countByType ?? const {}),
          ),
        ],
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: () async {
        final query = await showSearch<String>(
          context: context,
          delegate: _DashboardSearchDelegate(),
        );
        if (query != null && query.trim().isNotEmpty) onSearch(query.trim());
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppColors.beige300),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, color: AppColors.muted, size: 21),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Rechercher dans vos documents…',
                style: TextStyle(fontSize: 14, color: AppColors.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardSearchDelegate extends SearchDelegate<String> {
  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => _build(context);

  @override
  Widget buildSuggestions(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    return Container(
      color: AppColors.beige100,
      child: ListTile(
        leading: const Icon(Icons.search),
        title: Text(
          query.trim().isEmpty
              ? 'Saisissez une recherche'
              : 'Rechercher « ${query.trim()} »',
        ),
        trailing: const Icon(Icons.arrow_forward),
        onTap: query.trim().isEmpty ? null : () => close(context, query.trim()),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({this.stats, this.health});

  final Stats? stats;
  final Health? health;

  @override
  Widget build(BuildContext context) {
    final month = DateFormatMonth.currentKey;
    final monthCount = stats?.countByMonth[month] ?? 0;
    final alertCount = stats?.alertCount ?? 0;
    final cards = [
      _StatData(
        label: 'Total documents',
        value: '${stats?.totalDocuments ?? 0}',
        icon: Icons.folder_outlined,
        color: AppColors.accent,
        background: AppColors.accentLight,
      ),
      _StatData(
        label: 'Ce mois-ci',
        value: '$monthCount',
        icon: Icons.calendar_today_outlined,
        color: AppColors.success,
        background: AppColors.successBg,
      ),
      _StatData(
        label: 'Alertes',
        value: alertCount == 0 ? 'Aucune' : '$alertCount',
        icon: alertCount == 0
            ? Icons.check_circle_outline
            : Icons.warning_amber,
        color: alertCount == 0 ? AppColors.success : AppColors.warning,
        background: alertCount == 0 ? AppColors.successBg : AppColors.warningBg,
      ),
      _StatData(
        label: 'Système',
        value: health?.llmLoaded == true ? 'Opérationnel' : 'Hors ligne',
        icon: Icons.circle,
        color: health?.llmLoaded == true ? AppColors.success : AppColors.danger,
        background: health?.llmLoaded == true
            ? AppColors.successBg
            : AppColors.dangerBg,
        small: true,
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: [
        for (var i = 0; i < cards.length; i++)
          CascadeIn(
            index: i,
            child: _StatCard(data: cards[i]),
          ),
      ],
    );
  }
}

class DateFormatMonth {
  static String get currentKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }
}

class _StatData {
  const _StatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
    this.small = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  final bool small;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.beige300.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, size: 20, color: data.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: data.small ? 13 : 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
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

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.alerts, required this.onDismiss});

  final List<AlertItem> alerts;
  final ValueChanged<AlertItem> onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: const Color(0xFFFCD9A0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFBEB),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppTheme.radius),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Documents à surveiller',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final alert in alerts)
            Dismissible(
              key: ValueKey('${alert.alertType}-${alert.document.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => onDismiss(alert),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 18),
                color: AppColors.dangerBg,
                child: const Icon(Icons.close, color: AppColors.danger),
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  alert.document.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${alert.isExpiration ? 'Expire' : 'Échéance'} le ${formatDate(alert.targetDate)}'
                  '${alert.daysRemaining < 0
                      ? ' (il y a ${alert.daysRemaining.abs()} j)'
                      : alert.daysRemaining == 0
                      ? ' (aujourd’hui)'
                      : ' (dans ${alert.daysRemaining} j)'}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: AlertBadge(
                  urgency: alert.urgency,
                  label: alert.daysRemaining < 0
                      ? (alert.isExpiration ? 'Expiré' : 'En retard')
                      : urgencyLabel(alert.urgency),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypeDonut extends StatelessWidget {
  const _TypeDonut({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.pie_chart_outline,
        title: 'Pas encore de données',
        message: 'La répartition apparaîtra après l’analyse de vos documents.',
      );
    }
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    final colors = entries
        .map((e) => docTypeStyle(e.key).color)
        .toList(growable: false);
    final values = entries
        .map((e) => e.value.toDouble())
        .toList(growable: false);

    return Row(
      children: [
        SizedBox(
          width: 118,
          height: 118,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(118, 118),
                painter: _DonutPainter(values: values, colors: colors),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const Text(
                    'docs',
                    style: TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: entries.take(6).map((entry) {
              final style = docTypeStyle(entry.key);
              final percent = ((entry.value / total) * 100).round();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: style.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        style.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      '$percent %',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 3,
    );
    var start = -1.5708;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 6.28318;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.butt
        ..color = colors[i];
      canvas.drawArc(rect, start, sweep - 0.02, false, paint);
      start += sweep;
    }
    final hole = Paint()..color = AppColors.white;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 13,
      hole,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
