import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:documind_phone/api/api_client.dart';
import 'package:documind_phone/models/chat.dart';

Future<void> main(List<String> args) async {
  final address = args.isNotEmpty ? args.first : 'http://192.168.1.50:8000';
  final imagePath = args.length > 1 ? args[1] : '';
  final api = ApiClient(address);

  final probe = await ApiClient.probe(address);
  if (!probe.ok) {
    stderr.writeln('Probe: ${probe.message}');
    exit(1);
  }
  stdout.writeln('probe ok');

  final health = await api.health();
  stdout.writeln('health: ${health.status}');

  final stats = await api.stats();
  stdout.writeln('stats: ${stats.totalDocuments} documents');

  final page = await api.documents(limit: 2);
  stdout.writeln(
    'documents: ${page.total} total, ${page.documents.length} lus',
  );
  if (page.documents.isNotEmpty) {
    final document = await api.document(page.documents.first.id);
    stdout.writeln('document: ${document.status} · ${document.displayTitle}');
  }

  final alerts = await api.alerts(daysAhead: 365, limit: 2);
  stdout.writeln(
    'alerts: ${alerts.total} · expirés=${alerts.overdueCount} · '
    'expirent=${alerts.expiringCount}',
  );

  final procedures = await api.procedures(limit: 2);
  stdout.writeln('procedures: ${procedures.length} lues');

  final marks = await api.ingestMarks(limit: 2);
  stdout.writeln('ingest: ${marks.total} marques');

  final settings = await api.settings();
  stdout.writeln(
    'settings: provider=${settings.aiProvider} version=${settings.version}',
  );

  final logCompleter = Completer<void>();
  final logToken = CancelToken();
  final logLines = <String>[];
  final logSub = api
      .logs(cancelToken: logToken)
      .listen(
        (line) {
          logLines.add(line);
          if (logLines.length >= 3 && !logCompleter.isCompleted) {
            logCompleter.complete();
          }
        },
        onError: (Object error) {
          if (!logCompleter.isCompleted) logCompleter.completeError(error);
        },
      );
  try {
    await logCompleter.future.timeout(const Duration(seconds: 10));
  } finally {
    logToken.cancel('smoke');
    await logSub.cancel();
  }
  stdout.writeln('logs: ${logLines.length} ligne(s)');

  String? sessionId;
  final reply = StringBuffer();
  final streamToken = CancelToken();
  await for (final event
      in api
          .streamAgent(
            'Réponds uniquement par le mot OK, sans outil.',
            cancelToken: streamToken,
          )
          .timeout(const Duration(seconds: 120))) {
    switch (event) {
      case AgentSessionEvent():
        sessionId = event.sessionId;
      case AgentDone():
        sessionId = event.sessionId;
        reply.write(event.reply);
      case AgentError():
        throw StateError(event.message);
      default:
        break;
    }
  }
  stdout.writeln('chat stream: "${reply.toString().trim()}"');
  if (sessionId != null) {
    await api.deleteChatSession(sessionId);
    stdout.writeln('chat session supprimée');
  }

  if (imagePath.isNotEmpty) {
    final file = File(imagePath);
    final uploaded = await api.uploadDocument(file, source: 'phone_smoke');
    stdout.writeln('upload: ${uploaded.id} (${uploaded.status})');
    var status = uploaded.status;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final document = await api.document(uploaded.id);
      status = document.status;
      if (status == 'ready' || status == 'error') break;
    }
    stdout.writeln('upload status: $status');
    await api.deleteDocument(uploaded.id);
    stdout.writeln('upload supprimé');
  }

  stdout.writeln('smoke ok');
}
