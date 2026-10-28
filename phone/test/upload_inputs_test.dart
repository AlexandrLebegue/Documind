import 'dart:async';
import 'dart:io';

import 'package:documind_phone/screens/add_document_sheet.dart';
import 'package:documind_phone/screens/scanner_flow.dart';
import 'package:documind_phone/state/transfer_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    directory = Directory.systemTemp.createTempSync('phone_inputs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test('file URI is normalized and bytes-only provider is preserved', () async {
    final original = File('${directory.path}/avec espace.pdf')
      ..writeAsStringSync('%PDF-test');
    final uri = await materializePickedFile(
      PlatformFile(
        name: 'avec espace.pdf',
        size: 9,
        path: original.uri.toString(),
      ),
    );
    expect(await uri.readAsString(), '%PDF-test');
    final bytes = await materializePickedFile(
      PlatformFile(
        name: 'bytes.pdf',
        size: 9,
        bytes: Uint8List.fromList('%PDF-test'.codeUnits),
      ),
    );
    expect(await bytes.readAsString(), '%PDF-test');
  });

  test('stream-only provider is cached so retry can read it twice', () async {
    final picked = PlatformFile(
      name: 'stream.pdf',
      size: 9,
      path: 'content://provider/document/123',
      readStream: Stream.value('%PDF-test'.codeUnits),
    );
    final input = UploadInput(picked.name, () => materializePickedFile(picked));
    expect(await (await input.file()).readAsString(), '%PDF-test');
    expect(await (await input.file()).readAsString(), '%PDF-test');
  });

  test('inaccessible selection reports an explicit error', () async {
    await expectLater(
      materializePickedFile(PlatformFile(name: 'absent.pdf', size: 9)),
      throwsA(
        predicate((error) => error.toString().contains('Fichier inaccessible')),
      ),
    );
  });

  for (final size in [0, 50 * 1024 * 1024 + 1]) {
    test(
      '$size byte input fails before any upload and remains retryable',
      () async {
        final file = File('${directory.path}/invalid.pdf');
        final handle = file.openSync(mode: FileMode.write);
        handle.truncateSync(size);
        handle.closeSync();
        final transfers = TransferState(FakeApiClient());
        final finished = Completer<void>();
        transfers.addListener(() {
          if (transfers.tasks.isNotEmpty &&
              !transfers.tasks.single.sending &&
              !finished.isCompleted) {
            finished.complete();
          }
        });
        try {
          transfers.add([UploadInput('invalid.pdf', () async => file)]);
          await finished.future.timeout(const Duration(seconds: 3));
          expect(transfers.tasks.single.documentId, isNull);
          expect(
            transfers.tasks.single.error,
            contains(size == 0 ? 'vide' : '50 Mo'),
          );
          expect(transfers.hasErrors, isTrue);
        } finally {
          transfers.dispose();
        }
      },
    );
  }

  test('PDF never silently drops an unreadable scanner page', () async {
    final page = File('${directory.path}/page.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 20, height: 30)));
    await expectLater(
      buildPdfFromPages([
        page.path,
        '${directory.path}/absente.png',
      ], outputDirectory: directory),
      throwsA(predicate((error) => error.toString().contains('page 2'))),
    );
  });
}
