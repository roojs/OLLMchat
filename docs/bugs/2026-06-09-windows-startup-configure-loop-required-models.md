# Windows first-run: "Connection Failed" / required models loop; Configure does not open settings

**Status:** OPEN

**Started:** 2026-06-09

**Reporter:** Alan (fresh Windows install)

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval.

---

## Problem

After a fresh install on **Windows**, the user completes the initial connection setup (host / API details), then gets stuck in a failure loop:

1. Dialog titled **"Connection Failed"** with body along the lines of: *"Required models are not available. Please ensure models are downloaded. Please check your connection settings and try again."*
2. User clicks **Configure**.
3. A **"Checking Connection"** / verify step runs briefly.
4. The same **"Connection Failed"** dialog appears again.
5. User cannot reach settings to change connection details (host, API key, etc.).
6. User could not run debug from the command line (unclear whether `ollmchat.exe --debug` was attempted).

**Expected:** Clicking **Configure** opens the settings dialog (ideally on the relevant tab) and stays open until the user fixes connection or model issues and closes it. Initialization should retry only **after** settings close.

**Actual:** Error dialog reappears immediately (or settings never become usable). User is blocked from changing connection settings.

---

## Reproduction

**Environment:** Windows, fresh install (first run / bootstrap). Also reproduced under **Wine** with `ollmchat.exe --debug` and existing profile data.

1. Launch OLLMchat.
2. Enter Ollama (or compatible) connection details in the bootstrap / first-run dialog and verify.
3. Wait for startup initialization (`Initialize.run()`).
4. When **"Connection Failed"** appears (required-models message), click **Configure**.
5. Observe: **Checking Connection** spinner, then the same error again — no usable settings UI.

**Variants to confirm:**

- Ollama running locally with **no** `bge-m3:latest` / `qwen3:1.7b` installed (pull may fail or not start).
- Ollama **not** running (connection may still pass bootstrap but fail later, or remote-only API).
- Non-Ollama endpoint that does not support model **pull**.

---

## Evidence (Wine / `--debug` run, 2026-06-09)

`ollmchat.exe --debug` against remote Ollama `http://192.168.88.14:11434`:

| Observation | Implication |
| ----------- | ----------- |
| `Connection verified, found 47 models` | Connection and model list work; not a network failure |
| `/api/show` succeeds for `bge-m3:latest`, `qwen3:1.7b`, and many others | Required models **are** on the server |
| `Initialize.vala:308: Connection not found for model:` (empty model name) | `ensure_required_models()` failed because a required `ModelUsage` has **empty `model`** and **`connection` not in `config.connections`** — config problem, not server |
| `ERROR: FAILED TO OPEN DEBUG LOG FILE` on every log line | Separate Windows bug in `ApplicationInterface.debug_log` (path/dir creation); stderr still works with `--debug` |
| `Gdk-WARNING ... Failed to translate keypress` | Harmless Wine/GTK keyboard-layout noise |

**Inspect saved config** (`%USERPROFILE%\.local\share\ollmchat\config.json` or Wine equivalent):

- Expect `tools.codebase_search.embed` and `.analysis` with `connection: ""` and `model: ""` after a bootstrap save.

---

## Code path (startup)

```
Window.load_config_and_initialize()
  → Initialize.run(config)
      while (true):
        check_connections()
        initialize_model()
        ensure_required_models()     ← fails if embed/analysis missing or misconfigured
        on failure:
          show_settings(msg, "tools")
          continue                   ← BUG: runs immediately
```

**Required models at startup** (from `CodebaseSearchToolConfig.required_models()`):

| Role     | Default model      |
| -------- | ------------------ |
| Embed    | `bge-m3:latest`    |
| Analysis | `qwen3:1.7b`       |

Set in `libocvector/Tool/CodebaseSearchToolConfig.setup_defaults()`.

---

## Root cause

### 1. Bootstrap saves empty tool config (primary data bug — **confirmed**)

In `ollmapp/Window.vala` `show_bootstrap_dialog()`, on first-run save:

```vala
app.tools_registry.setup_config_defaults(config);
app.vector_registry.setup_config_defaults(config);

config.connections.set(this.bootstrap_dialog.verified_connection.url,
    this.bootstrap_dialog.verified_connection);
```

`setup_config_defaults()` runs **before** the connection is added. `CodebaseSearchTool.setup_tool_config_default()` calls `config.default_connection()`; at that moment it is **null**, so `setup_defaults(connection_url)` is **skipped**. The tool config is saved with default-empty `embed` and `analysis` (`connection: ""`, `model: ""`).

On every subsequent run, `setup_tool_config_default()` returns early because `codebase_search` already exists — **empty values are never repaired**, even when Ollama has the models.

This matches the Wine log: server has `bge-m3:latest` / `qwen3:1.7b`, but `ensure_required_models()` warns `Connection not found for model:` with an empty model name.

### 2. Initialization loop does not wait for settings to close (primary UX bug)

In `ollmapp/Initialize.vala`, `show_settings()`:

- Shows the error alert; on **Configure**, connects `settings_dialog.closed` → `reinitialize()` (correct).
- Starts `settings_dialog.show_dialog.begin(settings_page)` (async).
- **Returns `true` immediately** — does not await settings close.

The caller then does `continue`, which **immediately restarts** the `while (true)` loop:

```vala
if (!(yield this.ensure_required_models(config))) {
    if (!(yield this.show_settings(
        "Required models are not available. Please ensure models are downloaded.",
        "tools"))) {
        return false;
    }
    continue;  // comment says "after settings dialog closes" but runs now
}
```

So initialization re-runs `check_connections()` / `ensure_required_models()` **while** (or before) settings are shown. That matches the reporter's loop: **Configure → Checking Connection → same error again**.

