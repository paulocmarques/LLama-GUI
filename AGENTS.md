# AGENTS.md

## UI State Sync Rule

When the same setting appears in more than one place in the UI, all instances must stay linked.

Examples:
- A setting shown in both `Configure` and `Quick Launch`
- Any duplicated model, template, sampler, or launch flag control across tabs

Required behavior:
- All duplicate controls must read from the same underlying state object.
- Changing the setting in one tab must immediately update the matching control in every other tab.
- Command preview / launch args must be generated only from the shared underlying state, never from per-tab copies.
- Avoid separate option lists for the same setting. Reuse the same flag definition or shared source list whenever possible.
- Prefer one shared setter function for each shared setting so updates, UI refresh, and launch-arg sync happen in one place.

Anti-patterns to avoid:
- Maintaining a custom dropdown list in one tab while another tab uses the real flag enum
- Having "helper" controls that do not call the same setter as the main control
- Letting one tab keep its own derived copy of a shared setting
- Re-implementing the same setting logic in multiple places

Safe implementation pattern:
1. Define the setting once in shared flag/state definitions.
2. Reuse the same options source anywhere the setting is rendered.
3. Route all changes through one shared setter.
4. Refresh all mirrored controls after state changes.
5. Verify that changing either control updates the other and changes the final command preview.

If a shared control becomes unreliable, prefer removing the duplicate UI over keeping two unsynchronized versions.

## How the program works

### Architecture
- A static web UI served by a Python `http.server` backend.
- The backend handles `llama.cpp` installation, process management, and API proxying.
- `config.json` persists application state (installed version, active backend, tag).

### Backend (`server.py`)
- Manages downloading `llama.cpp` releases from GitHub.
- Runs `llama-server` as a subprocess and streams stdout/stderr.
- Handles preset and model file APIs.
- Selects binary based on backend type (e.g., `cuda-12.4`, `cpu`).

### Frontend
- **`ui/index.html`**: HTML template defining the tabbed layout and UI structure.
- **`ui/js/app.js`**: Core frontend logic; manages tab switching, flag collection, server launch/stop, and output polling.
- **`ui/js/flags.js`**: Defines CLI flag categories, data types, and built-in chat templates.
- **`ui/js/manager.js`**: Handles GitHub release fetching, backend selection, and installation progress UI.
- **`ui/js/presets.js`**: Manages preset normalization, validation, saving, and applying to the UI.
- **`ui/css/style.css`**: Stylesheet implementing the dark theme (Tokyo Night) and responsive layout.

### Tabs
1. **Install**: Download and install `llama.cpp` releases, select backend.
2. **Quick Launch**: One-click model launch with preset configuration.
3. **Configure**: Full CLI flag configuration for `llama-server`.
4. **API**: View and interact with the `llama.cpp` API endpoints.
5. **Presets**: Save, load, and manage preset configurations.

### Data Flow
- UI changes route through a shared setter to update state.
- All mirrored controls read from the same underlying state object.
- Command preview and launch args are generated from shared state, never per-tab copies.
- Server output is polled via HTTP endpoint and streamed to the terminal panel.

## llama.cpp Compatibility

### Flag Reference
- `ui/js/flags.js` is the single source of truth for all CLI flags exposed in the UI.
- Before adding, removing, or modifying any flag definition, verify the flag still exists and works as documented in the upstream `llama.cpp` repository.

### Checking for Updates
1. Check the official repository at `https://github.com/ggerganov/llama.cpp` for flag changes.
2. Review the `llama-server --help` output or the `examples/server/README.md` in the repo for the current flag list, descriptions, and default values.
3. Cross-reference every flag in `ui/js/flags.js` against the upstream documentation:
   - Flag name and shorthand (e.g., `--ctx-size` vs `-c`)
   - Expected value type (integer, string, boolean, enum, etc.)
   - Valid option values for enum-type flags
   - Default values
   - Whether the flag has been renamed, deprecated, or removed
4. If a flag has changed upstream, update `flags.js` to match the new behavior before merging.

### Compatibility Verification
- After any flag-related changes, confirm the generated command preview produces valid arguments that `llama-server` will accept.
- Test that toggling a flag in the UI produces the correct argument in the final launch command.
- Verify that enum dropdowns only contain values still recognized by the current `llama.cpp` version.
- Check that chat template names in `flags.js` match templates bundled with the installed `llama.cpp` release.

## Chat Template Preset Notes

### Current Approach

Llama GUI now treats the template dropdown as a curated preset list rather than a raw dump of every `llama.cpp` built-in template name.

The current preset list is aligned to the user-facing `Instruct Tag Preset` names from Kobold Lite, while still keeping:
- `Auto (from model)`
- the manual `Custom Template File` field

This trims the dropdown without removing low-level backward compatibility for older saved presets that may still reference hidden built-in `llama.cpp` template names directly.

### Shared Source Of Truth

The named dropdown presets now live in [ui/js/flags.js](C:/Users/pegas/Downloads/LLM/Misc%20LLM%20Programs/Llama%20GUI%20-%20Copy/LLama-GUI/ui/js/flags.js):
- `CHAT_TEMPLATE_PRESETS`
- `CHAT_TEMPLATE_PRESET_OPTIONS`

