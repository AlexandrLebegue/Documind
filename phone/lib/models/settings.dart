class ServerSettings {
  const ServerSettings({
    this.version,
    this.aiProvider = 'openrouter',
    this.openrouterApiKey = '',
    this.openrouterModel = '',
    this.openrouterBaseUrl = '',
    this.ollamaBaseUrl = '',
    this.ollamaModel = '',
    this.llamacppBaseUrl = '',
    this.llamacppModel = '',
    this.dataDir = '',
    this.nasSyncEnabled = false,
    this.nasHost = '',
    this.nasShare = '',
    this.nasPath = '',
    this.nasUsername = '',
    this.nasSyncHour = 7,
    this.nasSyncMinute = 0,
  });

  final String? version;
  final String aiProvider;
  final String openrouterApiKey;
  final String openrouterModel;
  final String openrouterBaseUrl;
  final String ollamaBaseUrl;
  final String ollamaModel;
  final String llamacppBaseUrl;
  final String llamacppModel;
  final String dataDir;
  final bool nasSyncEnabled;
  final String nasHost;
  final String nasShare;
  final String nasPath;
  final String nasUsername;
  final int nasSyncHour;
  final int nasSyncMinute;

  factory ServerSettings.fromJson(Map<String, dynamic> json) {
    return ServerSettings(
      version: json['version']?.toString(),
      aiProvider: (json['ai_provider'] ?? 'openrouter').toString(),
      openrouterApiKey: (json['openrouter_api_key'] ?? '').toString(),
      openrouterModel: (json['openrouter_model'] ?? '').toString(),
      openrouterBaseUrl: (json['openrouter_base_url'] ?? '').toString(),
      ollamaBaseUrl: (json['ollama_base_url'] ?? '').toString(),
      ollamaModel: (json['ollama_model'] ?? '').toString(),
      llamacppBaseUrl: (json['llamacpp_base_url'] ?? '').toString(),
      llamacppModel: (json['llamacpp_model'] ?? '').toString(),
      dataDir: (json['data_dir'] ?? '').toString(),
      nasSyncEnabled: json['nas_sync_enabled'] == true,
      nasHost: (json['nas_host'] ?? '').toString(),
      nasShare: (json['nas_share'] ?? '').toString(),
      nasPath: (json['nas_path'] ?? '').toString(),
      nasUsername: (json['nas_username'] ?? '').toString(),
      nasSyncHour: (json['nas_sync_hour'] as num?)?.toInt() ?? 7,
      nasSyncMinute: (json['nas_sync_minute'] as num?)?.toInt() ?? 0,
    );
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.upToDate,
    required this.localCommit,
    required this.remoteCommit,
    required this.behindBy,
    this.error,
  });

  final bool upToDate;
  final String localCommit;
  final String remoteCommit;
  final int behindBy;
  final String? error;

  factory UpdateCheckResult.fromJson(Map<String, dynamic> json) {
    return UpdateCheckResult(
      upToDate: json['up_to_date'] == true,
      localCommit: (json['local_commit'] ?? '').toString(),
      remoteCommit: (json['remote_commit'] ?? '').toString(),
      behindBy: (json['behind_by'] as num?)?.toInt() ?? 0,
      error: json['error']?.toString(),
    );
  }
}

class NasSyncResult {
  const NasSyncResult({
    required this.scanned,
    required this.imported,
    required this.skipped,
    required this.errors,
    this.errorMessage,
  });

  final int scanned;
  final int imported;
  final int skipped;
  final int errors;
  final String? errorMessage;

  factory NasSyncResult.fromJson(Map<String, dynamic> json) {
    return NasSyncResult(
      scanned: (json['scanned'] as num?)?.toInt() ?? 0,
      imported: (json['imported'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
      errorMessage: json['error_message']?.toString(),
    );
  }
}
