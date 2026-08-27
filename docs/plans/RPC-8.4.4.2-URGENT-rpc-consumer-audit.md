# 8.4.4.2 — URGENT — RPC consumers: Phase 2 items 6–13

> `docs/plans/RPC-1.0-summary.md` is **not** updated for this sub-plan until it is done and archived.

**Status:** **URGENT** **PROPOSED**

**Parent:** [`RPC-8.4.4-rpc-invoke-errors.md`](RPC-8.4.4-rpc-invoke-errors.md)

**Prior:** [`RPC-8.4.4.1-URGENT-rpc-consumer-audit.md`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md) — Phase 1 + items **1–5** (**✔️**)

**Depends on:** [`8.4.4`](RPC-8.4.4-rpc-invoke-errors.md) Phase 1; [`8.4.4.1`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md) Phase 1 + Alert/Banner on Window.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

Edits are **Remove** / **Replace with** / **Add** from the tree.
Verify surrounding context before applying.

---

## Purpose

- **🔷** `⏳` Phase 2 items **6–13** — one numbered item at a time.
- **ℹ️** Items **1–5** live in [`8.4.4.1`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md) (done). Do not re-fence them here.
- **ℹ️** `tests/rpc` is [`RPC-8.4.4`](RPC-8.4.4-rpc-invoke-errors.md).

---

## Shared contract (from 8.4.4.1)

| Severity | Transport |
| --- | --- |
| **Progress / FYI** | `client.*` / `event.*` → `ActivityBanner` |
| **Banner** | `Banner.show` → sticky `Adw.Banner` + FIFO (non-blocking) |
| **Alert** | `Alert.show` → modal dialog |
| **Log only** | `GLib.critical` / `warning` |

- **🔷** Emit via `this.rpc.notification(...)` — no GTK in libocfiles / liboccoder / tools.
- **🚫** Per-feature error methods. Use `Alert.show` / `Banner.show`.
- **🚫** Route `Alert.show` / `Banner.show` into `ActivityBanner`.
- **ℹ️** Soft fails: throw into one `catch` that does critical + Banner (don’t duplicate).

---

## Phase 2 — numbered callers (6–13)

### 6. `⏳` Task markdown links (`ValidateLink`) — **PROPOSED fences**

When a task’s References section is checked, `ValidateLink.file` asks: is this path in the project (`fetch_file`)? If not, is it a folder (`contains_folder`)? If neither, it appends “file does not exist” for the LLM to fix.

A **failed RPC** must not take the same path as “not in the project”.

- **🔷** Catch, `GLib.critical`, do **not** append a “file does not exist” issue. Continue validating other links.
- **🔷** Miss (`null` / not a folder) stays “does not exist”.
- **🔷** **Log only** — no `Banner.show` / `Alert.show` (refinement can hit many links; avoid spam).
- **ℹ️** Related (not this item’s fences): `ResolveLink.preload_file` also `yield fetch_file` without catch — backlog note only until a later tick. `WriteChange.validate` already `throws` → item **13**.

#### Remove

```vala
		var indexed = yield project.fetch_file (check_path);
		if (indexed != null) {
			return;
		}
		var is_directory = yield project.contains_folder (check_path);
		if (is_directory) {
			switch (this.stage) {
				case PhaseEnum.REFINEMENT:
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": path is a directory; use a file path, not a folder.";
					return;
				case PhaseEnum.LIST:
				case PhaseEnum.EXECUTION:
				case PhaseEnum.POST_EXEC:
				default:
					return;
			}
		}
		this.issues += "\n" + "Invalid reference target \"" + link.href +
			"\": file does not exist (resolved from project folder).";
```

#### Replace with

```vala
		try {
			var indexed = yield project.fetch_file (check_path);
			if (indexed != null) {
				return;
			}
			var is_directory = yield project.contains_folder (check_path);
			if (is_directory) {
				switch (this.stage) {
					case PhaseEnum.REFINEMENT:
						this.issues += "\n" + "Invalid reference target \"" + link.href +
							"\": path is a directory; use a file path, not a folder.";
						return;
					case PhaseEnum.LIST:
					case PhaseEnum.EXECUTION:
					case PhaseEnum.POST_EXEC:
					default:
						return;
				}
			}
			this.issues += "\n" + "Invalid reference target \"" + link.href +
				"\": file does not exist (resolved from project folder).";
		} catch (GLib.Error e) {
			GLib.critical ("ValidateLink.file: %s: %s", check_path, e.message);
		}
```

