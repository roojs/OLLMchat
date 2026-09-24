# Startup overlay stuck on “Checking tool models…” (deleted analysis model auto-pull)

**Status:** CLOSED — user archived 2026-09-23. Overlay hang is still intermittent; not confirmed fixed.

**Started:** 2026-09-21

**Reporter:** Alan

**Component:** `ollmapp/Initialize.vala` (`ensure_required_models`, `wait_for_pull`)

**Process:** Follow **`docs/bug-fix-process.md`** — propose → approve → apply.

**Related:**

- ℹ️ [`2026-09-15-FIXED-ollama-non200-json-error-body-ignored.md`](2026-09-15-FIXED-ollama-non200-json-error-body-ignored.md) — same missing `qwen3-coder:30b`; follow-up already noted auto-pull blocking `ensure_required_models`
- ℹ️ [`APP-7.15-SUPERSEDED-startup-loading-feedback.md`](../../plans/done/APP-7.15-SUPERSEDED-startup-loading-feedback.md) — overlay stays up while `wait_for_pull` runs

---

## Problem

🔷 On load, the busy overlay stays on **Checking tool models…** and never finishes.

🔷 Expected: startup continues; when the main UI is up, a header banner says the required tool model is missing so it can be changed in Settings.

🔷 Actual: startup treats the missing name as “must download”, starts an ~18.5 GB pull, and `wait_for_pull` holds init until that pull completes or retries exhaust.

---

## Evidence

- 🔷 User: overlay hung on checking tool models; likely a deleted model used by tools (semantic / codebase search).
- ✔️ `~/.config/ollmchat/config.2.json` `tools.codebase_search.analysis.model` is still **`qwen3-coder:30b`**. Embed is `bge-m3:latest` (present). Code default for analysis is `qwen3:1.7b`.
- ✔️ Ollama `http://192.168.88.14:11434` (2026-09-21 ~13:02):
  - ✔️ `GET /api/tags` — 46 models; **`qwen3-coder:30b` absent**; `bge-m3:latest` and `qwen3:1.7b` present
  - ✔️ `POST /api/show` `{"name":"qwen3-coder:30b"}` → **404** `{"error":"model 'qwen3-coder:30b' not found"}`
- ✔️ `~/.cache/ollmchat/ollmchat.debug.log` (run **12:59:56**):
  - config load → `/v1/models` ×4 (~1 s) → **`start_pull: model_name=qwen3-coder:30b`**
  - `POST http://192.168.88.14:11434/api/pull` body `{"name":"qwen3-coder:30b"}`
  - **no further debug** (pull chunks are not logged; overlay has no progress text)
- ✔️ `~/.local/share/ollmchat/loading.json` after that run:

```json
[{
  "model-name" : "qwen3-coder:30b",
  "status" : "pulling",
  "last-chunk-status" : "pulling 1194192cf2a1",
  "completed" : 126376128,
  "total" : 18556688736
}]
```

  (~126 MB of ~18.5 GB; file writes are rate-limited so this is a lower bound)
- ✔️ `CodebaseSearchToolConfig.required_models()` returns **embed + analysis** (vision is optional). `ensure_required_models` auto-pulls any failed `verify_model`.
- ℹ️ Overlay text is set in `Initialize.run()` immediately before `yield ensure_required_models`. Missing-model path calls `busy_dialog.close()` then `settings_dialog.show_dialog.begin("tools")`, then **`yield wait_for_pull`**. `show_dialog` presents a **second** BusyDialog (“Checking connection…”) and yields `check_all_connections` before Settings is `present`ed. Init does not continue until the 18 GB pull emits `model_complete` / `model_failed`.

---

## Root cause

✔️ Codebase-search **analysis** in config still names **`qwen3-coder:30b`**, which was deleted from the server.

✔️ `verify_model` correctly returns false (`/api/tags` has no such key).

✔️ `ensure_required_models` then **auto-pulls that same name** and **blocks startup** on `wait_for_pull`. Deleting the model is recovered as “download 18 GB again”, not “pick a model that exists”.

✔️ The overlay looks hung because that wait has no timeout, no pull-progress label, and Settings is not shown until `show_dialog` finishes its own connection check.

🚫 Not a hung `/v1/models` or embed check — those finished in ~1 s; `start_pull` is in the same debug file.

---

## Proposed fix

🔷 **Startup:** if a required tool model fails `verify_model`, **do not pull and do not abort init**. Emit `Banner.show` and keep going so the overlay can finish and the main UI appears.

