const API_BASE = '/api';

// Types
export interface Document {
  id: string;
  filename: string;
  filepath: string;
  title?: string;
  text_content?: string;
  doc_type?: string;
  emetteur?: string;
  doc_date?: string;
  montant?: number;
  reference?: string;
  destinataire?: string;
  resume?: string;
  tags?: string[];
  date_expiration?: string;
  date_echeance?: string;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface SearchResult {
  document: Document;
  score: number;
  match_type: string;
}

export interface ToolCallLog {
  tool: string;
  args: Record<string, unknown>;
  result_preview: string;
}

export interface ChatMessage {
  id: string;
  session_id?: string;
  message: string;
  role: string;
  context_doc_ids?: string[];
  tool_calls?: ToolCallLog[];
  created_at: string;
}

export interface ChatSession {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
}

export interface Stats {
  total_documents: number;
  count_by_type: Record<string, number>;
  count_by_month: Record<string, number>;
  recent_documents: Document[];
  expiring_soon_count: number;
  overdue_count: number;
}

export interface Health {
  status: string;
  llm_loaded: boolean;
  embedding_model_loaded: boolean;
  total_documents: number;
  version?: string;
}

export interface Settings {
  version?: string;
  ai_provider: string;
  openrouter_api_key: string;
  openrouter_model: string;
  openrouter_base_url: string;
  ollama_base_url: string;
  ollama_model: string;
  llamacpp_base_url: string;
  llamacpp_model: string;
  data_dir: string;
  nas_sync_enabled: boolean;
  nas_host: string;
  nas_share: string;
  nas_path: string;
  nas_username: string;
  nas_sync_hour: number;
  nas_sync_minute: number;
}

export interface SettingsUpdate {
  ai_provider?: string;
  openrouter_api_key?: string;
  openrouter_model?: string;
  openrouter_base_url?: string;
  ollama_base_url?: string;
  ollama_model?: string;
  llamacpp_base_url?: string;
  llamacpp_model?: string;
  nas_sync_enabled?: boolean;
  nas_host?: string;
  nas_share?: string;
  nas_path?: string;
  nas_username?: string;
  nas_password?: string;
  nas_sync_hour?: number;
  nas_sync_minute?: number;
}

export interface NasSyncResult {
  scanned: number;
  imported: number;
  skipped: number;
  errors: number;
  files_imported: string[];
  files_errors: string[];
  error_message?: string;
}

// Procedure types
export interface ProcedureRequiredDocument {
  doc_type: string;
  label: string;
  description?: string;
}

export interface Procedure {
  id: string;
  name: string;
  procedure_type: string;
  description?: string;
  required_documents: ProcedureRequiredDocument[];
  remarks?: string;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface MatchedDocument {
  required_doc_type: string;
  required_label: string;
  found: boolean;
  document?: Document;
}

export interface ProcedureExecution {
  id: string;
  procedure_id: string;
  person_name: string;
  matched_documents: MatchedDocument[];
  status: string;
  created_at: string;
}

// Generic fetch wrapper with error handling
async function fetchAPI<T>(path: string, options?: RequestInit): Promise<T> {
  const url = `${API_BASE}${path}`;
  const res = await fetch(url, {
    ...options,
    headers: {
      ...(options?.body instanceof FormData ? {} : { 'Content-Type': 'application/json' }),
      ...options?.headers,
    },
  });

  if (!res.ok) {
    const errorBody = await res.text().catch(() => '');
    throw new Error(`API Error ${res.status}: ${errorBody || res.statusText}`);
  }

  // Handle 204 No Content
  if (res.status === 204) {
    return undefined as T;
  }

  return res.json();
}

// Document file URL (for <img> / <iframe> src)
export function getDocumentFileUrl(id: string): string {
  return `${API_BASE}/documents/${id}/file`;
}

// Document operations
export async function uploadDocument(file: File): Promise<{ id: string; filename: string; status: string; message: string }> {
  const formData = new FormData();
  formData.append('file', file);
  return fetchAPI('/documents/upload', { method: 'POST', body: formData });
}

export async function getDocuments(params?: {
  doc_type?: string;
  emetteur?: string;
  date_from?: string;
  date_to?: string;
  q?: string;
  limit?: number;
  offset?: number;
}): Promise<{ documents: Document[]; total: number; limit: number; offset: number }> {
  const searchParams = new URLSearchParams();
  if (params) {
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        searchParams.set(key, String(value));
      }
    });
  }
  const query = searchParams.toString();
  return fetchAPI(`/documents${query ? `?${query}` : ''}`);
}

export async function getDocument(id: string): Promise<Document> {
  return fetchAPI(`/documents/${id}`);
}

