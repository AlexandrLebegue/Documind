# DocuMind — Website Icon & Settings Menu Plan

## Overview

Three changes requested:
1. **Add a favicon/icon** for the website (browser tab, bookmarks, PWA)
2. **Add a Settings page** to configure API key, data folder, and AI model
3. **Ensure mobile responsiveness** for all new UI

---

## 1. Website Favicon / Icon

### Current State
- No `public/` directory exists in `frontend/`
- No favicon configured in `layout.tsx` metadata
- The app logo is an inline SVG document icon (blue rounded square with a document shape)

### Approach
- **Create `frontend/src/app/icon.svg`** — Next.js 14 App Router auto-detects `icon.svg` in the `app/` directory and serves it as the favicon
- The SVG will match the existing sidebar logo: a blue rounded square (`#2E75B6`) with a white document outline
- **Update `layout.tsx`** to add `icons` metadata for broader browser support
- **Create `frontend/src/app/apple-icon.png`** is optional but recommended for iOS bookmarks — can be deferred

### Files Modified
| File | Action |
|------|--------|
| `frontend/src/app/icon.svg` | **Create** — SVG favicon matching the DocuMind brand |
| `frontend/src/app/layout.tsx` | **Modify** — Add `icons` to metadata export |

---

## 2. Backend — Settings API

### Current State
- Configuration lives in `config.py`, reading from environment variables
- No runtime settings storage or API endpoints exist
- The LLM client is created once at startup in `lifespan()`

### Approach — Settings Persistence
- **Create a `settings.json` file** stored in `DATA_DIR` (the persistent volume)
- On startup, load settings from this file and overlay them on top of env-var defaults
- Settings file schema:

```json
{
  "openrouter_api_key": "sk-or-...",
  "openrouter_model": "google/gemini-3.1-pro-preview",
  "data_dir": "/data"
}
```

### Approach — API Endpoints

**`GET /api/settings`** — Returns current settings (API key masked)
```json
{
  "openrouter_api_key": "sk-or-...****1234",
  "openrouter_model": "google/gemini-3.1-pro-preview",
  "data_dir": "/data",
  "openrouter_base_url": "https://openrouter.ai/api/v1"
}
```

**`PUT /api/settings`** — Update settings, persists to `settings.json`, hot-reloads LLM client
```json
{
  "openrouter_api_key": "sk-or-new-key",
  "openrouter_model": "anthropic/claude-sonnet-4"
}
```

### Hot-Reload Strategy
When settings are updated via PUT:
1. Write new values to `settings.json`
2. Update `config.py` module-level variables in-memory
3. Close existing `app.state.llm` client
4. Re-create `app.state.llm` with new credentials/model
5. Return success with the new masked settings

### Files Modified
| File | Action |
|------|--------|
| `config.py` | **Modify** — Add `load_settings()` / `save_settings()` functions, load from JSON on import |
| `main.py` | **Modify** — Add `GET /api/settings` and `PUT /api/settings` endpoints |
| `models.py` | **Modify** — Add `SettingsResponse` and `SettingsUpdateRequest` Pydantic models |

---

## 3. Frontend — Settings Page

### Architecture

```mermaid
graph TD
    A[Sidebar] -->|gear icon at bottom| B[/settings route]
    B --> C[SettingsPage component]
    C --> D[API Key Field - password input with reveal toggle]
    C --> E[AI Model Field - text input]
    C --> F[Data Folder Field - read-only display]
    C --> G[Save Button]
    G -->|PUT /api/settings| H[Backend]
    H -->|Hot-reload LLM| I[Updated config]
```

### Settings Page Layout
- Full-width card layout, single column
- Responsive: works on mobile with stacked fields
- Sections:
  1. **API Configuration** — API key input (masked, with show/hide toggle), Base URL (read-only)
  2. **AI Model** — Text input for model name, with hint text showing current model
  3. **Storage** — Data folder path (read-only, informational)
  4. **Save** — Full-width save button at bottom, with success/error toast

### Mobile Considerations
- All form fields are full-width on mobile (`w-full`)
- Padding adjusts: `p-4 sm:p-6`
- No side-by-side layouts that would break on narrow screens
- Save button is sticky at bottom on mobile for easy thumb access
- Settings gear icon visible in mobile sidebar navigation
- The page uses the same `LayoutShell` wrapper, so sidebar/header behavior is inherited

### Sidebar Integration
- Add a **Settings** nav item at the **bottom** of the sidebar, separated from main nav
- Use a gear/cog SVG icon
- On mobile, the settings link appears in the slide-out sidebar menu

### Files Modified/Created
| File | Action |
|------|--------|
| `frontend/src/app/settings/page.tsx` | **Create** — Settings page component |
| `frontend/src/components/Sidebar.tsx` | **Modify** — Add Settings nav item at bottom |
| `frontend/src/lib/api.ts` | **Modify** — Add `getSettings()` and `updateSettings()` functions + types |

---

## 4. Implementation Order

1. **Icon** — `icon.svg` + `layout.tsx` metadata (standalone, no dependencies)
2. **Backend settings persistence** — `config.py` changes + `settings.json` load/save
3. **Backend settings API** — `models.py` + `main.py` endpoints
4. **Frontend API layer** — `api.ts` settings functions
5. **Frontend settings page** — `settings/page.tsx`
6. **Sidebar update** — Add gear icon link to settings
7. **Mobile testing** — Verify all new UI on narrow viewports

---

## 5. File Change Summary

| File | Change Type |
|------|------------|
| `frontend/src/app/icon.svg` | New |
| `frontend/src/app/layout.tsx` | Modified |
| `frontend/src/app/settings/page.tsx` | New |
| `frontend/src/components/Sidebar.tsx` | Modified |
| `frontend/src/lib/api.ts` | Modified |
| `config.py` | Modified |
| `main.py` | Modified |
| `models.py` | Modified |
