import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:documind_phone/api/api_client.dart';
import 'package:documind_phone/screens/add_document_sheet.dart';
import 'package:documind_phone/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'screens_test.dart' show harness;

const _gallery = MethodChannel('plugins.flutter.io/image_picker');
const _files = MethodChannel('miguelruivo.flutter.plugins.filepicker');
const _scanner = MethodChannel('cunning_document_scanner');
const _paths = MethodChannel('plugins.flutter.io/path_provider');

// Exercise Dio's real multipart serialization and progress callbacks. Only the
// transport is replaced: the widget must actually start a POST with file bytes.
class UploadTransport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = await requestStream?.fold<List<int>>(
      [],
      (buffer, part) => buffer..addAll(part),
    );
    if (options.method == 'POST') bodies.add(latin1.decode(bytes ?? []));
    final data = options.method == 'POST'
        ? {'id': 'uploaded', 'filename': 'regression.png', 'status': 'queued'}
        : options.path == '/queue'
        ? {'pending': [], 'total_pending': 0, 'total_active': 0}
        : {'id': 'uploaded', 'filename': 'regression.png', 'status': 'ready'};
    return ResponseBody.fromString(
      jsonEncode(data),
      options.method == 'POST' ? 202 : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
  expect(done(), isTrue);
}

Widget _addHarness(AppState state) => harness(
  Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showAddDocumentSheet(context),
        child: const Text('Ajouter'),
      ),
    ),
  ),
  state: state,
);

void main() {
  for (final source in [
    'Depuis la galerie',
    'Choisir un fichier',
    'Scanner un document',
  ]) {
    testWidgets('$source: result after sheet disposal sends multipart POST', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('phone_upload_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/regression.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 30, height: 40)));
      final selected = Completer<dynamic>();
      final channel = source == 'Depuis la galerie'
          ? _gallery
          : source == 'Choisir un fichier'
          ? _files
          : _scanner;
      var pickerCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) {
        if (call.method == 'cleanCache') return Future.value();
        pickerCalls++;
        if (channel == _files) {
          expect(call.method, 'custom');
          expect(call.arguments['allowedExtensions'], [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'txt',
          ]);
        }
        return selected.future;
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _paths,
        (_) async => directory.path,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _paths,
          null,
        );
      });
      final transport = UploadTransport();
      final state = AppState.withClient(
        ApiClient('test.local', dio: Dio()..httpClientAdapter = transport),
      );
      await tester.pumpWidget(_addHarness(state));
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source));
      await tester.pumpAndSettle();
      expect(find.byType(AddDocumentSheet), findsNothing);
      expect(pickerCalls, 1);
      selected.complete(
        channel == _files
            ? [
                {
                  'path': file.path,
                  'name': 'regression.png',
                  'size': file.lengthSync(),
                  'bytes': null,
                },
              ]
            : [file.path],
      );
      if (channel == _scanner) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('Créer le PDF'));
      }
      await pumpUntil(tester, () => transport.bodies.isNotEmpty);
      final post = transport.requests.singleWhere(
        (request) => request.method == 'POST',
      );
      expect(post.uri.path, '/api/documents/upload');
      expect(
        transport.bodies.single,
        contains(channel == _scanner ? '%PDF-' : 'PNG'),
      );
      expect(
        transport.bodies.single,
        contains(channel == _scanner ? 'phone_scan' : 'phone'),
      );
      expect(transport.bodies.single, contains('name="file"'));
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });

    testWidgets('$source: native error is visible in French', (tester) async {
      final channel = source == 'Depuis la galerie'
          ? _gallery
          : source == 'Choisir un fichier'
          ? _files
          : _scanner;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'permission_denied',
          message: 'Accès refusé',
        );
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final transport = UploadTransport();
      final state = AppState.withClient(
        ApiClient('test.local', dio: Dio()..httpClientAdapter = transport),
      );
      await tester.pumpWidget(_addHarness(state));
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          channel == _scanner
              ? 'Accès à la caméra refusé'
              : 'Import impossible',
        ),
        findsOneWidget,
      );
      expect(transport.bodies, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });

    testWidgets('$source: cancellation leaves the app usable', (tester) async {
      final channel = source == 'Depuis la galerie'
          ? _gallery
          : source == 'Choisir un fichier'
          ? _files
          : _scanner;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final transport = UploadTransport();
      final state = AppState.withClient(
        ApiClient('test.local', dio: Dio()..httpClientAdapter = transport),
      );
      await tester.pumpWidget(_addHarness(state));
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(transport.bodies, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
}
