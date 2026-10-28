import 'package:dio/dio.dart';
import 'package:documind_phone/api/api_client.dart';
import 'package:documind_phone/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeServerAddress', () {
    test('adds scheme and strips trailing slashes', () {
      expect(
        normalizeServerAddress(' 192.168.1.50:8000/ '),
        'http://192.168.1.50:8000',
      );
      expect(
        normalizeServerAddress('https://docs.local/'),
        'https://docs.local',
      );
      expect(normalizeServerAddress(''), '');
    });
  });

  group('ApiClient', () {
    test('parses a document page', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.path, '/api/documents');
            expect(options.uri.queryParameters['limit'], '2');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'documents': [
                    {
                      'id': 'abc',
                      'filename': 'facture.pdf',
                      'filepath': '/data/facture.pdf',
                      'status': 'ready',
                      'title': 'Facture',
                      'doc_type': 'facture',
                      'montant': 42.5,
                      'tags': ['test'],
                      'created_at': '2026-10-20T10:00:00',
                      'updated_at': '2026-10-20T11:00:00',
                    },
                  ],
                  'total': 1,
                  'limit': 2,
                  'offset': 0,
                },
              ),
            );
          },
        ),
      );
      final api = ApiClient('test.local', dio: dio);
      final page = await api.documents(limit: 2);
      expect(page.total, 1);
      expect(page.documents.single.title, 'Facture');
      expect(page.documents.single.montant, 42.5);
      expect(page.documents.single.tags, ['test']);
      expect(page.documents.single.isReady, isTrue);
    });

    test('maps a server detail to ApiException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 404,
                data: {'detail': 'Document inconnu'},
              ),
            ),
          ),
        ),
      );
      final api = ApiClient('test.local', dio: dio);
      await expectLater(
        api.document('missing'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Document inconnu')
              .having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test('uses a friendly message for a 503 without detail', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 503),
            ),
          ),
        ),
      );
      final api = ApiClient('test.local', dio: dio);
      await expectLater(
        api.stats(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
    });
  });

  group('DocumentModel', () {
    test('tolerates null and string numeric fields', () {
      final document = DocumentModel.fromJson({
        'id': '1',
        'filename': 'scan.jpg',
        'filepath': '/tmp/scan.jpg',
        'status': 'processing',
        'pages_done': '2',
        'pages_total': '4',
        'montant': '19.99',
        'tags': null,
      });
      expect(document.pagesDone, 2);
      expect(document.progress, 0.5);
      expect(document.montant, 19.99);
      expect(document.tags, isEmpty);
      expect(document.isImage, isTrue);
      expect(document.isProcessing, isTrue);
      expect(document.displayTitle, 'scan.jpg');
    });
  });
}
