import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'add_document_sheet.dart';
import 'alerts_screen.dart';
import 'chat_screen.dart';
import 'dashboard_screen.dart';
import 'documents_screen.dart';
import 'logs_screen.dart';
import 'procedures_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final ValueNotifier<String> _documentsQuery = ValueNotifier('');
  int _alertCount = 0;
  Timer? _alertTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAlertCount());
    _alertTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshAlertCount(),
    );
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    _documentsQuery.dispose();
    super.dispose();
  }

  Future<void> _refreshAlertCount() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final response = await api.alerts(daysAhead: 30, limit: 1);
      if (!mounted) return;
      setState(() {
        _alertCount = response.overdueCount + response.expiringCount;
      });
    } catch (_) {}
  }

  void _openDocumentsSearch(String query) {
    _documentsQuery.value = query;
    setState(() => _index = 1);
  }

  Future<void> _openAdd() async {
    final changed = await showAddDocumentSheet(context);
    if (changed == true) {
      _documentsQuery.value = _documentsQuery.value;
      setState(() {});
      _refreshAlertCount();
    }
  }

  void _onTabChanged(int index) {
    setState(() => _index = index);
    if (index == 3) _refreshAlertCount();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardScreen(onSearch: _openDocumentsSearch),
      DocumentsScreen(queryListenable: _documentsQuery),
      const ChatScreen(),
      const AlertsScreen(),
      _MoreScreen(
        onNavigate: (index) {
          if (index == 1) {
            setState(() => _index = 1);
          }
        },
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabTransition(active: i == _index, child: tabs[i]),
          ],
        ),
      ),
      floatingActionButton: (_index == 0 || _index == 1)
          ? FloatingActionButton(
              onPressed: _openAdd,
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              tooltip: 'Ajouter un document',
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.beige200)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _navItem(0, Icons.home_outlined, Icons.home, 'Accueil'),
                _navItem(1, Icons.folder_outlined, Icons.folder, 'Documents'),
                _navItem(
                  2,
                  Icons.chat_bubble_outline,
                  Icons.chat_bubble,
                  'Chat',
                ),
                _navItem(
                  3,
                  Icons.notifications_none,
                  Icons.notifications,
                  'Alertes',
                  badge: _alertCount,
                ),
                _navItem(4, Icons.more_horiz, Icons.more_horiz, 'Plus'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    int badge = 0,
  }) {
    final selected = _index == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTabChanged(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 23,
                  color: selected ? AppColors.accent : AppColors.muted,
                ),
                if (badge > 0)
                  Positioned(
                    right: -7,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      constraints: const BoxConstraints(minWidth: 15),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabTransition extends StatelessWidget {
  const _TabTransition({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: Motion.fast,
      curve: Motion.curve,
      child: child,
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text(
          'Plus',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Démarches, synchronisation et outils du serveur.',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        _MoreTile(
          icon: Icons.assignment_outlined,
          title: 'Démarches',
          subtitle: 'Procédures et documents requis',
          onTap: () => Navigator.of(
            context,
          ).push(slideFadeRoute(const ProceduresScreen())),
        ),
        _MoreTile(
          icon: Icons.sync_outlined,
          title: 'Synchronisation',
          subtitle: 'Verdicts des dossiers surveillés',
          onTap: () =>
              Navigator.of(context).push(slideFadeRoute(const SyncScreen())),
        ),
        _MoreTile(
          icon: Icons.terminal_outlined,
          title: 'Journaux',
          subtitle: 'Logs du serveur en direct',
          onTap: () =>
              Navigator.of(context).push(slideFadeRoute(const LogsScreen())),
        ),
        _MoreTile(
          icon: Icons.settings_outlined,
          title: 'Réglages',
          subtitle: 'Serveur, IA et application',
          onTap: () => Navigator.of(
            context,
          ).push(slideFadeRoute(const SettingsScreen())),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.beige200.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'DocuMind mobile ne lance ni agent ni service de synchronisation. '
                  'Les verdicts restent consultables et validables depuis cet écran.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(
                color: AppColors.beige300.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 21, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