export async function updateDocument(id: string, data: Partial<Document>): Promise<Document> {
  return fetchAPI(`/documents/${id}`, {
    method: 'PUT',
    body: JSON.stringify(data),
  });
}

export async function deleteDocument(id: string): Promise<void> {
  return fetchAPI(`/documents/${id}`, { method: 'DELETE' });
}

export async function reprocessDocument(id: string): Promise<void> {
  return fetchAPI(`/documents/${id}/reprocess`, { method: 'POST' });
}

// Search
export async function search(query: string): Promise<{ results: SearchResult[]; query: string }> {
  return fetchAPI('/search', {
    method: 'POST',
    body: JSON.stringify({ query }),
  });
}

// Chat sessions
export async function getChatSessions(limit?: number, offset?: number): Promise<{ sessions: ChatSession[]; total: number }> {
  const params = new URLSearchParams();
  if (limit !== undefined) params.set('limit', String(limit));
  if (offset !== undefined) params.set('offset', String(offset));
  const query = params.toString();
  return fetchAPI(`/chat/sessions${query ? `?${query}` : ''}`);
}

export async function createChatSession(title?: string): Promise<ChatSession> {
  return fetchAPI('/chat/sessions', {
    method: 'POST',
    body: JSON.stringify({ title: title || null }),
  });
}

export async function updateChatSession(id: string, title: string): Promise<ChatSession> {
  return fetchAPI(`/chat/sessions/${id}`, {
    method: 'PUT',
    body: JSON.stringify({ title }),
  });
}

export async function deleteChatSession(id: string): Promise<void> {
  return fetchAPI(`/chat/sessions/${id}`, { method: 'DELETE' });
}

// Chat messages
export async function sendChatMessage(
  message: string,
  sessionId?: string,
): Promise<{ reply: string; source_document_ids: string[]; session_id: string }> {
  return fetchAPI('/chat', {
    method: 'POST',
    body: JSON.stringify({ message, session_id: sessionId || null }),
  });
}

export async function sendAgentMessage(
  message: string,
  sessionId?: string,
  contextProcedure?: string,
): Promise<{ reply: string; session_id: string; tool_calls_log: ToolCallLog[] }> {
  return fetchAPI('/agent/chat', {
    method: 'POST',
    body: JSON.stringify({
      message,
      session_id: sessionId || null,
      context_procedure: contextProcedure || '',
    }),
  });
}

export type AgentStreamEvent =
  | { type: 'session'; session_id: string }
  | { type: 'tool_start'; tool: string; args: Record<string, unknown> }
  | { type: 'tool_done'; tool: string; args: Record<string, unknown>; result_preview: string }
  | { type: 'done'; reply: string; session_id: string; tool_calls_log: ToolCallLog[] }
  | { type: 'error'; message: string };

export function streamAgentMessage(
  message: string,
  sessionId: string | undefined,
  onEvent: (event: AgentStreamEvent) => void,
  contextProcedure?: string,
): () => void {
  const controller = new AbortController();

  (async () => {
    const res = await fetch(`${API_BASE}/agent/chat/stream`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        session_id: sessionId || null,
        context_procedure: contextProcedure || '',
      }),
      signal: controller.signal,
    });

    if (!res.ok || !res.body) {
      const text = await res.text().catch(() => '');
      onEvent({ type: 'error', message: `API Error ${res.status}: ${text}` });
      return;
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          try {
            onEvent(JSON.parse(line.slice(6)));
          } catch { /* ignore malformed */ }
        }
      }
    }
  })().catch((err) => {
    if (err?.name !== 'AbortError') {
      onEvent({ type: 'error', message: String(err) });
    }
  });

  return () => controller.abort();
}

export async function getChatHistory(
  sessionId: string,
  limit?: number,
  offset?: number,
): Promise<{ messages: ChatMessage[] }> {
  const params = new URLSearchParams();
  params.set('session_id', sessionId);
  if (limit !== undefined) params.set('limit', String(limit));
  if (offset !== undefined) params.set('offset', String(offset));
  return fetchAPI(`/chat/history?${params.toString()}`);
}

// Stats & Health
export async function getStats(): Promise<Stats> {
  return fetchAPI('/stats');
}

export async function getHealth(): Promise<Health> {
  return fetchAPI('/health');
}

// Procedures
export async function createProcedure(data: {
  name?: string;
  procedure_type: string;
  image_base64?: string;
  manual_documents?: string[];
  remarks?: string;
}): Promise<Procedure> {
  return fetchAPI('/procedures', {
    method: 'POST',
    body: JSON.stringify(data),
  });
}

export async function getProcedures(params?: {
  limit?: number;
  offset?: number;
}): Promise<{ procedures: Procedure[]; total: number; limit: number; offset: number }> {
  const searchParams = new URLSearchParams();
  if (params) {
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        searchParams.set(key, String(value));
      }
    });
  }
  const query = searchParams.toString();
  return fetchAPI(`/procedures${query ? `?${query}` : ''}`);
}