Each preset entry has:
- `value`
- `label`
- `mode`
- and, when needed, either:
  - `builtin`
  - or `path`

Modes:
- `auto`: clears both `chat_template` and `chat_template_custom`
- `auto_alias`: also clears both, but exists as a named dropdown preset
- `builtin`: maps the preset to a real `llama.cpp` built-in template name
- `bundled`: maps the preset to an app-owned Jinja file under `ui/templates/`

Quick Launch does not maintain its own template list. It clones the shared options source from the `chat_template` flag, which keeps Configure and Quick Launch linked.

### State Mapping

Shared selection/state logic is in [ui/js/app.js](C:/Users/pegas/Downloads/LLM/Misc%20LLM%20Programs/Llama%20GUI%20-%20Copy/LLama-GUI/ui/js/app.js).

Important helpers:
- `getChatTemplatePresetByValue(...)`
- `getChatTemplatePresetByBuiltinName(...)`
- `getChatTemplatePresetByPath(...)`
- `getSelectedChatTemplateDropdownValue()`
- `getQuickTemplateSummaryText()`
- `setChatTemplateValue(...)`

Behavior:
- built-in preset:
  - sets `chat_template`
  - clears `chat_template_custom`
- bundled preset:
  - clears `chat_template`
  - sets `chat_template_custom` to a bundled file path
- `Auto (from model)`:
  - clears both
- manual custom file:
  - clears `chat_template`
  - keeps the path in `chat_template_custom`
  - only shows a named preset if the chosen path exactly matches one of the bundled preset files

This keeps Configure and Quick Launch synchronized while still ensuring launch args are generated from launch-relevant state only.

### Bundled Templates

Bundled template files live under [ui/templates](C:/Users/pegas/Downloads/LLM/Misc%20LLM%20Programs/Llama%20GUI%20-%20Copy/LLama-GUI/ui/templates).

They are used for Kobold-style presets that are:
- non-thinking variants
- renamed presets that do not map cleanly to a single built-in `llama.cpp` template
- special tag formats not represented directly by current built-ins

Current bundled files include:
- `alpaca.jinja`
- `chatml-nonthinking.jinja`
- `deepseek-v31-nonthinking.jinja`
- `gemma4.jinja`
- `gemma4-e2b-e4b-nothink.jinja`
- `gemma4-26b-31b-nothink.jinja`
- `glm45-nonthinking.jinja`
- `glm47-nonthinking.jinja`
- `metharme.jinja`
- `mistral-non-tekken.jinja`
- `seed-oss-nonthinking.jinja`
- `openai-harmony-nonthinking.jinja`

These use a small generic Jinja message loop with preset-specific start/end tokens.

### Built-In Mappings

Some Kobold Lite preset names are intentionally mapped to existing `llama.cpp` built-ins rather than bundled files.

Current examples:
- `ChatML` -> `chatml`
- `CommandR` -> `command-r`
- `Gemma 2 & 3` -> `gemma`
- `GLM-4 & 4.5` -> `chatglm4`
- `Granite 4` -> `granite`
- `Kimi ChatML` -> `kimi-k2`
- `Llama 2 Chat` -> `llama2`
- `Llama 3 Chat` -> `llama3`
- `Llama 4 Chat` -> `llama4`
- `Mistral Tekken` -> `mistral-v3-tekken`
- `Phi-3 Mini` -> `phi3`
- `Seed OSS` -> `seed_oss`
- `Vicuna` -> `vicuna`
- `OpenAI Harmony` -> `gpt-oss`

This keeps the user-facing list small while still using `llama.cpp`'s native template support when that is close enough.

### KoboldCppAutomatic

`KoboldCppAutomatic` is handled as a named preset that behaves like an auto/template-from-model selection.

It exists as a selectable label in the dropdown, but its launch behavior is still:
- no `--chat-template`
- no `--chat-template-file`

Because it resolves to the same launch-state shape as `Auto`, it is primarily a UI-facing alias rather than a distinct launch-format implementation.

### Backward Compatibility

The hidden compatibility layer is intentional:
- the dropdown is curated
- the old built-in allowlist is still present for launch/preset compatibility

That means:
- older saved presets using previously exposed built-in names can still launch
- but the main dropdown is no longer cluttered with all of those legacy options

### Reuse Pattern For Future Templates

When adding another Kobold-style or model-specific preset later:

1. Decide whether it should be:
   - `builtin`
   - `bundled`
   - or `auto`/`auto_alias`
2. Add one entry to `CHAT_TEMPLATE_PRESETS`
3. If bundled, add the Jinja file under `ui/templates/`
4. Let `CHAT_TEMPLATE_PRESET_OPTIONS` populate the dropdown automatically
5. Verify reverse mapping:
   - builtin name -> dropdown preset
   - bundled file path -> dropdown preset
6. Verify both Configure and Quick Launch update immediately

### Validation Checklist

For any new preset:
- confirm it appears in Configure and Quick Launch
- confirm both tabs stay linked
- confirm built-in presets use `--chat-template`
- confirm bundled presets use `--chat-template-file`
- confirm manual custom files clear named preset selection unless they match a bundled preset path
