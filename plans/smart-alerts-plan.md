# Smart Document Alerts & Expiry Tracking

> **Feature:** AI-powered expiration date extraction + proactive alerts dashboard  
> **Goal:** Transform DocuMind from a passive archive into a proactive document assistant

---

## Overview

During the existing AI metadata extraction pipeline, the LLM will additionally extract time-sensitive fields (`date_expiration`, `date_echeance`). The system will then provide:

1. A dashboard **"Expiring Soon"** widget with color-coded urgency
2. **Expiry/overdue badges** on document cards
3. A dedicated **`/alerts`** page with filterable alert timeline
4. **AI-powered renewal suggestions** linking to existing Procedures
5. **Missing document gap detection** (e.g. "payslips Jan-Apr present, May missing")

---

## Architecture

```mermaid
flowchart TD
    A[Document Upload] --> B[OCR + Text Extraction]
    B --> C[LLM Metadata Extraction]
    C --> |NEW: extract date_expiration + date_echeance| D[Save to DB]
    D --> E[Embedding Generation]
    E --> F[Document Ready]

    G[GET /api/alerts] --> H[Query DB for expiring docs]
    H --> I[Compute urgency levels]
    I --> J[Return AlertsResponse]

    K[GET /api/alerts/suggestions] --> L[Find expired docs]
    L --> M[Match to existing Procedures]
    M --> N[Return renewal suggestions]

    O[GET /api/stats] --> |ENHANCED| P[Include expiring_soon count]

    Q[Dashboard Page] --> R[Expiring Soon Widget]
    Q --> S[StatsCards with alert count]

    T[/alerts Page] --> U[Alert Timeline]
    T --> V[Filter by urgency]
    T --> W[Renewal Suggestions]
```

---

## Implementation Plan

### Phase 1 — Backend: Database Schema + Migration

**File:** `database.py`

Add two new columns to the `documents` table:

```sql
ALTER TABLE documents ADD COLUMN date_expiration TEXT;  -- YYYY-MM-DD
ALTER TABLE documents ADD COLUMN date_echeance TEXT;    -- YYYY-MM-DD
```

**Changes:**
- In `init_db()`: add migration `ALTER TABLE` blocks (same pattern as existing `title` migration at line 67)
- In `update_document_metadata()`: add `date_expiration` and `date_echeance` parameters to the UPDATE statement
- In `update_document_fields()`: add `"date_expiration"` and `"date_echeance"` to the `allowed` set (line 476)
- Add new query function `get_expiring_documents(days_ahead, limit)` that returns documents where `date_expiration` is between today and today + N days
- Add new query function `get_overdue_documents(limit)` for expired documents
- Add new query function `get_upcoming_echeances(days_ahead, limit)` for payment deadlines
- Enhance `get_stats()` to include `expiring_soon_count` (documents expiring within 30 days)

### Phase 2 — Backend: LLM Prompt Enhancement

**File:** `prompts.py`

Update `METADATA_EXTRACTION_PROMPT` to add two new fields to the extraction instructions:

```
- "date_expiration": date de fin de validité du document au format YYYY-MM-DD (null si pas applicable). 
  Exemples: date d'expiration d'une carte d'identité, fin de validité d'une attestation, 
  date de fin d'un contrat, date limite d'un certificat.
- "date_echeance": date d'échéance de paiement au format YYYY-MM-DD (null si pas de paiement). 
  Exemples: date limite de paiement d'une facture, échéance d'un prêt.
```

Also update `METADATA_CORRECTION_PROMPT` to include these two fields.

**File:** `llm.py`

- In `_parse_and_validate_metadata()`: 
  - Do NOT add these to `required_fields` (they are optional)
  - Add date format validation for both fields (YYYY-MM-DD or null)
  - Default to `None` if missing
- In `extract_metadata()`: the fallback dict should include both fields as `None`

**File:** `pipeline.py`

- In `_save_metadata()`: pass the two new fields to `update_document_metadata()`

### Phase 3 — Backend: API Endpoints

**File:** `models.py`

Add new fields to existing models:
```python
# In DocumentResponse — add:
date_expiration: Optional[str] = None
date_echeance: Optional[str] = None

# In DocumentUpdateRequest — add:
date_expiration: Optional[str] = None
date_echeance: Optional[str] = None
```