🔷 Use the existing window notification path (`method = "Banner.show"`). `OllmchatWindow` already queues those on `tool_error_banner` / `banner_queue` (Dismiss walks the queue). The handler is wired in the window constructor, so a notify during `ensure_required_models` sits under the busy overlay and is visible when `initialize_client` closes it.

🚫 `GLib.warning` as the user-facing report.

🚫 `Alert.show` (modal) and the current `show_settings(…, "tools")` failure arm — those block load the same way as auto-pull.

🚫 Do not paper over a missing name with a fallback model in code.

🚫 Do not keep blocking auto-pull.

### `ollmapp/Initialize.vala` — `run()`

**Where:** after “Checking tool models…”; drop the false → settings / quit path.

#### Remove

```vala
				if (!(yield this.ensure_required_models(config))) {
					if (this.window.busy_dialog != null) {
						this.window.busy_dialog.close();
					}
					yield this.show_settings(
						"Required models are not available. Please ensure models are downloaded.",
						"tools");
					return false;
				}
```

#### Replace with

```vala
				yield this.ensure_required_models(config);
```

### `ollmapp/Initialize.vala` — `ensure_required_models`

**Where:** the `foreach (var model_usage in required_models)` body after a failed verify; drop `wait_for_pull` (only used here).

#### Remove

```vala
			// Check each required model
			foreach (var model_usage in required_models) {
				// Verify model is available
				if (yield model_usage.verify_model(config)) {
					continue;  // Model is available
				}
				
				// Model not available - need to pull it
				// Show settings dialog if not already shown
				if (!this.window.settings_dialog.visible) {
					if (this.window.busy_dialog != null) {
						this.window.busy_dialog.close();
					}
					this.window.settings_dialog.show_dialog.begin("tools");
				}
				
				// Get connection (early return on failure)
				if (!config.connections.has_key(model_usage.connection)) {
					GLib.warning("Connection not found for model: %s", model_usage.model);
					return false;
				}
				var connection = config.connections.get(model_usage.connection);
				
				// Start background pull operation
				if (!this.window.settings_dialog.pull_manager.start_pull(model_usage.model, connection)) {
					// Pull already in progress - wait for it to complete
					GLib.debug("Pull already in progress for model: %s", model_usage.model);
				}
				
				// Wait for pull to complete (early return on failure)
				if (!(yield this.wait_for_pull(this.window.settings_dialog.pull_manager, model_usage.model))) {
					GLib.warning("Model pull failed: %s", model_usage.model);
					return false;
				}
				
				// Verify model is now available (early return on failure)
				if (!(yield model_usage.verify_model(config))) {
					GLib.warning("Model %s still not available after pull", model_usage.model);
					return false;
				}
			}
```

#### Replace with

```vala
			foreach (var model_usage in required_models) {
				if (yield model_usage.verify_model(config)) {
					continue;
				}
				this.window.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "Required tool model not available: "
						+ model_usage.model
						+ ". Update the tool model in Settings."
				});
			}
```

#### Remove

The whole `wait_for_pull` method.

ℹ️ `ensure_required_models` still returns `true` (no required models, or check finished). Callers no longer treat missing tools as init failure.

---

## Soft unblock (no code)

ℹ️ Point `tools.codebase_search.analysis` (and `usage.ocvector.analysis` if still used) at a present model, e.g. **`qwen3:1.7b`**.

ℹ️ Stop the in-flight Ollama pull of `qwen3-coder:30b` if it is still running; clear or rewrite `~/.local/share/ollmchat/loading.json` so a later `PullManager.restart()` does not resume it.

---

## Attempts / changelog

- ✔️ 2026-09-21 — Read overlay path, debug log, `loading.json`, config, `/api/tags` + `/api/show`. Confirmed auto-pull of deleted analysis model.
- 🔷 2026-09-21 — User: no `GLib.warning`; notify (queue until UI is up). Proposal switched to `Banner.show` + continue init.
- ✔️ 2026-09-21 — Applied continue-init + `Banner.show`. Removed `wait_for_pull` and the tools `show_settings` failure arm. `ninja -C build ollmapp/ollmchat` succeeded.
- 🔷 2026-09-21 — User: app boots, banner visible, **cannot click it or anything else**.
- ✔️ Overlay was still modal (`BusyDialog`) while the banner revealed under it. Defer `Banner.show` until `force_close`; then reveal from `banner_queue`.

## Next

- ℹ️ 2026-09-23 — user archived this log. Checking tool models still hangs sometimes; reopen if it sticks again.
- ℹ️ Optional: cancel the in-flight 18 GB pull / clear `loading.json` so `PullManager.restart()` does not resume it after 60s.
