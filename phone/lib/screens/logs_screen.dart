import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _scroll = ScrollController();
  final _lines = <String>[];
  StreamSubscription<String>? _subscription;
  CancelToken? _cancelToken;
  bool _connected = false;
  bool _paused = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cancelToken?.cancel('dispose');
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    await _subscription?.cancel();
    _cancelToken?.cancel('reconnect');
    final token = CancelToken();
    _cancelToken = token;
    setState(() => _error = null);
    _subscription = api
        .logs(cancelToken: token)
        .listen(
          (line) {
            if (!mounted) return;
            setState(() {
              _connected = true;
              if (_paused) return;
              _lines.add(line);
              if (_lines.length > 2000) {
                _lines.removeRange(0, _lines.length - 2000);
              }
            });
            if (!_paused) _scrollToBottom();
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _connected = false;
              _error = shortErrorMessage(error);
            });
          },
          onDone: () {
            if (mounted) setState(() => _connected = false);
          },
          cancelOnError: true,
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Color _color(String line) {
    if (line.contains(' ERROR')) return const Color(0xFFF87171);
    if (line.contains(' WARNING')) return const Color(0xFFFACC15);
    if (line.contains(' INFO')) return const Color(0xFFD4D4D8);
    return const Color(0xFF71717A);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090B),
        foregroundColor: Colors.white,
        title: const Text('Journaux'),
        actions: [
          IconButton(
            tooltip: _paused ? 'Reprendre' : 'Pause',
            onPressed: () => setState(() => _paused = !_paused),
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: 'Effacer',
            onPressed: () => setState(_lines.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'Reconnecter',
            onPressed: _connect,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _connected
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _connected ? 'Connecté' : 'Déconnecté',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: _connected
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_lines.length} ligne(s)',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF71717A),
                  ),
                ),
                const Spacer(),
                if (_paused)
                  const Text(
                    'En pause',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFACC15),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF450A0A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Flux interrompu : $_error',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFFFCA5A5),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: _lines.isEmpty
                  ? const Text(
                      'En attente de logs…',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF52525B),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: _lines.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: SelectableText(
                          _lines[index],
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            height: 1.45,
                            color: _color(_lines[index]),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