---

### 7. `⏳` File dropdown / review list (`fetch_files` / `fetch_pending`)

`.begin` from the UI. Callback cannot throw.

- **🔷** RPC throw (`project not found`, transport): catch in the ready callback, `GLib.critical`, leave the list (empty or last good page).
- **🔷** Empty page (`msg == "0"`, empty `result`): not an error. Empty dropdown. Do not retry, do not treat as scan-failed.
- **🔷** Path-filter miss (path absent from `all_files`): omit that path. Not an error.
- **🚫** Empty `fetch_files` is not “scan failed”. Do not change daemon `wait_scan_idle` / `read_dir` for this.
- **ℹ️** Same catch for `fetch_pending` / `ReviewFiles.refresh`.
- **ℹ️** Severity (Banner vs log) — decide when fencing this item.

### 8. `⏳` Save / reload / disk-changed banner (Window)

Save buffer, reload from disk, and “file changed on disk” all `.begin` from the window. Today a failed RPC looks like success (`false` ignored, or `NO_CHANGE` so no banner).

- **🔷** Catch, `GLib.critical`, do not show a fake “no change”. Save/reload: stay on the current buffer.
- **ℹ️** Severity (Banner / Alert vs log) — decide when fencing this item.

### 9. `⏳` Approve / revert buttons

- **🔷** Catch, `GLib.critical`. Do **not** refresh the review list after a failed approve/revert. Re-enable the buttons so the user can retry.
- **ℹ️** Severity — decide when fencing (likely `Banner.show` or `Alert.show`).

### 10. `⏳` Load project list / create project

- **🔷** `AgentFactory` / `Skill/Factory` already `catch` + `GLib.warning` on load. Keep (warning → `GLib.critical` if we touch them).
- **🔷** `ollmchat-cli` and examples that already throw: keep throwing (process may exit).
- **💩** `⏳` `SettingsDialog/ProjectsPage` — `GLib.critical` and leave the list as-is unless it already throws.

### 11. `⏳` Hugging Face / vector examples / `Summarize` vectors

- **🔷** Tools and CLI examples that already throw: keep throwing.
- **🔷** `Summarize.load_vector_metadata`: `GLib.critical`, still return the AST summary without vector rows (do not fail the whole summarize).

### 12. `⏳` Activate / remove project, notification `rpc.*` (fire-and-forget `call.begin`)

These send a daemon command and ignore the reply. The ready callback cannot throw.

- **🔷** Catch, `GLib.critical`. No extra dialog. `Client.failed` may also fire.

### 13. `⏳` `WriteFile.validate` / `EditMode/Stream`

Not item 3. These do **not** already throw cleanly for UI.

- **🔷** `WriteFile.validate()` — yields `exists` / `fetch_file` / `read`, returns an error string. No `throws`. A failed RPC is an unhandled warning, not a failed tool call.
- **🔷** `EditMode/Stream` — `process_next_change` / `finalize_and_handle_response` run from `.begin`. The callback cannot throw.
- **ℹ️** `WriteChange.validate` already `throws` — confirm callers catch or propagate when fencing.

---

## LLM notes

- **🚫** Fence Phase 1 `throws` / swallow deletes (done in [`8.4.4.1`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md)).
- **🚫** Re-open items **1–5**.
- **🚫** Fence 8.4.4 wire / `Client.call`.
- **🚫** Edit ollmfilesd `*Params` handlers.
- **🚫** Catch-all back to `false` / `""` / `null` with no log.
- **🚫** Add `throws` up the caller tree unless this item’s fences say so.
- **🚫** Blind `Client.failed` / every catch → UI.
- **🚫** Per-feature error methods. Use `Alert.show` / `Banner.show`.
- **🚫** Treat RPC throw in `ValidateLink` as “file does not exist”.
- **🚫** `Banner.show` for item **6** (log only).
- **ℹ️** Phase 2 fences only for the numbered item being ticked.
