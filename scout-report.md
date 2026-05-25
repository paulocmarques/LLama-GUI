# Scout Report: Llama GUI

**Date:** 2026-05-24
**Repo:** `LLama-GUI` — browser-based launcher/control panel for `llama.cpp`

---

## 1. Overall Structure & Purpose

Llama GUI is a **single-repo web application** that provides a dark-themed, tabbed browser UI for installing, configuring, launching, and chatting with `llama.cpp` models. It targets Windows, macOS, and Linux.

- **Backend:** Python stdlib `http.server` (no framework). Serves static UI and provides JSON/SSE API endpoints.
- **Frontend:** Vanilla HTML/CSS/JS loaded as ordered global `<script>` tags (no bundler, no ES modules). Each module attaches to `window.LlamaGui`.
- **Entry point:** `python server.py` → thin wrapper → delegates to `backend/app.py`.

### Top-Level Directory Map

| Dir / File | Role |
|---|---|
| `server.py` | 26-line compat entrypoint, re-exports `backend.app` |
| `backend/` | Python package: HTTP server, routes, services, state |
| `ui/` | Static frontend: `index.html`, `js/`, `css/`, `templates/` |
| `ui/js/flags/` | Ordered pure-data modules for flag definitions |
| `ui/templates/` | 14 bundled Jinja chat template files |
| `tests/` | Frontend (Node/Playwright) + backend (unittest) tests |
| `docs/` | Documentation: todo, flag audit, architecture, bugtracker |
| `llama/` | Downloaded `llama.cpp` binaries at runtime |
| `models/` | User model files (.gguf) |
| `presets/` | Saved launcher preset JSON files |
| `tools/` | Auto-downloaded `cloudflared` binary |
| `scripts/` | `create_windows_shortcuts.ps1` |
| `.launcher/` | Pinokio launcher integration (`launch-llama-gui.ps1`) |
| `assets/` | App icon (`Llama-GUI.ico`) |
| `AGENTS.md` | Agent workflow rules, anti-patterns, file ownership, pitfalls |
| `requirements.txt` | `certifi`, `ddgs`, `huggingface_hub` |
| `package.json` | Playwright devDependency + test scripts |

---

## 2. Main Entry Points

### `server.py` (line 1-26)
Compatibility shim. Uses `_ServerModule` trick to proxy `setattr` to `backend.app`. Calls `main()` on `__main__`.

### `backend/app.py` (889 lines)
Real server. Key sections:
- `create_ssl_context()` — certifi-based SSL
- `Handler` class — extends `SimpleHTTPRequestHandler`, serves `ui/` dir
- `do_GET/do_POST/do_DELETE` — dispatch to `API_ROUTER` or proxy to `llama-server`
- `API_ROUTER` — declarative route table (34 routes)
- `main()` — creates `ThreadingHTTPServer`, serves forever
- `configure_services()` — wires `AppContext` services
- Cache-busting via mtime-based versioning in `version_ui_asset_urls()`

### `ui/index.html` (862 lines)
6-tab layout: Install, Quick Launch, Configure, Chat, API, Presets. Loads 19 `<script>` tags in strict order.

---

## 3. Backend Architecture

### Module Map (7 core + 14 routes + 10 services)

**Core:**
| Module | Lines | Role |
|---|---|---|
| `backend/app.py` | 889 | HTTP handler, CORS, proxy, route registry, main() |
| `backend/config.py` | 87 | Path constants, env var parsing, web search limits |
| `backend/context.py` | 82 | `AppContext`, `AppPaths`, `ServerConfig`, `BackendServices` dataclasses |
| `backend/state.py` | 98 | `ServerState` dataclass, `AtomicDict` (lock-protected dict) |
| `backend/http.py` | 243 | `Request`/`Response`/`SseWriter`, CORS validation, `sanitize_error()` |
| `backend/routing.py` | 75 | `Router` class: exact + prefix route matching |

