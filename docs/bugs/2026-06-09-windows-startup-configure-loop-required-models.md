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

**Environment:** Windows, fresh install (first run / bootstrap).

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

## Code path (startup)

```
Window.load_config_and_initialize()
  → Initialize.run(config)
      while (true):
        check_connections()
        initialize_model()
        ensure_required_models()     ← fails if embed/analysis missing
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

## Root cause (code review — not yet verified on Windows)

### 1. Initialization loop does not wait for settings to close (primary UX bug)

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

### 2. Misleading error chrome

`Window.show_connection_error_dialog()` always uses title **"Connection Failed"** even when the failure is **required models** or **no chat model** — not a connection failure.

### 3. Wrong settings tab for connection changes

Required-models failure calls `show_settings(..., "tools")`, not `"connections"`. Even with bug (1) fixed, a user who needs to change the server URL would land on **Tools**, not **Connections**.

### 4. Underlying required-models failure (may be separate)

`ensure_required_models()` tries to auto-pull missing models via `PullManager`. It returns `false` when:

- Connection key missing for a required model
- Pull fails (`model_failed`)
- Model still not available after pull

On Windows, pull may fail (Ollama not installed, firewall, disk space, wrong host). That triggers the error path above; bug (1) then prevents recovery.

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

**Log file (always written, even without `--debug`):**

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

1. **`Initialize.run()`:** After `show_settings()` returns `true`, **do not `continue`**. Exit the loop (or `return`/`break` and rely on `reinitialize` when settings close). Ensure only one restart path.
2. **`show_settings()`:** Optionally `yield` until settings dialog closes instead of fire-and-forget `begin` + immediate return.
3. **Error dialog:** Use accurate titles per failure type (connection vs models vs required tool models).
4. **Tab routing:** For required-models failure, consider **Tools** (pull UI) **and** easy navigation to **Connections**; or open **Connections** when the connection is not working.
5. **Windows verification:** Reproduce with `--debug`, capture `ollmchat.debug.log`, confirm whether pull fails or only the UI loop.

---

## Open questions

- [ ] Exact Windows build / installer version?
- [ ] Ollama installed and running? Which URL was configured (`http://localhost:11434` vs remote)?
- [ ] Does `ollmchat.exe --help` work from a terminal?
- [ ] Contents of `%USERPROFILE%\.cache\ollmchat\ollmchat.debug.log` after one failed **Configure** cycle?
- [ ] Are `bge-m3:latest` and `qwen3:1.7b` present in `ollama list` on that machine?

---

## Changelog

| Date       | Change |
| ---------- | ------ |
| 2026-06-09 | File created from Windows first-run report + code review of `Initialize.vala` / `Window.vala`. |
