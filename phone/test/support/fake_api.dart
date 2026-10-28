import 'package:documind_phone/api/api_client.dart';
import 'package:documind_phone/models/alert.dart';
import 'package:documind_phone/models/chat.dart';
import 'package:documind_phone/models/document.dart';
import 'package:documind_phone/models/ingest.dart';
import 'package:documind_phone/models/procedure.dart';
import 'package:documind_phone/models/settings.dart';
import 'package:documind_phone/models/stats.dart';

DocumentModel testDocument({
  String id = 'doc-1',
  String filename = 'facture-edf.pdf',
  String? title = 'Facture EDF octobre',
  String status = 'ready',
  String docType = 'facture',
}) {
  final now = DateTime(2026, 10, 20, 12);
  return DocumentModel(
    id: id,
    filename: filename,
    filepath: '/data/$filename',
    status: status,
    createdAt: now,
    updatedAt: now,
    title: title,
    docType: docType,
    emetteur: 'EDF',
    montant: 84.5,
    tags: const ['énergie'],
    textContent: 'Contenu OCR de test.',
  );
}

class FakeApiClient extends ApiClient {
  FakeApiClient() : super('http://test.local');

  final documentsResult = <DocumentModel>[
    testDocument(),
    testDocument(
      id: 'doc-2',
      filename: 'bulletin.pdf',
      title: 'Bulletin de paie',
    ),
  ];

  @override
  Future<DocumentModel> document(String id) async =>
      documentsResult.firstWhere((doc) => doc.id == id);

  @override
  Future<List<DocumentModel>> segments(String id) async => const [];

  @override
  Future<Health> health() async => const Health(
    status: 'ok',
    llmLoaded: true,
    embeddingModelLoaded: true,
    totalDocuments: 2,
    version: 'test',
  );

  @override
  Future<Stats> stats() async => Stats(
    totalDocuments: documentsResult.length,
    countByType: const {'facture': 1, 'fiche_de_paie': 1},
    countByMonth: const {'2026-10': 2},
    recentDocuments: documentsResult,
    expiringSoonCount: 0,
    overdueCount: 0,
  );

  @override
  Future<DocumentPage> documents({
    String? query,
    String? docType,
    int limit = 24,
    int offset = 0,
  }) async => DocumentPage(
    documents: documentsResult,
    total: documentsResult.length,
    limit: limit,
    offset: offset,
  );

  @override
  Future<AlertsResponse> alerts({
    int daysAhead = 365,
    int limit = 100,
    String? urgency,
  }) async => const AlertsResponse(
    alerts: [],
    total: 0,
    expiringCount: 0,
    overdueCount: 0,
    upcomingPayments: 0,
  );

  @override
  Future<List<RenewalSuggestion>> renewalSuggestions() async => const [];

  @override
  Future<List<GapAlert>> gapAlerts() async => const [];

  @override
  Future<List<ChatSession>> chatSessions() async => const [];

  @override
  Future<List<ChatMessage>> chatHistory(String sessionId) async => const [];

  @override
  Future<List<Procedure>> procedures({int limit = 100, int offset = 0}) async =>
      const [];

  @override
  Future<IngestMarksResponse> ingestMarks({
    String? verdict,
    int limit = 100,
    int offset = 0,
  }) async => const IngestMarksResponse(marks: [], total: 0, counts: {});

  @override
  Future<ServerSettings> settings() async => const ServerSettings(
    version: 'test',
    aiProvider: 'llamacpp',
    llamacppBaseUrl: 'http://llm:8080',
    llamacppModel: 'qwen',
  );
}