**Routes** (`backend/routes/`):
| Route | Role |
|---|---|
| `chat.py` | `/api/chat/completions` — SSE proxy with web search |
| `process.py` | `/api/launch`, `/api/stop`, `/api/output`, `/api/send-input`, `/api/cleanup-llama` |
| `install.py` | `/api/releases`, `/api/install`, `/api/update`, `/api/download-progress` |
| `metrics.py` | `/api/llama/metrics`, `/api/llama/slots` — Prometheus proxy |
| `models.py` | `/api/models` — list GGUF files |
| `presets.py` | `/api/presets` CRUD + shortcut export |
| `hf_download.py` | `/api/hf/repo-files`, `/api/hf/download`, `/api/hf/download-status`, `/api/hf/download-cancel` |
| `tunnel.py` | `/api/remote-tunnel/start`, `/api/remote-tunnel/stop`, `/api/remote-tunnel/status` |
| `git_update.py` | `/api/app-update-status`, `/api/app-update` |
| `search.py` | `/api/web-search` |
| `status.py` | `/api/status` |
| `lifecycle.py` | `/api/shutdown`, `/api/restart`, `/api/open-folder` |
| `file_picker.py` | `/api/select-file` — native tkinter dialog |
| `lifecycle.py` | Server lifecycle |

**Services** (`backend/services/`):
| Service | Lines | Role |
|---|---|---|
| `llama_manager.py` | 461 | GitHub release fetch, install, SHA256 verify, binary extraction |
| `process_manager.py` | 196 | Process launch/stop, output streaming, arg flattening, API target parsing |
| `hf_download.py` | 311 | HF repo listing, file download with cancel, path validation |
| `web_search.py` | 216 | DuckDuckGo search, HTML-to-text, page fetching |
| `tunnel.py` | 241 | Cloudflare tunnel lifecycle, binary download, status polling |
| `git_update.py` | 369 | Git fetch/pull/status, safe dirty path classification |
| `lifecycle.py` | 112 | Server shutdown, restart, cleanup |
| `chat.py` | 99 | Chat proxy helpers (search queries, context building, local addresses) |
| `file_picker.py` | 120 | Native tkinter file dialog |

### State Pattern
- `ServerState` dataclass in `backend/state.py` — all mutable server state
- `AtomicDict` — lock-protected dict with `update()`, `replace()`, `snapshot()`
- `AppContext` in `backend/context.py` — frozen `AppPaths`, `ServerConfig`, mutable `ServerState`, `BackendServices`
- `DEFAULT_CONTEXT` singleton used by all routes via `ctx` parameter
- Services are injected into `ctx.services` by `configure_services()`

### API Router
```python
API_ROUTER = Router()
    .add("GET",  "/api/status", ...)
    .add("POST", "/api/launch", ...)
    .add_prefix("DELETE", "/api/presets/", ..., "name")
```
Routes receive `(request, response, ctx)` — `Request`/`Response` wrappers from `http.py`.

---

## 4. Frontend Architecture

### Script Loading Order (strict, 19 scripts)

```
1.  flags/categories.js      — FLAG_CATEGORIES array
2.  flags/options.js          — shared enum option lists (CACHE_TYPE_OPTIONS, etc.)
3.  flags/chat-templates.js   — BUILTIN_CHAT_TEMPLATES, CHAT_TEMPLATE_PRESETS, preset helpers
4.  flags/definitions.js      — FLAGS array (134 flags, single source of truth)
5.  flags/helpers.js          — getFlagsForTool(), getFlagsByCategory(), speculative helpers
6.  flag-validation.js        — startup validation (duplicate ids, bad types, etc.)
7.  flag-core.js              — window.LlamaGui.flagCore (shared state singleton)
8.  config-flags-ui.js        — window.LlamaGui.configFlagsUi (Configure tab rendering)
9.  manager.js                — window.LlamaGui.manager (install/update/fetchJson)
10. presets.js                — window.LlamaGui.presets (preset CRUD)
11. app-data.js               — QUICK_PROFILES, BUILTIN_SAMPLER_PRESETS, CHAT_SAMPLER_SLIDER_MAP
12. sampler-presets.js        — window.LlamaGui.samplerPresets
13. chat-rendering.js         — window.LlamaGui.chatRendering
14. api-tab.js                — window.LlamaGui.apiTab
15. hf-download-ui.js         — window.LlamaGui.hfDownloadUi
16. remote-tunnel-ui.js       — window.LlamaGui.remoteTunnelUi
17. quick-launch-ui.js        — window.LlamaGui.quickLaunchUi
18. chat-ui.js                — window.LlamaGui.chatUi
19. app.js                    — main orchestration, wires everything together
```