Add new response models:
```python
class AlertItem(BaseModel):
    document: DocumentResponse
    alert_type: str          # "expiration" or "echeance"
    target_date: str         # The relevant date
    days_remaining: int      # Negative = overdue
    urgency: str             # "critical", "warning", "info"

class AlertsResponse(BaseModel):
    alerts: list[AlertItem]
    total: int
    expiring_count: int      # Within 30 days
    overdue_count: int       # Past expiration
    upcoming_payments: int   # Echeances within 30 days

class RenewalSuggestion(BaseModel):
    document: DocumentResponse
    suggested_procedure: Optional[ProcedureResponse] = None
    reason: str

class RenewalSuggestionsResponse(BaseModel):
    suggestions: list[RenewalSuggestion]
```

Add to `StatsResponse`:
```python
expiring_soon_count: int = 0
overdue_count: int = 0
```

**File:** `main.py`

Add new endpoints:

#### `GET /api/alerts`
- Query params: `days_ahead` (default 90), `urgency` filter, `limit`, `offset`
- Combines expiring documents + upcoming echeances
- Computes `days_remaining` and `urgency` for each
- Urgency rules:
  - `critical`: <= 7 days or overdue
  - `warning`: 8-30 days
  - `info`: 31-90 days

#### `GET /api/alerts/suggestions`  
- For each expired/expiring document, search existing Procedures for a matching renewal
- Uses the document's `doc_type` to find relevant procedures
- Returns `RenewalSuggestion` objects

#### Enhanced `GET /api/stats`
- Add `expiring_soon_count` and `overdue_count` to the response

### Phase 4 — Frontend: Types & API Client

**File:** `frontend/src/lib/api.ts`

Add to `Document` interface:
```typescript
date_expiration?: string;
date_echeance?: string;
```

Add new types:
```typescript
interface AlertItem {
  document: Document;
  alert_type: 'expiration' | 'echeance';
  target_date: string;
  days_remaining: number;
  urgency: 'critical' | 'warning' | 'info';
}

interface AlertsResponse {
  alerts: AlertItem[];
  total: number;
  expiring_count: number;
  overdue_count: number;
  upcoming_payments: number;
}

interface RenewalSuggestion {
  document: Document;
  suggested_procedure?: Procedure;
  reason: string;
}
```

Add to `Stats` interface:
```typescript
expiring_soon_count: number;
overdue_count: number;
```

Add API functions:
```typescript
getAlerts(params?: { days_ahead?: number; urgency?: string; limit?: number; offset?: number })
getRenewalSuggestions()
```

### Phase 5 — Frontend: Dashboard Enhancement

**File:** `frontend/src/components/StatsCards.tsx`

- Replace one of the 4 stat cards (the less useful "Type principal" card) with an **"Alertes"** card showing `expiring_soon_count` with a warning icon
- If `expiring_soon_count > 0`, use amber/red background; otherwise green

**File:** `frontend/src/app/page.tsx` (Dashboard)

- Add an **"Expiring Soon" widget** below the stats cards (above recent documents)
- Shows the top 5 alerts with color-coded urgency badges
- Each item links to the document view
- "Voir toutes les alertes →" link to `/alerts`

### Phase 6 — Frontend: Document Cards & View Enhancements

**File:** `frontend/src/components/DocumentCard.tsx`

- Add an **expiry badge** next to the existing `TypeBadge`:
  - Red "Expiré" badge if `date_expiration` < today
  - Amber "Expire bientôt" badge if within 30 days
  - Similarly for `date_echeance`

**File:** `frontend/src/app/documents/view/page.tsx`

- Display `date_expiration` and `date_echeance` in the metadata section
- Add a visual alert banner at the top if the document is expired or expiring soon
- Add a "Renouveler" button that links to the suggested procedure

**File:** `frontend/src/components/MetadataEditor.tsx`

- Add date inputs for `date_expiration` and `date_echeance` so users can manually set/correct these dates

### Phase 7 — Frontend: Dedicated Alerts Page

**File:** `frontend/src/app/alerts/page.tsx` (NEW)

