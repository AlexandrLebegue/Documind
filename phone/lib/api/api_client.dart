import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/alert.dart';
import '../models/chat.dart';
import '../models/document.dart';
import '../models/ingest.dart';
import '../models/procedure.dart';
import '../models/queue.dart';
import '../models/settings.dart';
import '../models/stats.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

String normalizeServerAddress(String value) {
  var address = value.trim().replaceAll(RegExp(r'/+$'), '');
  if (address.isEmpty) return '';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(address)) {
    address = 'http://$address';
  }
  return address;
}

class ApiClient {
  ApiClient(String server, {Dio? dio})
    : server = normalizeServerAddress(server),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 90),
              sendTimeout: const Duration(seconds: 120),
              responseType: ResponseType.json,
              headers: const {'Accept': 'application/json'},
            ),
          ) {
    _dio.options.baseUrl = '${this.server}/api';
  }

  final String server;
  final Dio _dio;

  static Future<({bool ok, String message})> probe(String address) async {
    final normalized = normalizeServerAddress(address);
    if (normalized.isEmpty) {
      return (ok: false, message: 'Saisissez une adresse.');
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: const {'Accept': 'application/json'},
      ),
    );
    try {
      final response = await dio.get('$normalized/api/system');
      if (response.statusCode == 200) {
        return (ok: true, message: '');
      }
      return (
        ok: false,
        message:
            'Le serveur a répondu ${response.statusCode}. Vérifiez l’adresse.',
      );
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != null) {
        return (
          ok: false,
          message: 'Le serveur a répondu $code. Vérifiez l’adresse.',
        );
      }
      return (
        ok: false,
        message:
            'Serveur injoignable. Vérifiez l’adresse, le port et que DocuMind est démarré.',
      );
    } catch (_) {
      return (
        ok: false,
        message: 'Serveur injoignable. Vérifiez l’adresse et le réseau.',
      );
    }
  }

  Future<T> _get<T>(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<dynamic>(path, queryParameters: query);
      return response.data as T;
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Future<T> _post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        path,
        data: data,
        queryParameters: query,
      );
      return response.data as T;
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Future<T> _put<T>(String path, {Object? data}) async {
    try {
      final response = await _dio.put<dynamic>(path, data: data);
      return response.data as T;
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Future<void> _delete(String path, {Map<String, dynamic>? query}) async {
    try {
      await _dio.delete<dynamic>(path, queryParameters: query);
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  ApiException _translate(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    String? detail;
    if (data is Map) {
      detail = data['detail']?.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      detail = data;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          'Le serveur met trop de temps à répondre.',
          statusCode: status,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          'Connexion au serveur impossible. Vérifiez le réseau.',
          statusCode: status,
        );
      case DioExceptionType.cancel:
        return ApiException('Requête annulée.', statusCode: status);
      default:
        break;
    }
    if (detail != null && detail.trim().isNotEmpty) {
      return ApiException(detail.trim(), statusCode: status);
    }
    if (status == 404) {
      return ApiException(
        'Élément introuvable sur le serveur.',
        statusCode: status,
      );
    }
    if (status == 503) {
      return ApiException(
        'Le serveur n’est pas prêt (modèles IA en cours de chargement).',
        statusCode: status,
      );
    }
    return ApiException(
      'Erreur serveur${status != null ? ' ($status)' : ''}. Réessayez.',
      statusCode: status,
    );
  }

  // ── Health / stats ──────────────────────────────────────────────────────

  Future<Health> health() async =>
      Health.fromJson(await _get<Map<String, dynamic>>('/health'));

  Future<Stats> stats() async =>
      Stats.fromJson(await _get<Map<String, dynamic>>('/stats'));

  Future<QueueStatus> queue() async =>
      QueueStatus.fromJson(await _get<Map<String, dynamic>>('/queue'));

  // ── Documents ───────────────────────────────────────────────────────────

  Future<DocumentPage> documents({
    String? query,
    String? docType,
    int limit = 24,
    int offset = 0,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      '/documents',
      query: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (docType != null && docType.isNotEmpty) 'doc_type': docType,
        'limit': limit,
        'offset': offset,
      },
    );
    return DocumentPage.fromJson(json);
  }

  Future<DocumentModel> document(String id) async => DocumentModel.fromJson(
    await _get<Map<String, dynamic>>('/documents/$id'),
  );

  Future<DocumentModel> updateDocument(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final json = await _put<Map<String, dynamic>>(
      '/documents/$id',
      data: updates,
    );
    return DocumentModel.fromJson(json);
  }

  Future<void> deleteDocument(String id) async => _delete('/documents/$id');

  Future<void> reprocessDocument(String id) async =>
      _post('/documents/$id/reprocess');

  Future<List<DocumentModel>> segments(String id) async {
    final data = await _get<List<dynamic>>('/documents/$id/segments');
    return data
        .whereType<Map<String, dynamic>>()
        .map(DocumentModel.fromJson)
        .toList();
  }

  String documentFileUrl(String id) => '$server/api/documents/$id/file';

  Future<UploadResult> uploadDocument(
    File file, {
    String source = 'phone',
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: _basename(file.path),
      ),
      'source': source,
    });
    try {
      final response = await _dio.post<dynamic>(
        '/documents/upload',
        data: form,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
      );
      final data = response.data as Map<String, dynamic>;
      return UploadResult(
        id: (data['id'] ?? '').toString(),
        filename: (data['filename'] ?? '').toString(),
        status: (data['status'] ?? '').toString(),
        message: (data['message'] ?? '').toString(),
      );
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Future<File> downloadDocument(String id, String filename) async {
    final directory = await _temporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File('${directory.path}/$id-$safeName');
    try {
      await _dio.download(
        '/documents/$id/file',
        target.path,
        deleteOnError: true,
      );
      return target;
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Future<Directory> _temporaryDirectory() async {
    final dir = Directory('${Directory.systemTemp.path}/documind_phone');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Alerts ──────────────────────────────────────────────────────────────

  Future<AlertsResponse> alerts({
    int daysAhead = 365,
    int limit = 100,
    String? urgency,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      '/alerts',
      query: {
        'days_ahead': daysAhead,
        'limit': limit,
        if (urgency != null && urgency.isNotEmpty) 'urgency': urgency,
      },
    );
    return AlertsResponse.fromJson(json);
  }

  Future<List<RenewalSuggestion>> renewalSuggestions() async {
    final json = await _get<Map<String, dynamic>>('/alerts/suggestions');
    return (json['suggestions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RenewalSuggestion.fromJson)
        .toList();
  }

  Future<List<GapAlert>> gapAlerts() async {
    final json = await _get<Map<String, dynamic>>('/alerts/gaps');
    return (json['gaps'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GapAlert.fromJson)
        .toList();
  }

  Future<void> dismissAlert(String docId, String alertType) =>
      _post('/alerts/$docId/dismiss', query: {'alert_type': alertType});

  Future<void> undismissAlert(String docId, String alertType) =>
      _delete('/alerts/$docId/dismiss', query: {'alert_type': alertType});

  // ── Chat ────────────────────────────────────────────────────────────────

  Future<List<ChatSession>> chatSessions() async {
    final json = await _get<Map<String, dynamic>>(
      '/chat/sessions',
      query: {'limit': 100},
    );
    return (json['sessions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatSession.fromJson)
        .toList();
  }

  Future<ChatSession> createChatSession({String? title}) async {
    final json = await _post<Map<String, dynamic>>(
      '/chat/sessions',
      data: {'title': title},
    );
    return ChatSession.fromJson(json);
  }

  Future<ChatSession> renameChatSession(String id, String title) async {
    final json = await _put<Map<String, dynamic>>(
      '/chat/sessions/$id',
      data: {'title': title},
    );
    return ChatSession.fromJson(json);
  }

  Future<void> deleteChatSession(String id) => _delete('/chat/sessions/$id');

  Future<List<ChatMessage>> chatHistory(String sessionId) async {
    final json = await _get<Map<String, dynamic>>(
      '/chat/history',
      query: {'session_id': sessionId, 'limit': 100, 'offset': 0},
    );
    final messages = (json['messages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
    return messages.reversed.toList();
  }

  Future<ChatReply> sendChat(String message, {String? sessionId}) async {
    final json = await _post<Map<String, dynamic>>(
      '/chat',
      data: {'message': message, 'session_id': sessionId},
    );
    return ChatReply.fromJson(json);
  }

  Stream<AgentEvent> streamAgent(
    String message, {
    String? sessionId,
    String? contextProcedure,
    CancelToken? cancelToken,
  }) async* {
    late Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/agent/chat/stream',
        data: {
          'message': message,
          'session_id': sessionId,
          'context_procedure': contextProcedure ?? '',
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: const {'Accept': 'text/event-stream'},
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      throw _translate(error);
    }

    final stream = response.data!.stream.cast<List<int>>().transform(
      const Utf8Decoder(allowMalformed: true),
    );
    final buffer = StringBuffer();
    await for (final text in stream) {
      buffer.write(text);
      var content = buffer.toString();
      var index = content.indexOf('\n');
      while (index >= 0) {
        final line = content.substring(0, index).trimRight();
        content = content.substring(index + 1);
        index = content.indexOf('\n');
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        try {
          final event = _parseAgentEvent(jsonDecode(payload));
          if (event != null) yield event;
        } catch (_) {
          // Ignore malformed SSE frames, like the web client.
        }
      }
      buffer
        ..clear()
        ..write(content);
    }
  }

  AgentEvent? _parseAgentEvent(dynamic raw) {
    if (raw is! Map) return null;
    final type = raw['type']?.toString();
    switch (type) {
      case 'session':
        return AgentSessionEvent((raw['session_id'] ?? '').toString());
      case 'tool_start':
        return AgentToolStart(
          (raw['tool'] ?? '').toString(),
          (raw['args'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'tool_done':
        return AgentToolDone(
          (raw['tool'] ?? '').toString(),
          (raw['args'] as Map?)?.cast<String, dynamic>() ?? const {},
          (raw['result_preview'] ?? '').toString(),
        );
      case 'done':
        return AgentDone(
          (raw['reply'] ?? '').toString(),
          (raw['session_id'] ?? '').toString(),
          (raw['tool_calls_log'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ToolCallLog.fromJson)
              .toList(),
        );
      case 'error':
        return AgentError((raw['message'] ?? 'Erreur inconnue').toString());
      default:
        return null;
    }
  }

  // ── Procedures ──────────────────────────────────────────────────────────

  Future<List<Procedure>> procedures({int limit = 100, int offset = 0}) async {
    final json = await _get<Map<String, dynamic>>(
      '/procedures',
      query: {'limit': limit, 'offset': offset},
    );
    return (json['procedures'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Procedure.fromJson)
        .toList();
  }

  Future<Procedure> procedure(String id) async =>
      Procedure.fromJson(await _get<Map<String, dynamic>>('/procedures/$id'));

  Future<Procedure> createProcedure({
    required String procedureType,
    String? name,
    List<String> manualDocuments = const [],
    String? remarks,
    String? imageBase64,
  }) async {
    final json = await _post<Map<String, dynamic>>(
      '/procedures',
      data: {
        'procedure_type': procedureType,
        'name': name,
        'manual_documents': manualDocuments,
        'remarks': remarks,
        if (imageBase64 != null) 'image_base64': imageBase64,
      },
    );
    return Procedure.fromJson(json);
  }

  Future<Procedure> updateProcedure(
    String id, {
    String? name,
    String? procedureType,
    String? description,
    List<Map<String, String>>? requiredDocuments,
    String? remarks,
  }) async {
    final data = <String, dynamic>{
      if (name != null) 'name': name,
      if (procedureType != null) 'procedure_type': procedureType,
      if (description != null) 'description': description,
      if (requiredDocuments != null) 'required_documents': requiredDocuments,
      if (remarks != null) 'remarks': remarks,
    };
    final json = await _put<Map<String, dynamic>>(
      '/procedures/$id',
      data: data,
    );
    return Procedure.fromJson(json);
  }

  Future<void> deleteProcedure(String id) => _delete('/procedures/$id');

  Future<ProcedureExecution> executeProcedure(
    String id,
    String personName,
  ) async {
    final json = await _post<Map<String, dynamic>>(
      '/procedures/$id/execute',
      data: {'person_name': personName},
    );
    return ProcedureExecution.fromJson(json);
  }

  // ── Ingest marks (sync view, no agent) ──────────────────────────────────

  Future<IngestMarksResponse> ingestMarks({
    String? verdict,
    int limit = 100,
    int offset = 0,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      '/ingest/marks',
      query: {
        if (verdict != null && verdict.isNotEmpty) 'verdict': verdict,
        'limit': limit,
        'offset': offset,
      },
    );
    return IngestMarksResponse.fromJson(json);
  }

  Future<void> acceptIngestMark(String sha256) =>
      _post('/ingest/marks/$sha256/accept');

  Future<void> rejectIngestMark(String sha256) =>
      _post('/ingest/marks/$sha256/reject');

  Future<void> reevaluateIngestMark(String sha256) =>
      _post('/ingest/marks/$sha256/reevaluate');

  // ── Settings ────────────────────────────────────────────────────────────

  Future<ServerSettings> settings() async =>
      ServerSettings.fromJson(await _get<Map<String, dynamic>>('/settings'));

  Future<ServerSettings> updateSettings(Map<String, dynamic> data) async =>
      ServerSettings.fromJson(
        await _put<Map<String, dynamic>>('/settings', data: data),
      );

  Future<UpdateCheckResult> checkUpdate() async => UpdateCheckResult.fromJson(
    await _get<Map<String, dynamic>>('/update/check'),
  );

  Future<void> applyUpdate() => _post('/update/apply');

  Future<NasSyncResult> triggerNasSync() async => NasSyncResult.fromJson(
    await _post<Map<String, dynamic>>('/sync/nas/blocking'),
  );

  Future<bool> testLlamaCpp() async {
    final json = await _post<Map<String, dynamic>>('/llamacpp/test');
    return json['status'] == 'ok';
  }

  // ── Live logs ───────────────────────────────────────────────────────────

  Stream<String> logs({CancelToken? cancelToken}) async* {
    late Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        '/logs',
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(days: 1),
          headers: const {'Accept': 'text/event-stream'},
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      throw _translate(error);
    }
    final lines = StreamController<String>();
    final buffer = StringBuffer();
    response.data!.stream
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (text) {
            buffer.write(text);
            var content = buffer.toString();
            var index = content.indexOf('\n');
            while (index >= 0) {
              final line = content.substring(0, index).trimRight();
              content = content.substring(index + 1);
              index = content.indexOf('\n');
              if (line.startsWith('data:')) {
                lines.add(line.substring(5).trimLeft());
              }
            }
            buffer
              ..clear()
              ..write(content);
          },
          onError: lines.addError,
          onDone: lines.close,
          cancelOnError: true,
        );
    yield* lines.stream;
  }

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? path : parts.last;
  }
}

class UploadResult {
  const UploadResult({
    required this.id,
    required this.filename,
    required this.status,
    required this.message,
  });

  final String id;
  final String filename;
  final String status;
  final String message;
}

Uint8List? decodeBase64Image(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}