### Key Module Sizes (lines)

| Module | Lines | Namespace |
|---|---|---|
| `app.js` | 932 | `window.LlamaGui` (global orchestration) |
| `presets.js` | 917 | `window.LlamaGui.presets` |
| `flags/definitions.js` | 382 | `FLAGS` array |
| `flag-core.js` | 380 | `window.LlamaGui.flagCore` |
| `sampler-presets.js` | 361 | `window.LlamaGui.samplerPresets` |
| `config-flags-ui.js` | 670 | `window.LlamaGui.configFlagsUi` |
| `chat-ui.js` | 688 | `window.LlamaGui.chatUi` |
| `quick-launch-ui.js` | 573 | `window.LlamaGui.quickLaunchUi` |
| `manager.js` | 768 | `window.LlamaGui.manager` |

### Frontend Module Dependency Graph

```
flags/categories.js ←── flags/definitions.js
flags/options.js    ←── flags/definitions.js
flags/chat-templates.js ←── flags/definitions.js
flags/definitions.js ←── flags/helpers.js ←── flag-core.js ←── config-flags-ui.js
                   ←── flag-validation.js
flag-core.js ←── app.js (configures callbacks)
            ←── config-flags-ui.js (reads flags, renders inputs)
            ←── quick-launch-ui.js (reads/writes shared state)
            ←── chat-ui.js (reads/writes sampler state)
            ←── sampler-presets.js (apply values through flagCore)
            ←── presets.js (collect/apply preset values)
            ←── api-tab.js (reads endpoint config)
            ←── manager.js (install/status)

app.js is the orchestrator:
  - initializes all modules with dependencies
  - wires tab switching, launch/stop, polling, toasts
  - provides shared helpers (copyText, template mapping)
```

---

## 5. Key Patterns

### 5a. Shared State (flagCore)

**Single source of truth:** `window.LlamaGui.flagCore` owns:
- `currentTool` ("llama-server" | "llama-cli")
- `selectedModel` (filename string)
- `flagValues` (flat object of flag id → value)

**All mutations through setters:**
- `setFlagValue(id, value)` → calls `setMultipleFlagValues()`
- `setMultipleFlagValues(patch)` → patches `flagValues`, fires `afterPatch` + `postUpdate` callbacks
- `applyFlagValues(data)` → replaces all values, fires `afterApply` + `postUpdate`

**Readers:** All tabs read from `flagCore.getFlagValues()`. No per-tab copies.

**Anti-pattern guards (from AGENTS.md):**
- Never mutate `flagValues` directly
- Never maintain separate options lists for duplicated settings
- Never create per-tab state copies
- Never use `innerHTML` with user/model content

### 5b. Flag System

**`FLAGS` array** in `ui/js/flags/definitions.js` (134 entries):
- Each flag: `{ id, flag, category, type, label, desc, tool, default, options, min, max, ... }`
- Types: `bool`, `int`, `float`, `text`, `path`, `enum`, `multi_enum`
- `tool` field: `"both"`, `"server"`, `"cli"` — controls visibility
- Categories: model, context, cpu, gpu, sampling, rope, conversation, lora, kv, speculative, server, grammar, logging, advanced
- Submenus within categories (e.g., "MCP Settings" in server)
- `false_flag` for boolean negation (e.g., `--mmap` / `--no-mmap`)

**Launch args generation** (`flagCore.getLaunchArgs()`):
1. Iterate FLAGS, filter by tool
2. Skip inert defaults (explicit allowlist in `shouldOmitFlagValue`)
3. Skip speculative flags when not enabled
4. Build `[flag, value]` pairs
5. Parse + append custom args
6. Append model path as `-m models/<name>`
7. Return `{ args, error, warnings }`

