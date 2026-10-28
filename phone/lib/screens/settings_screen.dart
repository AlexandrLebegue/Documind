import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _openrouterKey = TextEditingController();
  final _openrouterModel = TextEditingController();
  final _openrouterUrl = TextEditingController();
  final _ollamaUrl = TextEditingController();
  final _ollamaModel = TextEditingController();
  final _llamacppUrl = TextEditingController();
  final _llamacppModel = TextEditingController();
  final _nasHost = TextEditingController();
  final _nasShare = TextEditingController();
  final _nasPath = TextEditingController();
  final _nasUser = TextEditingController();
  final _nasPassword = TextEditingController();

  ServerSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _checkingUpdate = false;
  bool _updating = false;
  bool _syncingNas = false;
  bool _testingLlama = false;
  bool _keyChanged = false;
  bool _nasPasswordChanged = false;
  bool _showKey = false;
  String _provider = 'openrouter';
  bool _nasEnabled = false;
  int _nasHour = 7;
  String? _error;
  String? _status;
  UpdateCheckResult? _update;
  NasSyncResult? _nasResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final controller in [
      _openrouterKey,
      _openrouterModel,
      _openrouterUrl,
      _ollamaUrl,
      _ollamaModel,
      _llamacppUrl,
      _llamacppModel,
      _nasHost,
      _nasShare,
      _nasPath,
      _nasUser,
      _nasPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    setState(() {
      _loading = _settings == null;
      _error = null;
    });
    try {
      final settings = await api.settings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _provider = settings.aiProvider;
        _openrouterKey.text = settings.openrouterApiKey;
        _openrouterModel.text = settings.openrouterModel;
        _openrouterUrl.text = settings.openrouterBaseUrl;
        _ollamaUrl.text = settings.ollamaBaseUrl;
        _ollamaModel.text = settings.ollamaModel;
        _llamacppUrl.text = settings.llamacppBaseUrl;
        _llamacppModel.text = settings.llamacppModel;
        _nasHost.text = settings.nasHost;
        _nasShare.text = settings.nasShare;
        _nasPath.text = settings.nasPath;
        _nasUser.text = settings.nasUsername;
        _nasEnabled = settings.nasSyncEnabled;
        _nasHour = settings.nasSyncHour;
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

  Future<void> _save() async {
    final api = context.read<AppState>().api!;
    final settings = _settings;
    if (settings == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    final payload = <String, dynamic>{
      'ai_provider': _provider,
      'openrouter_model': _openrouterModel.text.trim(),
      'openrouter_base_url': _openrouterUrl.text.trim(),
      'ollama_base_url': _ollamaUrl.text.trim(),
      'ollama_model': _ollamaModel.text.trim(),
      'llamacpp_base_url': _llamacppUrl.text.trim(),
      'llamacpp_model': _llamacppModel.text.trim(),
      'nas_sync_enabled': _nasEnabled,
      'nas_host': _nasHost.text.trim(),
      'nas_share': _nasShare.text.trim(),
      'nas_path': _nasPath.text.trim(),
      'nas_username': _nasUser.text.trim(),
      'nas_sync_hour': _nasHour,
      'nas_sync_minute': settings.nasSyncMinute,
    };
    if (_keyChanged && _openrouterKey.text.trim().isNotEmpty) {
      payload['openrouter_api_key'] = _openrouterKey.text.trim();
    }
    if (_nasPasswordChanged && _nasPassword.text.isNotEmpty) {
      payload['nas_password'] = _nasPassword.text;
    }
    try {
      final updated = await api.updateSettings(payload);
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _openrouterKey.text = updated.openrouterApiKey;
        _nasPassword.clear();
        _keyChanged = false;
        _nasPasswordChanged = false;
        _status = 'Réglages enregistrés';
        _showKey = false;
      });
      showAppSnack(context, 'Réglages enregistrés');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = shortErrorMessage(error));
      showAppSnack(context, shortErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkUpdate() async {
    final api = context.read<AppState>().api!;
    setState(() {
      _checkingUpdate = true;
      _error = null;
      _status = null;
    });
    try {
      final result = await api.checkUpdate();
      if (!mounted) return;
      setState(() => _update = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = shortErrorMessage(error));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _applyUpdate() async {
    final api = context.read<AppState>().api!;
    setState(() {
      _updating = true;
      _error = null;
      _status = null;
    });
    try {
      await api.applyUpdate();
      if (!mounted) return;
      setState(() => _status = 'Mise à jour appliquée sur le serveur');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = shortErrorMessage(error));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _triggerNas() async {
    final api = context.read<AppState>().api!;
    setState(() {
      _syncingNas = true;
      _error = null;
      _nasResult = null;
    });
    try {
      final result = await api.triggerNasSync();
      if (!mounted) return;
      setState(() => _nasResult = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = shortErrorMessage(error));
    } finally {
      if (mounted) setState(() => _syncingNas = false);
    }
  }

  Future<void> _testLlama() async {
    final api = context.read<AppState>().api!;
    setState(() {
      _testingLlama = true;
      _status = null;
      _error = null;
    });
    try {
      final ok = await api.testLlamaCpp();
      if (!mounted) return;
      setState(() {
        _status = ok
            ? 'Connexion llama.cpp réussie'
            : 'llama.cpp ne répond pas correctement';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = shortErrorMessage(error));
    } finally {
      if (mounted) setState(() => _testingLlama = false);
    }
  }

  void _changeServer() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    context.read<AppState>().requestServerChange();
  }

  Future<void> _forgetServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oublier ce serveur ?'),
        content: const Text(
          'L’adresse sera supprimée de ce téléphone. Aucune donnée n’est modifiée sur le serveur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oublier'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await context.read<AppState>().forgetServer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Shimmer(
                child: Column(
                  children: [
                    SkeletonBox(height: 110),
                    SizedBox(height: 12),
                    SkeletonBox(height: 220),
                    SizedBox(height: 12),
                    SkeletonBox(height: 120),
                  ],
                ),
              ),
            )
          : _settings == null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorState(
                message: _error ?? 'Réglages indisponibles',
                onRetry: _load,
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _serverCard(),
                  const SizedBox(height: 12),
                  _aiCard(),
                  const SizedBox(height: 12),
                  _nasCard(),
                  const SizedBox(height: 12),
                  _updatesCard(),
                  const SizedBox(height: 12),
                  _aboutCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _messageBox(_error!, error: true),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    _messageBox(_status!, error: false),
                  ],
                  const SizedBox(height: 16),
                  AsyncButton(
                    label: _saving
                        ? 'Enregistrement…'
                        : 'Enregistrer les réglages',
                    icon: Icons.save_outlined,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _serverCard() {
    final state = context.watch<AppState>();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.dns_outlined, title: 'Serveur DocuMind'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.beige50,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppColors.beige300),
            ),
            child: SelectableText(
              state.server,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _changeServer,
                  icon: const Icon(Icons.swap_horiz, size: 17),
                  label: const Text('Changer de serveur'),
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: _forgetServer,
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text('Oublier ce serveur'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Widget _aiCard() {
    final settings = _settings!;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.memory, title: 'Configuration IA'),
          const SizedBox(height: 12),
          const _FieldLabel('Fournisseur'),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: 'openrouter',
                child: Text('OpenRouter (cloud)'),
              ),
              DropdownMenuItem(
                value: 'ollama',
                child: Text('Ollama (Proxmox / local)'),
              ),
              DropdownMenuItem(
                value: 'llamacpp',
                child: Text('llama.cpp (GPU local)'),
              ),
              DropdownMenuItem(
                value: 'custom',
                child: Text('Endpoint personnalisé'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _provider = value);
            },
          ),
          const SizedBox(height: 14),
          if (_provider == 'openrouter' || _provider == 'custom') ...[
            const _FieldLabel('Clé API OpenRouter'),
            TextField(
              controller: _openrouterKey,
              obscureText: !_showKey,
              onChanged: (_) => _keyChanged = true,
              decoration: InputDecoration(
                hintText: settings.openrouterApiKey.isEmpty
                    ? 'sk-or-…'
                    : 'Valeur masquée',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(
                    _showKey ? Icons.visibility_off : Icons.visibility,
                    size: 19,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _field('Modèle', _openrouterModel),
            _field('URL de base', _openrouterUrl),
          ],
          if (_provider == 'ollama') ...[
            _field('URL Ollama', _ollamaUrl),
            _field('Modèle Ollama', _ollamaModel),
          ],
          if (_provider == 'llamacpp') ...[
            _field('URL llama.cpp', _llamacppUrl),
            _field('Modèle llama.cpp', _llamacppModel),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _testingLlama ? null : _testLlama,
              icon: _testingLlama
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 17),
              label: const Text('Tester la connexion'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nasCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.cloud_sync_outlined,
            title: 'Synchronisation NAS du serveur',
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Synchronisation quotidienne',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Le serveur importe les fichiers du NAS une fois par jour.',
              style: TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
            value: _nasEnabled,
            onChanged: (value) => setState(() => _nasEnabled = value),
          ),
          if (_nasEnabled) ...[
            _field('Hôte NAS', _nasHost),
            _field('Partage', _nasShare),
            _field('Chemin', _nasPath),
            _field('Utilisateur', _nasUser),
            const _FieldLabel('Mot de passe'),
            TextField(
              controller: _nasPassword,
              obscureText: true,
              onChanged: (_) => _nasPasswordChanged = true,
              decoration: const InputDecoration(
                hintText: 'Laisser vide pour conserver',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _nasHour,
              decoration: const InputDecoration(labelText: 'Heure'),
              items: [
                for (var hour = 0; hour < 24; hour++)
                  DropdownMenuItem(
                    value: hour,
                    child: Text('${hour.toString().padLeft(2, '0')}:00'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _nasHour = value);
              },
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: _syncingNas ? null : _triggerNas,
            icon: _syncingNas
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 17),
            label: Text(
              _syncingNas
                  ? 'Synchronisation en cours…'
                  : 'Synchroniser le NAS maintenant',
            ),
          ),
          if (_nasResult != null) ...[
            const SizedBox(height: 10),
            _messageBox(
              '${_nasResult!.scanned} fichier(s) analysé(s) · '
              '${_nasResult!.imported} importé(s) · '
              '${_nasResult!.skipped} ignoré(s)'
              '${_nasResult!.errors > 0 ? ' · ${_nasResult!.errors} erreur(s)' : ''}',
              error: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _updatesCard() {
    final update = _update;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.system_update_alt,
            title: 'Mises à jour du serveur',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _checkingUpdate ? null : _checkUpdate,
            icon: _checkingUpdate
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 17),
            label: const Text('Vérifier les mises à jour'),
          ),
          if (update != null) ...[
            const SizedBox(height: 10),
            if (update.error != null)
              _messageBox(update.error!, error: true)
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: update.upToDate
                      ? AppColors.successBg
                      : AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  update.upToDate
                      ? 'Le serveur est à jour.'
                      : '${update.behindBy} commit(s) disponible(s) sur GitHub.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: update.upToDate
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ),
            if (!update.upToDate && update.error == null) ...[
              const SizedBox(height: 10),
              AsyncButton(
                label: _updating ? 'Mise à jour…' : 'Mettre à jour le serveur',
                icon: Icons.download,
                onPressed: _updating ? null : _applyUpdate,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.info_outline, title: 'Application'),
          const SizedBox(height: 10),
          _infoRow('Version mobile', '0.1.0'),
          _infoRow('Version serveur', _settings?.version ?? '—'),
          _infoRow('Stockage serveur', _settings?.dataDir ?? '—'),
          const SizedBox(height: 6),
          const Text(
            'DocuMind mobile ne lance ni agent ni service de synchronisation. '
            'Les réglages IA et NAS agissent sur le serveur DocuMind.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          TextField(
            controller: controller,
            decoration: InputDecoration(hintText: label),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBox(String message, {required bool error}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? AppColors.dangerBg : AppColors.successBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: (error ? AppColors.danger : AppColors.success).withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: error ? AppColors.danger : AppColors.success,
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
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
