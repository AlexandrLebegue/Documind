import 'dart:async';
import 'dart:io';

import 'package:documind_phone/models/document.dart';
import 'package:documind_phone/models/queue.dart';
import 'package:documind_phone/api/api_client.dart';
import 'package:documind_phone/screens/home_shell.dart';
import 'package:documind_phone/screens/document_detail_screen.dart';
import 'package:documind_phone/state/app_state.dart';
import 'package:documind_phone/state/transfer_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens_test.dart' show harness;
import 'support/fake_api.dart';
import 'upload_regression_test.dart' show pumpUntil;

class ProcessingApi extends FakeApiClient {
  QueueStatus queueResult = const QueueStatus(
    active: QueueJob(
      id: 'job-other',
      label: 'autre.pdf',
      status: 'processing',
      position: 0,
    ),
    pending: [
      QueueJob(
        id: 'job-upload',
        label: 'test.pdf',
        status: 'pending',
        position: 1,
      ),
      QueueJob(
        id: 'job-last',
        label: 'dernier.pdf',
        status: 'pending',
        position: 2,
      ),
    ],
    totalActive: 1,
    totalPending: 2,
  );
  String status = 'queued';
  int pagesDone = 0;
  int pagesTotal = 0;
  int uploads = 0;
  int reprocesses = 0;
  bool queueFails = false;
  Completer<UploadResult> uploadResult = Completer<UploadResult>();
  void Function(int, int)? progress;

  @override
  Future<QueueStatus> queue() async {
    if (queueFails) throw ApiException('Connexion impossible');
    return queueResult;
  }

  @override
  Future<DocumentModel> document(String id) async => DocumentModel.fromJson({
    'id': id,
    'filename': 'test.pdf',
    'status': status,
    'pages_done': pagesDone,
    'pages_total': pagesTotal,
    if (status == 'error') 'error_message': 'Le serveur a refusé l’analyse.',
  });

  @override
  Future<UploadResult> uploadDocument(
    File file, {
    String source = 'phone',
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) {
    uploads++;
    progress = onProgress;
    return uploadResult.future;
  }

  @override
  Future<void> reprocessDocument(String id) async {
    reprocesses++;
    status = 'queued';
  }

  void completeUpload() => uploadResult.complete(
    const UploadResult(
      id: 'doc',
      filename: 'test.pdf',
      status: 'queued',
      message: '',
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets(
    'global badge reopens full queue; bytes, OCR, LLM and ready remain visible at 360dp',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync('phone_progress_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/test.pdf')
        ..writeAsStringSync('%PDF-synthetic');
      final api = ProcessingApi();
      final state = AppState.withClient(api);
      final transfers = state.transfers!;
      await tester.pumpWidget(harness(const HomeShell(), state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('global-transfer-badge')));
      await tester.pumpAndSettle();
      expect(find.text('autre.pdf'), findsOneWidget);
      expect(find.text('dernier.pdf'), findsOneWidget);
      expect(find.text('En file · position 2'), findsOneWidget);
      transfers.add([UploadInput('test.pdf', () async => file)]);
      await tester.pump();
      expect(find.text('Envoi…'), findsOneWidget);
      await pumpUntil(tester, () => api.progress != null);
      api.progress!(32, 100);
      await tester.pump();
      expect(find.text('32 / 100 octets'), findsOneWidget);
      await tester.tap(find.byTooltip('Fermer le suivi'));
      await tester.pumpAndSettle();
      api.completeUpload();
      await pumpUntil(tester, () => transfers.tasks.single.document != null);
      await tester.tap(find.byKey(const ValueKey('global-transfer-badge')));
      await tester.pumpAndSettle();
      expect(find.text('En file · position 1'), findsWidgets);
      api.status = 'processing';
      api.pagesTotal = 4;
      api.pagesDone = 2;
      await transfers.refresh();
      await tester.pump();
      expect(find.text('OCR page 2/4'), findsOneWidget);
      api.pagesDone = 4;
      await transfers.refresh();
      await tester.pump();
      expect(find.text('Analyse LLM…'), findsOneWidget);
      api.status = 'ready';
      await transfers.refresh();
      await tester.pump();
      expect(find.text('Terminé'), findsOneWidget);
      expect(find.text('Voir la fiche'), findsOneWidget);
      await tester.tap(find.text('Voir la fiche'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DocumentDetailScreen>(find.byType(DocumentDetailScreen))
            .documentId,
        'doc',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'upload failure is shown and retry uploads again; server error retries reprocessing',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('phone_retry_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/test.pdf')
        ..writeAsStringSync('%PDF-synthetic');
      final api = ProcessingApi();
      final state = AppState.withClient(api);
      final transfers = state.transfers!;
      await tester.pumpWidget(harness(const HomeShell(), state: state));
      await tester.pumpAndSettle();
      transfers.add([UploadInput('test.pdf', () async => file)]);
      await pumpUntil(tester, () => api.uploads == 1);
      api.uploadResult.completeError(ApiException('Réseau coupé'));
      await pumpUntil(tester, () => transfers.tasks.single.error != null);
      await tester.tap(find.byKey(const ValueKey('global-transfer-badge')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Réseau coupé'), findsOneWidget);
      api.uploadResult = Completer<UploadResult>();
      await tester.tap(find.text('Réessayer'));
      await pumpUntil(tester, () => api.uploads == 2);
      api.status = 'error';
      api.completeUpload();
      await pumpUntil(
        tester,
        () => transfers.tasks.single.document?.status == 'error',
      );
      expect(find.text('Le serveur a refusé l’analyse.'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      expect(api.reprocesses, 1);
      expect(api.uploads, 2);
      api.queueFails = true;
      await transfers.refresh();
      await tester.pump();
      expect(
        find.textContaining('File d’attente indisponible'),
        findsOneWidget,
      );
      api.queueFails = false;
      await tester.tap(find.text('Réessayer le suivi'));
      await tester.pump();
      expect(find.textContaining('File d’attente indisponible'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
