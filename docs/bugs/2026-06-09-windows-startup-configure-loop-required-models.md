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

## Proposed fix (implemented 2026-06-09 — pending Windows/Wine verification)

Hunks are **Remove** / **Replace with** from the tree; verify surrounding context before applying.

See **`.cursor/rules/CODING_STANDARDS.md`**: no defensive null checks on config casts; no nested tab-routing heuristic in `run()` (bootstrap + repair fixes the empty-connection case); title derived from `settings_page` inside `show_settings()` only; `continue` → `return false` without redundant `if (!(yield …))` wrapper; debug log dir creation matches `libollamaweb/Model.vala` `save()`.

1. Bootstrap: connection before `setup_config_defaults()` (`ollmapp/Window.vala`)
2. Repair empty `codebase_search` embed/analysis on load (`libocvector/Tool/CodebaseSearchTool.vala`)
3. Init loop: `return false` after `show_settings()`, not `continue` (`ollmapp/Initialize.vala`)
4. Error dialog title from `settings_page` + `dialog_title` on `show_connection_error_dialog()` (`ollmapp/Initialize.vala`, `ollmapp/Window.vala`)
5. Debug log dir on Windows (`libollmchat/ApplicationInterface.vala`)

---

### 1. `ollmapp/Window.vala` — bootstrap: connection before tool defaults

**Why:** `default_connection()` must be set when `CodebaseSearchTool.setup_tool_config_default()` runs.

**Where:** `show_bootstrap_dialog()`, `bootstrap_dialog.closed` handler.

**Depends on:** none.

#### Remove

```vala
				var app = this.app as OllmchatApplication;
				app.tools_registry.setup_config_defaults(config);
				app.vector_registry.setup_config_defaults(config);

				config.connections.set(this.bootstrap_dialog.verified_connection.url, 
					this.bootstrap_dialog.verified_connection);
```

#### Replace with

```vala
				var app = this.app as OllmchatApplication;
				config.connections.set(this.bootstrap_dialog.verified_connection.url,
					this.bootstrap_dialog.verified_connection);
				app.tools_registry.setup_config_defaults(config);
				app.vector_registry.setup_config_defaults(config);
```

---

### 2. `libocvector/Tool/CodebaseSearchTool.vala` — `setup_tool_config_default()`: repair empty configs

**Why:** Bootstrap bug saved `codebase_search` with empty embed/analysis; early return never repairs.

**Where:** `setup_tool_config_default()`, whole method.

**Depends on:** none.

#### Remove

```vala
		public override void setup_tool_config_default(OLLMchat.Settings.Config2 config)
		{
			if (config.tools.has_key("codebase_search")) {
				return;
			}
			
			var tool_config = new CodebaseSearchToolConfig();
			var default_connection = config.default_connection();
			if (default_connection != null) {
				tool_config.setup_defaults(default_connection.url);
			}
			config.tools.set("codebase_search", tool_config);
		}
```

#### Replace with

```vala
		public override void setup_tool_config_default(OLLMchat.Settings.Config2 config)
		{
			var default_connection = config.default_connection();
			if (!config.tools.has_key("codebase_search")) {
				var tool_config = new CodebaseSearchToolConfig();
				if (default_connection != null) {
					tool_config.setup_defaults(default_connection.url);
				}
				config.tools.set("codebase_search", tool_config);
				return;
			}
			if (default_connection == null) {
				return;
			}
			var tool_config = config.tools.get("codebase_search") as CodebaseSearchToolConfig;
			if (tool_config.embed.connection != ""
				&& tool_config.embed.model != ""
				&& tool_config.analysis.connection != ""
				&& tool_config.analysis.model != "") {
				return;
			}
			tool_config.setup_defaults(default_connection.url);
			config.save();
		}
```

---

### 3. `ollmapp/Initialize.vala` — `run()`: do not `continue` after settings shown

**Why:** `show_settings()` returns immediately; `continue` restarts init before settings close. `reinitialize` on `closed` is the single restart path.

**Where:** `run()`, each block that calls `show_settings()` then `continue`.

**Depends on:** §4, §5.

##### Part 1 — no working connection

#### Remove

```vala
				if (working_conn == null) {
					if (!(yield this.show_settings(
						"No working connection found. Please check your connection settings.",
						"connections"))) {
						return false;
					}
					continue;  // Restart loop after settings dialog closes
				}
```

#### Replace with

```vala
				if (working_conn == null) {
					yield this.show_settings(
						"No working connection found. Please check your connection settings.",
						"connections");
					return false;
				}
```

##### Part 2 — no chat model (first `initialize_model` failure)

#### Remove

```vala
				if (!(yield this.initialize_model(config, working_conn))) {
					if (!(yield this.show_settings(
						"No chat model found (only embedding models available). Please add or select a model.",
						"models"))) {
						return false;
					}
					continue;  // Restart loop after settings dialog closes
				}
```

#### Replace with

```vala
				if (!(yield this.initialize_model(config, working_conn))) {
					yield this.show_settings(
						"No chat model found (only embedding models available). Please add or select a model.",
						"models");
					return false;
				}
```

##### Part 3 — required models failure

#### Remove

```vala
				if (!(yield this.ensure_required_models(config))) {
					if (!(yield this.show_settings(
						"Required models are not available. Please ensure models are downloaded.",
						"tools"))) {
						return false;
					}
					continue;  // Restart loop after settings dialog closes
				}
```

#### Replace with