Full-page alerts view with:
- **Summary header**: 3 mini-cards showing overdue count, expiring this month, upcoming payments
- **Filter bar**: by urgency level (critical/warning/info), by alert type (expiration/echeance)
- **Alert timeline**: grouped by urgency, each item showing:
  - Document title + type badge
  - Target date + days remaining
  - Urgency badge (color-coded)
  - "View document" link
  - "Renew" button (if a matching procedure exists)
- **Renewal suggestions section**: AI-powered recommendations at the bottom

**File:** `frontend/src/components/Sidebar.tsx`

- Add "Alertes" nav item between "Procédures" and "Chat"
- Show a notification dot/badge on the nav item when there are critical alerts

**File:** `frontend/src/components/AlertBadge.tsx` (NEW)

Reusable urgency badge component:
- `critical` → red background, "Urgent" or "Expiré"
- `warning` → amber background, "Bientôt"  
- `info` → blue background, "À venir"

### Phase 8 — AI Gap Detection (Bonus)

**File:** `main.py` — new endpoint `GET /api/alerts/gaps`

- Queries documents grouped by `doc_type` and `destinataire`
- For recurring document types (fiche_de_paie, facture, quittance), analyzes the date pattern
- Uses simple date arithmetic (not LLM) to detect:
  - Missing monthly documents (e.g., payslip gap)
  - Missing yearly renewals (e.g., no 2024 insurance attestation)
- Returns a list of `GapAlert` objects

---

## File Change Summary

| File | Action | Changes |
|------|--------|---------|
| `database.py` | MODIFY | Add columns migration, update metadata fn, add alert queries, enhance stats |
| `prompts.py` | MODIFY | Add date_expiration + date_echeance to extraction prompts |
| `llm.py` | MODIFY | Validate new date fields in metadata parser, update fallback dict |
| `pipeline.py` | MODIFY | Pass new fields through _save_metadata |
| `models.py` | MODIFY | Add fields to DocumentResponse/UpdateRequest, add AlertItem + AlertsResponse models |
| `main.py` | MODIFY | Add /api/alerts, /api/alerts/suggestions, /api/alerts/gaps endpoints, enhance /api/stats |
| `frontend/src/lib/api.ts` | MODIFY | Add types + API functions for alerts |
| `frontend/src/components/StatsCards.tsx` | MODIFY | Replace "Type principal" card with alerts card |
| `frontend/src/app/page.tsx` | MODIFY | Add "Expiring Soon" widget section |
| `frontend/src/components/DocumentCard.tsx` | MODIFY | Add expiry/echeance badges |
| `frontend/src/app/documents/view/page.tsx` | MODIFY | Show expiry dates + alert banner + renew button |
| `frontend/src/components/MetadataEditor.tsx` | MODIFY | Add date_expiration + date_echeance inputs |
| `frontend/src/components/Sidebar.tsx` | MODIFY | Add "Alertes" nav item with notification dot |
| `frontend/src/app/alerts/page.tsx` | NEW | Full alerts page with timeline + filters + suggestions |
| `frontend/src/components/AlertBadge.tsx` | NEW | Reusable urgency badge component |

---

## Urgency Classification Rules

| Days Remaining | Level | Color | Label |
|----------------|-------|-------|-------|
| < 0 (overdue) | critical | Red #dc2626 | Expiré / En retard |
| 0-7 | critical | Red #dc2626 | Urgent |
| 8-30 | warning | Amber #d97706 | Expire bientôt |
| 31-90 | info | Blue #2563eb | À surveiller |

---

## Implementation Order

The phases should be implemented strictly in order because each depends on the previous:

1. **Phase 1** (DB) → schema must exist before anything else
2. **Phase 2** (LLM) → prompts must extract dates before they can be stored
3. **Phase 3** (API) → endpoints must exist before frontend can call them
4. **Phase 4** (Frontend types) → types must exist before UI components
5. **Phase 5** (Dashboard) → most visible impact, should come next
6. **Phase 6** (Document enhancements) → per-document badges and view
7. **Phase 7** (Alerts page) → dedicated page, most complex frontend piece
8. **Phase 8** (Gap detection) → bonus feature, can be deferred

Existing documents can be re-analyzed by using the existing `/api/documents/{id}/reprocess` endpoint, which re-runs the LLM metadata extraction and will pick up the new fields.