### 5c. Chat Template Presets

**Three sources:**
- `BUILTIN_CHAT_TEMPLATES` — 51 llama.cpp template names (compatibility allowlist)
- `CHAT_TEMPLATE_PRESETS` — curated dropdown presets (Kobold Lite-style names)
- `ui/templates/*.jinja` — 14 bundled Jinja files for non-built-in presets

**Modes:** `auto`, `auto_alias`, `builtin`, `bundled`

**State mapping helpers** in `app.js`:
- Built-in → sets `chat_template`, clears `chat_template_custom`
- Bundled → clears `chat_template`, sets `chat_template_custom` to file path
- Auto → clears both

### 5d. Sampler Presets

**Built-ins** in `app-data.js`: Neutral, Balanced, Creative, Precise
**Custom** in localStorage: `llama_gui_sampler_presets_v1`
**Apply flow:** `samplerPresets.applySamplerPresetValues()` → `flagCore.setMultipleFlagValues()`

### 5e. Preset System (full launcher presets)

`ui/js/presets.js` (917 lines) — save/load/delete/update/import/export full launcher configs as JSON.
- Stored on filesystem in `presets/` dir
- Backend CRUD via `/api/presets` routes
- Grouped by model, searchable, collapsible
- Shortcut export (Windows `.cmd`)

### 5f. Chat Flow

1. Frontend sends POST `/api/chat/completions` with messages + sampler params
2. Backend (`routes/chat.py`) optionally performs web search
3. Backend proxies to `llama-server` `/v1/chat/completions` with SSE streaming
4. Frontend (`chat-ui.js`) renders markdown via `chat-rendering.js`
5. Conversations stored in localStorage

### 5g. Process Management

1. Frontend calls `POST /api/launch` with args from `flagCore.getLaunchArgs()`
2. Backend (`services/process_manager.py`) spawns subprocess
3. stdout/stderr streamed to output buffer (thread-safe)
4. Frontend polls `GET /api/output` for terminal display
5. `POST /api/stop` kills process (platform-specific signal handling)

---

## 6. Test Infrastructure

### Backend Tests (`tests/backend/`)
- `test_backend_foundation.py`
- `test_extracted_routes.py`
- `test_http_adapters.py`
- `test_routing.py`
- `test_server_baseline.py`
- `test_services.py`
- Run: `python -m unittest discover tests -v`

### Frontend Tests (`tests/frontend/`)
- `custom_launch_args_unit.cjs` — parser unit tests (run with `node`)
- `flag_sync_smoke.cjs` — Playwright smoke test for shared state sync
- `js_syntax_check.cjs` — syntax validation
- `module_namespace_unit.cjs` — namespace checks
- `presets_unit.cjs` — preset logic tests
- Run all: `npm run test` (syntax → unit → modules → Playwright)
- Playwright is dev-only (`devDependencies`), not in `requirements.txt`

### NPM Scripts
```json
"test": "npm run test:syntax && node tests/frontend/custom_launch_args_unit.cjs && npm run test:frontend:modules && npm run test:frontend"
"test:syntax": "node tests/frontend/js_syntax_check.cjs"
"test:frontend:modules": "node tests/frontend/module_namespace_unit.cjs"
"test:frontend": "node tests/frontend/flag_sync_smoke.cjs"
```

---

## 7. Build / Deploy Story

### Runtime
- **No build step.** Static files served directly.
- **Python deps:** `pip install -r requirements.txt` (certifi, ddgs, huggingface_hub)
- **Start:** `python server.py` (or platform scripts: `windows_start.bat`, `mac_linux_start.sh`)
- **Default:** `127.0.0.1:5240`, configurable via `LLAMA_GUI_HOST` / `LLAMA_GUI_PORT` env vars
- **llama-server:** runs on `127.0.0.1:8080` as subprocess

### Release Scripts
- `release.bat` / `release.ps1` — Windows release packaging
- `install.sh` — Linux/macOS installer
- `online_installers/` — online installation scripts

