import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

enum AppPhase { loading, setup, transition, ready }

class AppState extends ChangeNotifier {
  static const serverStorageKey = 'documind_server';

  AppPhase phase = AppPhase.loading;
  String server = '';
  String setupError = '';
  bool busy = false;
  ApiClient? _client;

  AppState();

  ApiClient? get api => _client;
  bool get hasClient => _client != null;

  factory AppState.withClient(ApiClient client) {
    final state = AppState();
    state
      .._client = client
      ..server = client.server
      ..phase = AppPhase.ready;
    return state;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = normalizeServerAddress(
      prefs.getString(serverStorageKey) ?? '',
    );
    if (stored.isEmpty) {
      phase = AppPhase.setup;
      notifyListeners();
      return;
    }
    final probe = await ApiClient.probe(stored);
    if (probe.ok) {
      server = stored;
      _client = ApiClient(stored);
      phase = AppPhase.transition;
    } else {
      server = stored;
      setupError = probe.message;
      phase = AppPhase.setup;
    }
    notifyListeners();
  }

  Future<String?> connect(String address) async {
    final normalized = normalizeServerAddress(address);
    if (normalized.isEmpty) return 'Saisissez une adresse.';
    busy = true;
    setupError = '';
    notifyListeners();
    final probe = await ApiClient.probe(normalized);
    busy = false;
    if (!probe.ok) {
      setupError = probe.message;
      notifyListeners();
      return probe.message;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(serverStorageKey, normalized);
    server = normalized;
    _client = ApiClient(normalized);
    phase = AppPhase.transition;
    setupError = '';
    notifyListeners();
    return null;
  }

  void finishTransition() {
    if (phase != AppPhase.transition) return;
    phase = AppPhase.ready;
    notifyListeners();
  }

  /// Opens the setup screen without forgetting the saved address.
  void requestServerChange() {
    phase = AppPhase.setup;
    setupError = '';
    notifyListeners();
  }

  Future<void> forgetServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(serverStorageKey);
    server = '';
    _client = null;
    phase = AppPhase.setup;
    setupError = '';
    notifyListeners();
  }
}