The `reinitialize` signal on `closed` can also call `load_config_and_initialize()` again, so a fix must avoid **double** restart.

### 3. Misleading error chrome

`Window.show_connection_error_dialog()` always uses title **"Connection Failed"** even when the failure is **required models** or **no chat model** — not a connection failure.

### 4. Wrong settings tab for connection changes

Required-models failure calls `show_settings(..., "tools")`, not `"connections"`. Even with bug (2) fixed, a user who needs to change the server URL would land on **Tools**, not **Connections**.

### 5. Debug log file fails on Windows (secondary)

`ApplicationInterface.debug_log` builds `~/.cache/ollmchat/` and creates directories by splitting the path on `/`. On native Windows paths (`C:\Users\...`) this does not create intermediate directories; `FileStream.open` fails and every log line prints `ERROR: FAILED TO OPEN DEBUG LOG FILE`. Does not block startup but obscures diagnostics.

### 6. Genuine pull failures (possible, separate)

`ensure_required_models()` can also fail when models are truly missing and auto-pull fails (Ollama not installed, firewall, disk space, non-Ollama endpoint). Bug (2) prevents recovery in that case too.

---

## Debug / diagnostics (for reporter)

The GUI **does** support command-line flags (`ollmapp/Application.vala`):

| Flag | Purpose |
| ---- | ------- |
| `--debug` / `-d` | Print debug messages to stderr |
| `--debug-critical` | Treat critical warnings as errors |
| `--disable-indexer` | Disable background semantic indexing |
| `--help` | List options |

**Windows example (PowerShell or cmd):**

```text
"C:\Path\To\ollmchat.exe" --debug
```

Because the app uses `GApplicationFlags.HANDLES_COMMAND_LINE`, flags must be passed to the **`.exe`**, not only a shortcut without arguments.

**Log file (intended path; may fail to open on Windows — see root cause §5):**

```text
%USERPROFILE%\.cache\ollmchat\ollmchat.debug.log
```

(`ApplicationInterface.debug_log` — see `libollmchat/ApplicationInterface.vala`.)

**Config/data (for manual inspection):**

```text
%USERPROFILE%\.local\share\ollmchat\
```

---

## Proposed fix (awaiting approval — not implemented)

### A. Bootstrap ordering (`ollmapp/Window.vala`)

Add the verified connection to `config` **before** calling `setup_config_defaults()`, so `default_connection()` is non-null when `CodebaseSearchTool.setup_tool_config_default()` runs:

```vala
config.connections.set(verified_connection.url, verified_connection);
app.tools_registry.setup_config_defaults(config);
app.vector_registry.setup_config_defaults(config);
```

Alternatively (or additionally), after both are set, explicitly call `setup_defaults(verified_connection.url)` on the new `CodebaseSearchToolConfig`.

### B. Repair existing broken configs (`libocvector/Tool/CodebaseSearchTool.vala`)

In `setup_tool_config_default()`, when `codebase_search` **already exists** but `embed` or `analysis` has empty `connection` or `model`, call `setup_defaults()` using `config.default_connection().url` (or the first working connection). Save config if repaired. Fixes profiles created by the bootstrap bug without requiring manual config edit.

### C. Initialization loop (`ollmapp/Initialize.vala`)

After `show_settings()` returns `true`, **do not `continue`**. `break` or `return true` from `run()` and rely solely on `reinitialize` when settings close. Ensure only one restart path (remove duplicate `load_config_and_initialize` trigger).

Optionally refactor `show_settings()` to `yield` until the settings dialog closes instead of fire-and-forget `show_dialog.begin()` + immediate return.

### D. Error dialog and tab routing (`ollmapp/Window.vala`, `Initialize.vala`)

- Use accurate dialog titles per failure type (connection vs chat model vs required tool models).
- When `ensure_required_models()` fails with missing connection key, open **Connections** (or a message that names the misconfigured tool).
- When failure is missing model on server, keep **Tools** (pull UI).

### E. Debug log on Windows (`libollmchat/ApplicationInterface.vala`)

Replace `/`-split directory creation with `GLib.mkdir_with_parents()` (or equivalent) on the full `log_dir` path so `%USERPROFILE%\.cache\ollmchat\ollmchat.debug.log` opens reliably on native Windows.

### F. Verification

1. Fresh bootstrap on Windows/Wine: confirm `config.json` has non-empty `tools.codebase_search.embed` / `.analysis`.
2. Load an existing broken config (empty embed/analysis): confirm repair on startup.
3. Trigger required-models error with `--debug`: confirm **Configure** opens settings and stays open until closed; init retries once after close, not immediately.
4. Confirm debug log file is created on Windows without stderr spam.

---

## Open questions

- [ ] Exact Windows build / installer version?
- [x] Ollama reachable and models present? **Yes** — Wine run: 47 models at `http://192.168.88.14:11434`, including `bge-m3:latest` and `qwen3:1.7b`.
- [x] Does `ollmchat.exe --debug` work? **Yes** under Wine; stderr output captured.
- [ ] Contents of `config.json` after bootstrap on native Windows (confirm empty embed/analysis)?
- [ ] Native Windows debug log path — does `%USERPROFILE%\.cache\ollmchat\ollmchat.debug.log` get created after fix E?

---

## Changelog

| Date       | Change |
| ---------- | ------ |
| 2026-06-09 | File created from Windows first-run report + code review of `Initialize.vala` / `Window.vala`. |
| 2026-06-09 | Added Wine `--debug` evidence; confirmed bootstrap ordering bug (empty `codebase_search` tool config); expanded proposed fixes (A–F). |
