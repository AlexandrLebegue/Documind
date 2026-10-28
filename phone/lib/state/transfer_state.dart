import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/document.dart';
import '../models/queue.dart';

class UploadInput {
  UploadInput(this.name, this.load);

  final String name;
  final Future<File> Function() load;
  File? _cached;

  Future<File> file() async => _cached ??= await load();
}

class UploadTask {
  UploadTask(this.input, this.source);

  final UploadInput input;
  final String source;
  bool sending = true;
  int sent = 0;
  int total = 0;
  String? documentId;
  DocumentModel? document;
  String? error;

  bool get isComplete =>
      document?.isReady == true || document?.status == 'segmented';

  bool get isBusy => sending || (error == null && !isComplete);
}

/// Owns transfers independently of picker, modal and navigation lifetimes.
class TransferState extends ChangeNotifier {
  TransferState(this.api);

  final ApiClient api;
  final List<UploadTask> tasks = [];
  QueueStatus? queue;
  String? pollError;
  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;

  int get busyCount {
    final local = tasks.where((task) => task.isBusy).length;
    final remote = (queue?.totalActive ?? 0) + (queue?.totalPending ?? 0);
    // Local tasks overlap with the server queue after upload.
    final sending = tasks.where((task) => task.sending).length;
    return local > remote + sending ? local : remote + sending;
  }

  bool get hasErrors =>
      pollError != null || tasks.any((task) => task.error != null);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void startPolling() {
    if (_disposed || _timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void add(List<UploadInput> inputs, {String source = 'phone'}) {
    final added = [for (final input in inputs) UploadTask(input, source)];
    tasks.addAll(added);
    _changed();
    startPolling();
    unawaited(_sendAll(added));
  }

  Future<void> _sendAll(List<UploadTask> added) async {
    for (final task in added) {
      if (_disposed) return;
      await _send(task);
    }
  }

  Future<void> _send(UploadTask task) async {
    task.sending = true;
    task.error = null;
    task.sent = 0;
    task.total = 0;
    _changed();
    try {
      final file = await task.input.file();
      final length = await file.length();
      if (length == 0) throw ApiException('Le fichier est vide.');
      if (length > 50 * 1024 * 1024) {
        throw ApiException('Le fichier dépasse la limite de 50 Mo.');
      }
      task.total = length;
      _changed();
      final result = await api.uploadDocument(
        file,
        source: task.source,
        onProgress: (sent, total) {
          task.sent = sent;
          task.total = total;
          _changed();
        },
      );
      if (result.id.isEmpty) {
        throw ApiException(
          'Le serveur n’a pas renvoyé le document. Réessayez.',
        );
      }
      task.documentId = result.id;
      task.sent = task.total;
    } catch (error) {
      task.error = 'Envoi impossible : $error';
    } finally {
      task.sending = false;
      _changed();
    }
    await refresh();
  }

  Future<void> retry(UploadTask task) async {
    if (task.sending) return;
    if (task.documentId == null) {
      await _send(task);
      return;
    }
    task.sending = true;
    task.error = null;
    _changed();
    try {
      await api.reprocessDocument(task.documentId!);
      task.document = null;
    } catch (error) {
      task.error = 'Nouvelle analyse impossible : $error';
    } finally {
      task.sending = false;
      _changed();
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    final errors = <String>[];
    try {
      try {
        queue = await api.queue();
      } catch (error) {
        errors.add('File d’attente indisponible : $error');
      }
      // Each result is independent: a failing document must not hide the others.
      for (final task in tasks.toList()) {
        if (_disposed) return;
        if (task.documentId == null || task.sending || task.isComplete) {
          continue;
        }
        try {
          task.document = await api.document(task.documentId!);
          task.error = task.document!.status == 'error'
              ? task.document!.errorMessage ??
                    'Le traitement du document a échoué.'
              : null;
        } catch (error) {
          errors.add('Statut de ${task.input.name} indisponible : $error');
        }
      }
      pollError = errors.isEmpty ? null : errors.join('\n');
      _changed();
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