```vala
				if (!(yield this.ensure_required_models(config))) {
					yield this.show_settings(
						"Required models are not available. Please ensure models are downloaded.",
						"tools");
					return false;
				}
```

##### Part 4 — `ensure_model_usage` catch path

#### Remove

```vala
					if (!(yield this.initialize_model(config, working_conn))) {
						if (!(yield this.show_settings(
							"No chat model found (only embedding models available). Please add or select a model.",
							"models"))) {
							return false;
						}
						continue;
					}
```

#### Replace with

```vala
					if (!(yield this.initialize_model(config, working_conn))) {
						yield this.show_settings(
							"No chat model found (only embedding models available). Please add or select a model.",
							"models");
						return false;
					}
```

---

### 4. `ollmapp/Initialize.vala` — `show_settings()`: title from `settings_page`

**Why:** Accurate alert title without a third argument on every `show_settings()` call site.

**Where:** `show_settings()`, start of method before `show_connection_error_dialog` call.

**Depends on:** §5.

#### Remove

```vala
		private async bool show_settings(string error_message, string settings_page)
		{
			var response = yield this.window.show_connection_error_dialog(error_message);
```

#### Replace with

```vala
		private async bool show_settings(string error_message, string settings_page)
		{
			string dialog_title;
			switch (settings_page) {
				case "connections":
					dialog_title = "Connection Failed";
					break;
				case "models":
					dialog_title = "No Chat Model";
					break;
				default:
					dialog_title = "Required Models Unavailable";
					break;
			}
			var response = yield this.window.show_connection_error_dialog(
				error_message,
				dialog_title
			);
```

---

### 5. `ollmapp/Window.vala` — `show_connection_error_dialog()`: title parameter

**Why:** Caller supplies title; hardcoded **Connection Failed** is wrong for models / required-models failures.

**Where:** `show_connection_error_dialog()` signature, body, and docblock.

**Depends on:** none.

#### Remove

```vala
		/**
		 * Shows a warning dialog when connection fails, with option to configure settings.
		 * 
		 * @param error_message The error message to display
		 * @return The response string ("settings" or "cancel")
		 */
		internal async string show_connection_error_dialog(string error_message)
		{
			var alert = new Adw.AlertDialog(
				"Connection Failed",
				error_message + "\n\nPlease check your connection settings and try again."
			);
```

#### Replace with

```vala
		/**
		 * Shows a warning dialog when initialization fails, with option to configure settings.
		 *
		 * @param error_message The error message to display
		 * @param dialog_title Alert title (e.g. connection, chat model, or required-models failure)
		 * @return The response string ("settings" or "cancel")
		 */
		internal async string show_connection_error_dialog(
			string error_message,
			string dialog_title
		) {
			var alert = new Adw.AlertDialog(
				dialog_title,
				error_message + "\n\nPlease check your connection settings and try again."
			);
```

---

### 6. `libollmchat/ApplicationInterface.vala` — `debug_log()`: create log dir on Windows

**Why:** `/`-split path creation fails for `C:\Users\...`; stderr spam on every log line.

**Where:** `debug_log()`, lazy open of `debug_log_file`.

**Depends on:** none.

#### Remove

```vala
				// Try to create directory if it doesn't exist (simple recursive approach)
				var parts = log_dir.split("/");
				var current_path = "";
				foreach (var part in parts) {
					if (part == "") {
						current_path = "/";
						continue;
					}
					if (current_path == "") {
						current_path = part;
					} else {
						current_path = current_path + "/" + part;
					}
					// Try to create directory (ignore errors if it already exists)
					try {
						GLib.DirUtils.create(current_path, 0755);
					} catch (GLib.FileError e) {
						// Ignore if directory already exists
						if (e.code != GLib.FileError.EXIST) {
							// For other errors, continue anyway - file open might still work
						}
					}
				}
```

#### Replace with

```vala
				if (!GLib.FileUtils.test(log_dir, GLib.FileTest.IS_DIR)) {
					GLib.DirUtils.create_with_parents(log_dir, 0755);
				}
```

---

## Open questions

- [ ] Exact Windows build / installer version?
- [x] Ollama reachable and models present? **Yes** — Wine run: 47 models at `http://192.168.88.14:11434`, including `bge-m3:latest` and `qwen3:1.7b`.
- [x] Does `ollmchat.exe --debug` work? **Yes** under Wine; stderr output captured.
- [ ] Contents of `config.json` after bootstrap on native Windows (confirm empty embed/analysis)?
- [ ] Native Windows debug log path — does `%USERPROFILE%\.cache\ollmchat\ollmchat.debug.log` get created after the debug-log fix?

---

## Changelog

| Date       | Change |
| ---------- | ------ |
| 2026-06-09 | File created from Windows first-run report + code review of `Initialize.vala` / `Window.vala`. |
| 2026-06-09 | Added Wine `--debug` evidence; confirmed bootstrap ordering bug (empty `codebase_search` tool config); expanded proposed fixes. |
| 2026-06-09 | Added verbatim **Remove** / **Replace with** code hunks to **Proposed fix**. |
| 2026-06-09 | Revised proposed hunks for **CODING_STANDARDS** (drop defensive null/heuristic tab routing; simplify init loop and debug-log dir). |
| 2026-06-09 | `setup_tool_config_default()` proposal: early return, `!has_key` create path first. |
| 2026-06-09 | Approved hunks applied: `Window.vala`, `Initialize.vala`, `CodebaseSearchTool.vala`, `ApplicationInterface.vala`. `meson compile` OK. |