### Auto-Update
- Git-based: `git fetch`, `git pull --ff-only`, `pip install -r requirements.txt`, server restart
- Dirty path classification (safe vs blocking)
- Frontend reloads with cache-busting `?appReload=<timestamp>`

### Pinokio Launcher
- Separate repo: `https://github.com/thomas9120/llama-gui-pinokio`
- Clones this repo into `app/`, runs `server.py`
- `.launcher/launch-llama-gui.ps1` for Pinokio integration

---

## 8. Notable Gotchas & Anti-Patterns

### From AGENTS.md
1. **Never mutate `flagValues` directly.** Always use `setFlagValue()`/`setMultipleFlagValues()`.
2. **Never create per-tab state copies.** Read from `flagCore.getFlagValues()`.
3. **Never maintain separate options lists** for duplicated settings.
4. **No `innerHTML` with user content** (except `renderMarkdown()`).
5. **No new globals in `app.js`** — use `window.LlamaGui` namespace.
6. **No silent error swallowing** — use `console.debug()`/`console.warn()`.
7. **Backend: no broad `except Exception`** without re-raise or logging.
8. **No `os._exit()`** except restart path.
9. **All threading locks required** for state mutations.
10. **Validate all external input** (HF repo IDs, filenames, paths).

### From Bugtracker
- **Cloudflare tunnel stop** produces noisy `ConnectionAbortedError` traceback in terminal (cosmetic, no functional impact).

### From Flag Audit (May 2026)
- 110 upstream `llama.cpp` flags not exposed in UI
- 7 notable default/enum differences from upstream
- 2 missing built-in chat templates (`granite-4.0`, `hunyuan-ocr`)
- `--split-mode` missing `tensor` option

### Script Loading Order
- **Must not change.** Each file depends on those above it.
- New modules go after dependencies, before consumers.

### Platform Concerns
- Windows: `CTRL_BREAK_EVENT` requires `CREATE_NEW_PROCESS_GROUP`
- Frontend must be platform-agnostic; all platform logic lives in backend.

### Frontend Limitations
- No ES modules — global script loading with IIFE pattern
- `app.js` at 932 lines is the largest file — "already 80+ global functions"
- Cache-busting uses mtime-based versioning, not content hashes

---

## 9. Start Here

**For a new agent joining this codebase:**

1. **Read `AGENTS.md`** — contains all rules, anti-patterns, file ownership, recipes
2. **Read `docs/directory.md`** — project structure overview
3. **Read `docs/agent-workflows.md`** — flag audit and template update procedures
4. **Open `backend/app.py`** — understand the HTTP handler, router, and main()
5. **Open `ui/js/flag-core.js`** — understand shared state singleton
6. **Open `ui/js/flags/definitions.js`** — understand the FLAGS array structure
7. **Open `ui/js/app.js`** — understand module initialization and wiring

**Key files to modify for common tasks:**

| Task | Primary File |
|---|---|
| Add/modify a llama.cpp flag | `ui/js/flags/definitions.js` |
| Change shared state behavior | `ui/js/flag-core.js` |
| Change Configure tab rendering | `ui/js/config-flags-ui.js` |
| Change Quick Launch controls | `ui/js/quick-launch-ui.js` |
| Change Chat tab behavior | `ui/js/chat-ui.js` |
| Change backend route | `backend/routes/<name>.py` + `backend/services/<name>.py` |
| Add chat template preset | `ui/js/flags/chat-templates.js` + optionally `ui/templates/*.jinja` |
| Change sampler preset | `ui/js/sampler-presets.js` + `ui/js/app-data.js` |
| Change process management | `backend/services/process_manager.py` |

---

## 10. Supervisor Coordination

No blockers. Report complete. Key open items:
- 110 upstream flags not yet exposed (see `docs/flag_report.md`)
- Presets UI redesign planned but not started (see `docs/todo.md`)
- Cross-platform preset shortcuts (Linux `.desktop`, macOS `.command`) pending
- Tunnel stop traceback cleanup pending
