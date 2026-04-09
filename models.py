"""DocuMind Pydantic v2 request/response schemas."""

from pydantic import BaseModel, Field
from typing import Optional


class DocumentResponse(BaseModel):
    """Full document representation returned by the API."""

    id: str
    filename: str
    filepath: str
    title: Optional[str] = None
    text_content: Optional[str] = None
    doc_type: Optional[str] = None
    emetteur: Optional[str] = None
    doc_date: Optional[str] = None
    montant: Optional[float] = None
    reference: Optional[str] = None
    destinataire: Optional[str] = None
    resume: Optional[str] = None
    tags: Optional[list[str]] = None
    date_expiration: Optional[str] = None
    date_echeance: Optional[str] = None
    status: str
    created_at: str
    updated_at: str


class DocumentListResponse(BaseModel):
    """Paginated list of documents."""

    documents: list[DocumentResponse]
    total: int
    limit: int
    offset: int


class DocumentUpdateRequest(BaseModel):
    """Partial update payload for manual metadata editing."""

    title: Optional[str] = None
    doc_type: Optional[str] = None
    emetteur: Optional[str] = None
    doc_date: Optional[str] = None
    montant: Optional[float] = None
    reference: Optional[str] = None
    destinataire: Optional[str] = None
    resume: Optional[str] = None
    tags: Optional[list[str]] = None
    date_expiration: Optional[str] = None
    date_echeance: Optional[str] = None


class SearchRequest(BaseModel):
    """Incoming search query."""

    query: str


class SearchResultItem(BaseModel):
    """A single search hit with score and match origin."""

    document: DocumentResponse
    score: float
    match_type: str  # "fts", "semantic", or "hybrid"


class SearchResponse(BaseModel):
    """Collection of search results for a query."""

    results: list[SearchResultItem]
    query: str


class ChatRequest(BaseModel):
    """Incoming chat message from the user."""

    message: str
    session_id: Optional[str] = Field(
        None,
        description="Chat session UUID. If absent a new session is created automatically.",
    )


class ChatMessage(BaseModel):
    """A single chat history entry."""

    id: str
    session_id: Optional[str] = None
    message: str
    role: str
    context_doc_ids: Optional[list[str]] = None
    created_at: str


class ChatResponse(BaseModel):
    """LLM reply with source document references."""

    reply: str
    source_document_ids: list[str]
    session_id: str


class ChatHistoryResponse(BaseModel):
    """List of past chat messages."""

    messages: list[ChatMessage]


# ---------------------------------------------------------------------------
# Chat sessions
# ---------------------------------------------------------------------------


class ChatSessionResponse(BaseModel):
    """Full chat session representation."""

    id: str
    title: str
    created_at: str
    updated_at: str


class ChatSessionListResponse(BaseModel):
    """Paginated list of chat sessions."""

    sessions: list[ChatSessionResponse]
    total: int


class ChatSessionCreateRequest(BaseModel):
    """Request to create a new chat session."""

    title: Optional[str] = Field(None, description="Session title (auto-generated if absent)")


class ChatSessionUpdateRequest(BaseModel):
    """Request to rename a chat session."""

    title: str


class StatsResponse(BaseModel):
    """Aggregate statistics about the document collection."""

    total_documents: int
    count_by_type: dict[str, int]
    count_by_month: dict[str, int]
    recent_documents: list[DocumentResponse]
    expiring_soon_count: int = 0
    overdue_count: int = 0


class UploadResponse(BaseModel):
    """Response returned after a document upload."""

    id: str
    filename: str
    status: str
    message: str


class HealthResponse(BaseModel):
    """Health-check / readiness response."""

    status: str
    llm_loaded: bool
    embedding_model_loaded: bool
    total_documents: int
    version: str = "unknown"


# ---------------------------------------------------------------------------
# Procedures
# ---------------------------------------------------------------------------


class ProcedureRequiredDocument(BaseModel):
    """A single document required by a procedure."""

    doc_type: str
    label: str
    description: Optional[str] = None


class ProcedureCreateRequest(BaseModel):
    """Incoming request to create a procedure via AI analysis."""

    name: Optional[str] = Field(None, description="Custom name for the procedure (overrides AI-generated name)")
    procedure_type: str = Field(..., description="Type of procedure (administrative, contrat, bancaire, sante, emploi, immobilier)")
    image_base64: Optional[str] = Field(None, description="Base64-encoded image of the required documents list")
    manual_documents: Optional[list[str]] = Field(None, description="Manually entered list of required document descriptions")
    remarks: Optional[str] = Field(None, description="Additional remarks or context")


class ProcedureUpdateRequest(BaseModel):
    """Partial update payload for editing an existing procedure."""

    name: Optional[str] = None
    procedure_type: Optional[str] = None
    description: Optional[str] = None
    required_documents: Optional[list[ProcedureRequiredDocument]] = None
    remarks: Optional[str] = None


class ProcedureResponse(BaseModel):
    """Full procedure representation returned by the API."""

    id: str
    name: str
    procedure_type: str
    description: Optional[str] = None
    required_documents: list[ProcedureRequiredDocument]
    remarks: Optional[str] = None
    status: str
    created_at: str
    updated_at: str


class ProcedureListResponse(BaseModel):
    """Paginated list of procedures."""

    procedures: list[ProcedureResponse]
    total: int
    limit: int
    offset: int


class ProcedureExecuteRequest(BaseModel):
    """Request to execute a procedure by searching for matching documents."""

    person_name: str = Field(..., description="Full name of the person whose documents to search for")


class MatchedDocument(BaseModel):
    """A single document match result during procedure execution."""

    required_doc_type: str
    required_label: str
    found: bool
    document: Optional[DocumentResponse] = None