export async function getProcedure(id: string): Promise<Procedure> {
  return fetchAPI(`/procedures/${id}`);
}

export async function updateProcedure(
  id: string,
  data: {
    name?: string;
    procedure_type?: string;
    description?: string;
    required_documents?: ProcedureRequiredDocument[];
    remarks?: string;
  },
): Promise<Procedure> {
  return fetchAPI(`/procedures/${id}`, {
    method: 'PUT',
    body: JSON.stringify(data),
  });
}

export async function deleteProcedure(id: string): Promise<void> {
  return fetchAPI(`/procedures/${id}`, { method: 'DELETE' });
}

export async function executeProcedure(id: string, personName: string): Promise<ProcedureExecution> {
  return fetchAPI(`/procedures/${id}/execute`, {
    method: 'POST',
    body: JSON.stringify({ person_name: personName }),
  });
}

// Settings
export async function getSettings(): Promise<Settings> {
  return fetchAPI('/settings');
}

export async function updateSettings(data: SettingsUpdate): Promise<Settings> {
  return fetchAPI('/settings', {
    method: 'PUT',
    body: JSON.stringify(data),
  });
}

// Alert types
export interface AlertItem {
  document: Document;
  alert_type: 'expiration' | 'echeance';
  target_date: string;
  days_remaining: number;
  urgency: 'critical' | 'warning' | 'info';
}

export interface AlertsResponse {
  alerts: AlertItem[];
  total: number;
  expiring_count: number;
  overdue_count: number;
  upcoming_payments: number;
}

export interface RenewalSuggestion {
  document: Document;
  suggested_procedure?: Procedure;
  reason: string;
}

export interface GapAlert {
  doc_type: string;
  destinataire?: string;
  expected_date: string;
  last_seen_date?: string;
  message: string;
}

// Alerts API
export async function getAlerts(params?: {
  days_ahead?: number;
  urgency?: string;
  limit?: number;
}): Promise<AlertsResponse> {
  const searchParams = new URLSearchParams();
  if (params) {
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        searchParams.set(key, String(value));
      }
    });
  }
  const query = searchParams.toString();
  return fetchAPI(`/alerts${query ? `?${query}` : ''}`);
}

export async function getRenewalSuggestions(): Promise<{ suggestions: RenewalSuggestion[] }> {
  return fetchAPI('/alerts/suggestions');
}

export async function getGapAlerts(): Promise<{ gaps: GapAlert[]; total: number }> {
  return fetchAPI('/alerts/gaps');
}

export async function dismissAlert(docId: string, alertType: 'expiration' | 'echeance'): Promise<void> {
  return fetchAPI(`/alerts/${docId}/dismiss?alert_type=${alertType}`, { method: 'POST' });
}

export async function undismissAlert(docId: string, alertType: 'expiration' | 'echeance'): Promise<void> {
  return fetchAPI(`/alerts/${docId}/dismiss?alert_type=${alertType}`, { method: 'DELETE' });
}

// Update
export interface UpdateCheckResult {
  up_to_date: boolean;
  local_commit: string;
  remote_commit: string;
  behind_by: number;
  error: string | null;
}

export async function checkForUpdate(): Promise<UpdateCheckResult> {
  return fetchAPI('/update/check');
}

export async function applyUpdate(): Promise<{ status: string; message: string }> {
  return fetchAPI('/update/apply', { method: 'POST' });
}

// NAS Sync
export async function triggerNasSync(): Promise<NasSyncResult> {
  return fetchAPI('/sync/nas/blocking', { method: 'POST' });
}

export async function triggerNasSyncBackground(): Promise<{ status: string; message: string }> {
  return fetchAPI('/sync/nas', { method: 'POST' });
}

export async function testLlamaCppConnection(): Promise<{ status: string; detail?: unknown }> {
  return fetchAPI('/llamacpp/test', { method: 'POST' });
}

// ---------------------------------------------------------------------------
// Processing queue
// ---------------------------------------------------------------------------

export interface QueueJob {
  id: string;
  label: string;
  status: string;
  position: number;
  created_at: number;
  started_at?: number;
  finished_at?: number;
  error?: string;
}

export interface QueueStatus {
  active?: QueueJob;
  pending: QueueJob[];
  history: QueueJob[];
  total_pending: number;
  total_active: number;
}

export async function getQueue(): Promise<QueueStatus> {
  return fetchAPI('/queue');
}

// ---------------------------------------------------------------------------
// Live logs
// ---------------------------------------------------------------------------

export function createLogsEventSource(): EventSource {
  return new EventSource(`${API_BASE}/logs`);
}