class ProcedureExecutionResponse(BaseModel):
    """Result of executing a procedure — matched documents for each requirement."""

    id: str
    procedure_id: str
    person_name: str
    matched_documents: list[MatchedDocument]
    status: str
    created_at: str


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------


class SettingsResponse(BaseModel):
    """Current application settings (API key is masked)."""

    version: str = "unknown"
    ai_provider: str = Field(..., description="Active AI provider: openrouter | ollama | custom")
    openrouter_api_key: str = Field(
        ..., description="Masked API key (only last 4 characters visible)"
    )
    openrouter_model: str
    openrouter_base_url: str
    ollama_base_url: str
    ollama_model: str
    data_dir: str
    # NAS sync settings
    nas_sync_enabled: bool = False
    nas_host: str = "192.168.1.100"
    nas_share: str = "NAS_Commun_Vol2"
    nas_path: str = "DOCUMIND/originals"
    nas_username: str = ""
    nas_sync_hour: int = Field(7, ge=0, le=23, description="Hour (0-23) at which the daily sync runs")
    nas_sync_minute: int = Field(0, ge=0, le=59, description="Minute (0-59) at which the daily sync runs")


class SettingsUpdateRequest(BaseModel):
    """Partial update payload for application settings."""

    ai_provider: Optional[str] = Field(
        None, description="AI provider: openrouter | ollama | custom"
    )
    openrouter_api_key: Optional[str] = Field(
        None, description="OpenRouter API key (full key)"
    )
    openrouter_model: Optional[str] = Field(
        None, description="OpenRouter model identifier"
    )
    openrouter_base_url: Optional[str] = Field(
        None, description="OpenRouter base URL"
    )
    ollama_base_url: Optional[str] = Field(
        None, description="Ollama base URL (e.g. http://192.168.1.50:11434)"
    )
    ollama_model: Optional[str] = Field(
        None, description="Ollama model name (e.g. llama3.2, mistral)"
    )
    # NAS sync settings
    nas_sync_enabled: Optional[bool] = None
    nas_host: Optional[str] = None
    nas_share: Optional[str] = None
    nas_path: Optional[str] = None
    nas_username: Optional[str] = None
    nas_password: Optional[str] = Field(None, description="NAS password (write-only, never returned)")
    nas_sync_hour: Optional[int] = Field(None, ge=0, le=23)
    nas_sync_minute: Optional[int] = Field(None, ge=0, le=59)


# ---------------------------------------------------------------------------
# Processing Queue
# ---------------------------------------------------------------------------


class QueueJobResponse(BaseModel):
    """A single job in the processing queue."""
    id: str
    label: str
    status: str
    position: int
    created_at: float
    started_at: Optional[float] = None
    finished_at: Optional[float] = None
    error: Optional[str] = None


class QueueStatusResponse(BaseModel):
    """Full snapshot of the processing queue."""
    active: Optional[QueueJobResponse] = None
    pending: list[QueueJobResponse] = []
    history: list[QueueJobResponse] = []
    total_pending: int = 0
    total_active: int = 0


# ---------------------------------------------------------------------------
# Alerts & Expiry Tracking
# ---------------------------------------------------------------------------


class AlertItem(BaseModel):
    """A single alert for an expiring or overdue document."""

    document: DocumentResponse
    alert_type: str = Field(..., description="'expiration' or 'echeance'")
    target_date: str = Field(..., description="The relevant date (YYYY-MM-DD)")
    days_remaining: int = Field(..., description="Days until target date (negative = overdue)")
    urgency: str = Field(..., description="'critical', 'warning', or 'info'")


class AlertsResponse(BaseModel):
    """Collection of document alerts."""

    alerts: list[AlertItem]
    total: int
    expiring_count: int = Field(0, description="Documents expiring within 30 days")
    overdue_count: int = Field(0, description="Documents past expiration")
    upcoming_payments: int = Field(0, description="Payment deadlines within 30 days")


class RenewalSuggestion(BaseModel):
    """A suggestion to renew an expired/expiring document via a procedure."""

    document: DocumentResponse
    suggested_procedure: Optional[ProcedureResponse] = None
    reason: str


class RenewalSuggestionsResponse(BaseModel):
    """List of renewal suggestions."""

    suggestions: list[RenewalSuggestion]


class GapAlert(BaseModel):
    """A detected gap in recurring documents."""

    doc_type: str
    destinataire: Optional[str] = None
    expected_date: str = Field(..., description="Approximate date of the missing document (YYYY-MM)")
    last_seen_date: Optional[str] = None
    message: str


class GapAlertsResponse(BaseModel):
    """List of detected document gaps."""

    gaps: list[GapAlert]
    total: int


# ---------------------------------------------------------------------------
# Agent chat
# ---------------------------------------------------------------------------


class AgentChatRequest(BaseModel):
    """Incoming message for the agentic chat endpoint."""

    message: str
    session_id: Optional[str] = Field(
        None,
        description="Chat session UUID. A new session is created if absent.",
    )
    context_procedure: str = Field(
        "",
        description="Optional procedure text to inject into the agent's system prompt.",
    )


class ToolCallLog(BaseModel):
    """A single tool invocation recorded during an agentic turn."""

    tool: str = Field(..., description="Tool name (e.g. 'recherche_web')")
    args: dict = Field(..., description="Arguments passed to the tool")
    result_preview: str = Field(..., description="First 300 chars of the tool result")


class AgentChatResponse(BaseModel):
    """Agent reply with tool usage log and session info."""

    reply: str
    session_id: str
    tool_calls_log: list[ToolCallLog] = Field(
        default_factory=list,
        description="Ordered list of tools the agent called before answering",
    )
