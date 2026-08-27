# 8.4.4.2 — URGENT — RPC consumers: Phase 2 items 6–13

> `docs/plans/RPC-1.0-summary.md` is **not** updated for this sub-plan until it is done and archived.

**Status:** **URGENT** — Phase 2 items **6–13** agent-done (**✔️**). Ready for user **✅** / archive.

**Parent:** [`RPC-8.4.4-rpc-invoke-errors.md`](RPC-8.4.4-rpc-invoke-errors.md)

**Prior:** [`RPC-8.4.4.1-URGENT-rpc-consumer-audit.md`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md) — Phase 1 + items **1–5** (**✔️**)

**Depends on:** [`8.4.4`](RPC-8.4.4-rpc-invoke-errors.md) Phase 1; [`8.4.4.1`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md) Phase 1 + Alert/Banner on Window.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

Edits are **Remove** / **Replace with** / **Add** from the tree.
Verify surrounding context before applying.

---

## Purpose

- **🔷** `✔️` Phase 2 items **6–13** — complete (see sections below).
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
- **🔷** Log-only catch → **narrow** `try` (one yield). Soft-fail → Banner/Alert may use one catch for several throws in the same soft path.
- **🚫** Per-feature error methods. Use `Alert.show` / `Banner.show`.
- **🚫** Route `Alert.show` / `Banner.show` into `ActivityBanner`.
- **ℹ️** Soft fails that notify: throw into one `catch` that does critical + Banner (don’t duplicate).

---

## Phase 2 — numbered callers (6–13)

### 6. `✔️` Task markdown links (`ValidateLink`)

When a task’s References section is checked, `ValidateLink.file` asks: is this path in the project (`fetch_file`)? If not, is it a folder (`contains_folder`)? If neither, it appends “file does not exist” for the LLM to fix.

A **failed RPC** must not take the same path as “not in the project”.

- **🔷** Catch each RPC yield separately, `GLib.critical`, do **not** append a “file does not exist” issue. Continue validating other links.
- **🔷** Miss (`null` / not a folder) stays “does not exist”.
- **🔷** **Log only** — no `Banner.show` / `Alert.show` (refinement can hit many links; avoid spam).
- **🚫** One blanket `try` around fetch + folder check + issue append. Log-only catch → wrap **only** the yield that can throw (see `docs/coding-standards.md` **Try/Catch Scope**).
- **ℹ️** Related (not this item’s fences): `ResolveLink.preload_file` also `yield fetch_file` without catch — backlog note only until a later tick. `WriteChange.validate` already `throws` → item **13**.

#### Remove

```vala
		var indexed = yield project.fetch_file (check_path);
		if (indexed != null) {
			return;
		}
		var is_directory = yield project.contains_folder (check_path);
```

#### Replace with

```vala
		OLLMfiles.File? indexed;
		try {
			indexed = yield project.fetch_file (check_path);
		} catch (GLib.Error e) {
			GLib.critical ("ValidateLink.file fetch_file: %s: %s",
				check_path, e.message);
			return;
		}
		if (indexed != null) {
			return;
		}
		bool is_directory;
		try {
			is_directory = yield project.contains_folder (check_path);
		} catch (GLib.Error e) {
			GLib.critical ("ValidateLink.file contains_folder: %s: %s",
				check_path, e.message);
			return;
		}
```

**Keep** (unchanged — outside any `try`):

```vala
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
---

### 7. `✔️` File dropdown / review list (`fetch_files` / `fetch_pending`)

`.begin` from the UI. Catch inside `ProjectFiles` / `ReviewFiles` so every caller is covered.

| Call | Severity | Why |
| --- | --- | --- |
| `ProjectFiles.refresh` / `load_more` | **Banner** | User is browsing/searching; list failed to update |
| `ReviewFiles.refresh` | **Banner** | Pending list failed; Banner only fires on a real error |

- **🔷** Empty page (`msg == "0"`, empty `result`): not an error.
- **🔷** Path-filter miss: omit path. Not an error.
- **🔷** On `refresh` RPC fail: **keep last good page** (do not clear before a successful fetch).
- **🔷** On fail: clear `loading` / `refresh_running` so the UI does not stick.
- **🚫** Empty `fetch_files` is not “scan failed”. Do not change daemon `wait_scan_idle` / `read_dir`.

#### `libocfiles/ProjectFiles.vala` — `refresh`

##### Remove

```vala
			var old_n_items = this.items.size;
			this.items.clear();

			this.loading = true;
			var response = yield this.project.fetch_files(0, 50, query);
			this.loading = false;
```

##### Replace with

```vala
			this.loading = true;
			OLLMrpc.Response response;
			try {
				response = yield this.project.fetch_files(0, 50, query);
			} catch (GLib.Error e) {
				this.loading = false;
				GLib.critical ("ProjectFiles.refresh: %s", e.message);
				this.project.manager.rpc.notification (new OLLMrpc.Notification () {
					method = "Banner.show",
					message = "Could not load project files: " + e.message
				});
				return;
			}
			this.loading = false;
			var old_n_items = this.items.size;
			this.items.clear ();
```

#### `libocfiles/ProjectFiles.vala` — `load_more`

##### Remove

```vala
			this.loading = true;
			var response = yield this.project.fetch_files(
				this.offset,
				50,
				this.query
			);
			this.loading = false;
```

##### Replace with

```vala
			this.loading = true;
			OLLMrpc.Response response;
			try {
				response = yield this.project.fetch_files (
					this.offset,
					50,
					this.query
				);
			} catch (GLib.Error e) {
				this.loading = false;
				GLib.critical ("ProjectFiles.load_more: %s", e.message);
				this.project.manager.rpc.notification (new OLLMrpc.Notification () {
					method = "Banner.show",
					message = "Could not load more files: " + e.message
				});
				return;
			}
			this.loading = false;
```

#### `libocfiles/ReviewFiles.vala` — `refresh`

##### Remove

```vala
				var replay = this.since_marker == 0;
				var files = yield this.fetch_pending();
```

##### Replace with

```vala
				var replay = this.since_marker == 0;
				Gee.ArrayList<FileWithHistory> files;
				try {
					files = yield this.fetch_pending ();
				} catch (GLib.Error e) {
					GLib.critical ("ReviewFiles.refresh: %s", e.message);
					this.manager.rpc.notification (new OLLMrpc.Notification () {
						method = "Banner.show",
						message = "Could not refresh pending files: " + e.message
					});
					break;
				}
```

**Keep** (`refresh_running = false` after the loop — unchanged).

---

### 8. `✔️` Save / reload / disk-changed (Window)

Catch in `ProjectManager` (Window `.begin` sites stay thin).

| Call | Severity | Why |
| --- | --- | --- |
| `write_buffer_to_disk` | **Alert** | Save failed — user must know; buffer may be unsaved |
| `reload_file_from_disk` | **Banner** | Reload/refresh failed; buffer still there |
| `check_active_file_changed` | **Banner** | Transport/RPC fail only; not on every focus. Still return `NO_CHANGE` (do not invent a disk change) |

- **🔷** Stay on the current buffer on save/reload fail.
- **🚫** Treat check RPC throw as a real disk change.

#### `libocfiles/ProjectManager.vala` — `check_active_file_changed`

##### Remove

```vala
			return yield this.active_file.check_changed();
```

##### Replace with

```vala
			try {
				return yield this.active_file.check_changed ();
			} catch (GLib.Error e) {
				GLib.critical ("check_active_file_changed: %s: %s",
					this.active_file.path, e.message);
				this.rpc.notification (new OLLMrpc.Notification () {
					method = "Banner.show",
					message = "Could not check file on disk: " + e.message
				});
				return FileUpdateStatus.NO_CHANGE;
			}
```

#### `libocfiles/ProjectManager.vala` — `write_buffer_to_disk`

##### Remove

```vala
			yield this.active_file.rpc_write();
```

##### Replace with

```vala
			try {
				yield this.active_file.rpc_write ();
			} catch (GLib.Error e) {
				GLib.critical ("write_buffer_to_disk: %s: %s",
					this.active_file.path, e.message);
				this.rpc.notification (new OLLMrpc.Notification () {
					method = "Alert.show",
					message = "Could not save file: " + e.message
				});
			}
```

#### `libocfiles/ProjectManager.vala` — `reload_file_from_disk`

##### Remove

```vala
			yield this.active_file.read();
```

##### Replace with

```vala
			try {
				yield this.active_file.read ();
			} catch (GLib.Error e) {
				GLib.critical ("reload_file_from_disk: %s: %s",
					this.active_file.path, e.message);
				this.rpc.notification (new OLLMrpc.Notification () {
					method = "Banner.show",
					message = "Could not reload file: " + e.message
				});
			}
```

---

### 9. `✔️` Approve / revert buttons

User clicked approve/reject on a pending file change. RPC fail must not refresh the list as if it succeeded.

| Severity | Why |
| --- | --- |
| **Alert** | User initiated a destructive/irreversible-ish action; must know it failed |

- **🔷** Catch in the `.begin` ready callback (cannot throw). Narrow: only `.end(res)`.
- **🔷** On fail: `Alert.show`, re-enable approve/reject buttons, **do not** call `review_files.refresh`.
- **ℹ️** `FileHistory.rpc_revert` reload miss/throw → `Alert.show` already done (item **4**). This item is the **button** path only.

#### `liboccoder/Approvals.vala` — `on_approve_clicked`

##### Remove

```vala
			hist.rpc_approve.begin((obj, res) => {
				hist.rpc_approve.end(res);
				this.project_manager.review_files.refresh.begin();
			});
```

##### Replace with

```vala
			hist.rpc_approve.begin((obj, res) => {
				try {
					hist.rpc_approve.end(res);
				} catch (GLib.Error e) {
					GLib.critical ("approve failed %s: %s",
						this.selected_file.path, e.message);
					this.project_manager.rpc.notification (new OLLMrpc.Notification () {
						method = "Alert.show",
						message = "Could not approve change: " + e.message
					});
					this.approve_button.sensitive = true;
					this.reject_button.sensitive = true;
					return;
				}
				this.project_manager.review_files.refresh.begin();
			});
```

#### `liboccoder/Approvals.vala` — `on_reject_clicked`

##### Remove

```vala
			hist.rpc_revert.begin((obj, res) => {
				hist.rpc_revert.end(res);
				this.project_manager.review_files.refresh.begin();
			});
```

##### Replace with

```vala
			hist.rpc_revert.begin((obj, res) => {
				try {
					hist.rpc_revert.end(res);
				} catch (GLib.Error e) {
					GLib.critical ("revert failed %s: %s",
						this.selected_file.path, e.message);
					this.project_manager.rpc.notification (new OLLMrpc.Notification () {
						method = "Alert.show",
						message = "Could not revert change: " + e.message
					});
					this.approve_button.sensitive = true;
					this.reject_button.sensitive = true;
					return;
				}
				this.project_manager.review_files.refresh.begin();
			});
```

---

### 10. `✔️` Load project list / create project

Several call sites; severity depends on **when the user notices**.

| Site | Severity | Why |
| --- | --- | --- |
| First open / startup project dropdown (`AgentFactory`, `Skill/Factory`, `AgentPi/Factory` `initialize_widget`) | **Alert** | Empty or stale dropdown on first use — user cannot pick a project |
| `Window` agent-dropdown lazy reload (`rpc_load_projects_from_db.begin` when session path missing) | **Alert** | Same — session restore blocked |
| `SettingsDialog/ProjectsPage.load_projects` (user opened Projects tab) | **Banner** | Settings context; list can stay empty until retry |
| `ProjectsPage.add_project` → `rpc_create_project` | **Alert** | User explicitly added a folder; failure is serious |
| `ProjectsPage.on_remove_clicked` → `remove_project` RPC fail | **Alert** | Local list already updated — user must know daemon still has it |
| `ollmchat-cli`, `examples/*` | **Log / throw** | No GTK; process exit or stderr is enough |

- **🔷** Startup paths: upgrade `GLib.warning` in existing `catch` → `GLib.critical` + `Alert.show` via `host.notification` / `ui.notification` (factories) or `this.notification` (Window).
- **🚫** Banner for first-startup dropdown load (use **Alert**).
- **🚫** Alert for CLI/examples.

#### `liboccoder/AgentFactory.vala` — `initialize_widget` catch

##### Remove

```vala
			} catch (GLib.Error e) {
				GLib.warning("Failed to initialize AgentFactory widget: %s", e.message);
			} finally {
```

##### Replace with

```vala
			} catch (GLib.Error e) {
				GLib.critical ("initialize AgentFactory widget: %s", e.message);
				host.notification (new OLLMrpc.Notification () {
					method = "Alert.show",
					message = "Could not load projects: " + e.message
				});
			} finally {
```

**Keep** — same catch replacement in `liboccoder/Skill/Factory.vala` and `liboccoder/AgentPi/Factory.vala` `initialize_widget` (message text: `Skills Agent` / `Agent Pi`).

#### `ollmapp/Window.vala` — agent-dropdown lazy load

##### Remove

```vala
					this.project_manager.rpc_load_projects_from_db.begin((obj, res) => {
						this.project_manager.rpc_load_projects_from_db.end(res);
						this.notification(new OLLMrpc.Notification() {
							method = "client.project.load_end",
						});
						project = this.project_manager.projects.path_map.get(
							session.project_path);
						if (project == null) {
							GLib.warning(
								"Session project_path '%s' not found in project list",
								session.project_path);
							return;
						}
```

##### Replace with

```vala
					this.project_manager.rpc_load_projects_from_db.begin((obj, res) => {
						try {
							this.project_manager.rpc_load_projects_from_db.end(res);
						} catch (GLib.Error e) {
							GLib.critical ("session project load: %s", e.message);
							this.notification (new OLLMrpc.Notification () {
								method = "Alert.show",
								message = "Could not load projects: " + e.message
							});
							this.notification (new OLLMrpc.Notification () {
								method = "client.project.load_end",
							});
							return;
						}
						this.notification(new OLLMrpc.Notification() {
							method = "client.project.load_end",
						});
						project = this.project_manager.projects.path_map.get(
							session.project_path);
						if (project == null) {
							GLib.warning(
								"Session project_path '%s' not found in project list",
								session.project_path);
							this.notification (new OLLMrpc.Notification () {
								method = "Alert.show",
								message = "Session project is not in the project list: "
									+ session.project_path
							});
							return;
						}
```

#### `ollmapp/SettingsDialog/ProjectsPage.vala` — `load_projects`

##### Remove

```vala
			yield win.project_manager.rpc_load_projects_from_db();
			this.project_manager = win.project_manager;
```

##### Replace with

```vala
			try {
				yield win.project_manager.rpc_load_projects_from_db();
			} catch (GLib.Error e) {
				GLib.critical ("ProjectsPage.load_projects: %s", e.message);
				win.project_manager.rpc.notification (new OLLMrpc.Notification () {
					method = "Banner.show",
					message = "Could not load projects: " + e.message
				});
				return;
			}
			this.project_manager = win.project_manager;
```

#### `ollmapp/SettingsDialog/ProjectsPage.vala` — `add_project`

##### Remove

```vala
					this.project_manager.rpc_create_project.begin(normalized);
```

##### Replace with

```vala
					this.project_manager.rpc_create_project.begin(normalized,
						(obj, res) => {
						try {
							this.project_manager.rpc_create_project.end(res);
						} catch (GLib.Error e) {
							GLib.critical ("create project %s: %s",
								normalized, e.message);
							this.project_manager.rpc.notification (
								new OLLMrpc.Notification () {
									method = "Alert.show",
									message = "Could not create project: "
										+ e.message
								});
						}
					});
```

#### `libocfiles/ProjectManager.vala` — `remove_project` callback

##### Remove

```vala
				} catch (GLib.Error e) {
					GLib.critical("remove project failed %s: %s", project.path, e.message);
				}
```

##### Replace with

```vala
				} catch (GLib.Error e) {
					GLib.critical ("remove project failed %s: %s",
						project.path, e.message);
					this.rpc.notification (new OLLMrpc.Notification () {
						method = "Alert.show",
						message = "Could not remove project from daemon: "
							+ e.message
					});
				}
```

---

### 11. `✔️` Hugging Face / vector examples / `Summarize`

| Site | Severity | Why |
| --- | --- | --- |
| `examples/oc-hf.vala`, `examples/oc-vector-*`, `ollmchat-cli` | **Log / throw** | No UI; stderr or exit |
| `HuggingFace` tool in app (hub fetch / download start fails) | **Banner** | User invoked tool; non-modal notice |
| `Summarize.load_vector_metadata` (`read_file` tool) | **Log only** | Optional vector rows; AST summary still useful |

- **🔷** HF download progress stays on `ActivityBanner` (`event.hf.*`) — do not reroute.
- **🔷** HF **RPC/transport throw** before/at download: `GLib.critical` + `Banner.show` on `agent.notification` (in addition to tool error returned to LLM).
- **🔷** `Summarize`: narrow `try` around `rpc.call`; on fail `GLib.critical`, return summary without vector rows.

#### `liboctools/ReadFile/Summarize.vala` — `load_vector_metadata`

##### Remove

```vala
			var response = yield this.file.manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Codebase.file_info",
				args = OLLMrpc.args("s", this.file.path)
			});
			var rows = (Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>) response.result;
```

##### Replace with

```vala
			Gee.ArrayList<OLLMfiles.SQT.VectorMetadata> rows;
			try {
				var response = yield this.file.manager.rpc.call (
					new OLLMrpc.Request () {
						method = "RPC-Codebase.file_info",
						args = OLLMrpc.args ("s", this.file.path)
					});
				rows = (Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>) response.result;
			} catch (GLib.Error e) {
				GLib.critical ("Summarize vector metadata: %s: %s",
					this.file.path, e.message);
				return;
			}
```

#### `liboctools/HuggingFace/Request.vala` — download `start.begin` catch

##### Remove

```vala
						} catch (GLib.Error e) {
							this.agent.notification(new OLLMrpc.Notification() {
								method = "event.hf.download.end",
								object_type = "Model",
								message = hub_ref + " error: " + e.message,
							});
						}
```

##### Replace with

```vala
						} catch (GLib.Error e) {
							GLib.critical ("hf download %s: %s",
								hub_ref, e.message);
							this.agent.notification (new OLLMrpc.Notification () {
								method = "event.hf.download.end",
								object_type = "Model",
								message = hub_ref + " error: " + e.message,
							});
							this.agent.notification (new OLLMrpc.Notification () {
								method = "Banner.show",
								message = "Hugging Face download failed: "
									+ e.message
							});
						}
```

**Keep** — examples/CLI: no UI fences (already throw or exit).

---

### 12. `✔️` Activate project / remove project / banner `rpc.*` actions

Not daemon `event.*` notifications. Two fire-and-forget client RPC patterns:

1. **`ProjectManager.activate_project`** — `.begin` after local UI state updated.
2. **`Window` `notification_reply`** — user clicked an ActivityBanner button whose `action` starts with `rpc.` (e.g. `rpc.Codebase.stop` from vector scan).

| Site | Severity | Why |
| --- | --- | --- |
| `activate_project` RPC fail | **Banner** | Project may look selected locally; user can re-select |
| `remove_project` RPC fail | **Alert** | (item **10** fence) local list already changed |
| Banner `rpc.*` action fail | **Banner** | Secondary action; log + dismissible strip |

- **🔷** Upgrade existing `GLib.critical`-only catches to emit notification as above.
- **🚫** Modal Alert on vector-scan Cancel/stop fail.

#### `libocfiles/ProjectManager.vala` — `activate_project` callback

##### Remove

```vala
				} catch (GLib.Error e) {
					GLib.critical("activate project failed %s: %s",
						project != null ? project.path : "", e.message);
				}
```

##### Replace with

```vala
				} catch (GLib.Error e) {
					GLib.critical ("activate project failed %s: %s",
						project != null ? project.path : "", e.message);
					this.rpc.notification (new OLLMrpc.Notification () {
						method = "Banner.show",
						message = "Could not activate project: " + e.message
					});
				}
```

#### `ollmapp/Window.vala` — `notification_reply` `rpc.*`

##### Remove

```vala
				}, (obj, res) => {
					this.project_manager.rpc.call.end(res);
				});
```

##### Replace with

```vala
				}, (obj, res) => {
					try {
						this.project_manager.rpc.call.end(res);
					} catch (GLib.Error e) {
						GLib.critical ("banner rpc action: %s", e.message);
						this.notification (new OLLMrpc.Notification () {
							method = "Banner.show",
							message = "Action failed: " + e.message
						});
					}
				});
```

---

### 13. `✔️` `WriteFile.validate` / `EditMode/Stream`

Tool paths — errors go **back to the LLM**, not Alert/Banner (unless we add a separate user strip later).

| Site | Severity | Why |
| --- | --- | --- |
| `WriteFile.validate` RPC fail | **Return error string** | Same as validation miss — tool rejects with message |
| `EditMode/Stream` write/sync RPC fail | **LLM summary** | Existing `with_error` / `send_response` path |

- **🔷** RPC throw ≠ “file does not exist” / “read failed” — return explicit RPC-failure strings.
- **🔷** Narrow `try` per yield (`exists`, `fetch_file`, `read`) in validate.
- **🔷** `sync_and_update_metadata`: `rpc_write` throws — rely on existing `catch` in `apply_line_based_changes`; add matching `try`/`catch` around `sync_and_update_metadata` in `process_next_change` (today unhandled).

#### `liboctools/WriteFile/Request.vala` — `validate` (`fetch_file` + `exists` block, first occurrence ~line 151)

##### Remove

```vala
				if (project_manager.active_project != null) {
					var indexed = yield project_manager.active_project.fetch_file(
						norm
					);
					if (indexed != null) {
						file = indexed;
					}
				}
				project_manager.buffer_provider.create_buffer(file);
				if ((yield file.exists()) != GLib.FileType.REGULAR) {
					return "file does not exist (required for ast_path / line_numbers mode)";
				}
				if (!(yield file.read())) {
					return "failed to read file";
				}
```

##### Replace with

```vala
				if (project_manager.active_project != null) {
					try {
						var indexed = yield project_manager.active_project.fetch_file (
							norm);
						if (indexed != null) {
							file = indexed;
						}
					} catch (GLib.Error e) {
						GLib.critical ("WriteFile.validate fetch_file: %s: %s",
							norm, e.message);
						return "could not verify file (RPC failed): " + e.message;
					}
				}
				project_manager.buffer_provider.create_buffer(file);
				try {
					if ((yield file.exists()) != GLib.FileType.REGULAR) {
						return "file does not exist (required for ast_path / line_numbers mode)";
					}
				} catch (GLib.Error e) {
					GLib.critical ("WriteFile.validate exists: %s: %s",
						norm, e.message);
					return "could not verify file (RPC failed): " + e.message;
				}
				try {
					if (!(yield file.read())) {
						return "failed to read file";
					}
				} catch (GLib.Error e) {
					GLib.critical ("WriteFile.validate read: %s: %s",
						norm, e.message);
					return "could not read file (RPC failed): " + e.message;
				}
```

**Keep** — apply the same `fetch_file` / `exists` / `read` pattern to the **`has_search`** and **`has_ast`** blocks in the same method (three similar sites).

#### `liboctools/EditMode/Stream.vala` — `sync_and_update_metadata`

##### Remove

```vala
			if (!(yield this.file.rpc_write())) {
				throw new GLib.IOError.FAILED(
					"Failed to write file via RPC: " + this.request.normalized_path);
			}
```

##### Replace with

```vala
			try {
				yield this.file.rpc_write();
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED (
					"Failed to write file via RPC: "
						+ this.request.normalized_path
						+ ": "
						+ e.message);
			}
```

#### `liboctools/EditMode/Stream.vala` — `process_next_change` (queue drain)

##### Remove

```vala
				if (this.request.message_completed) {
					yield this.sync_and_update_metadata();
					this.send_response();
				}
```

##### Replace with

```vala
				if (this.request.message_completed) {
					try {
						yield this.sync_and_update_metadata();
					} catch (GLib.Error e) {
						this.changes.add (new OLLMfiles.FileChange.with_error (
							this.file,
							"Error syncing changes: " + e.message));
					}
					this.send_response();
				}
```

**Keep** — `apply_line_based_changes` already wraps `sync_and_update_metadata` the same way.

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
- **🚫** Soften item **8** save fail to Banner — save is **Alert**.
- **🚫** Log-only for `ReviewFiles.refresh` or `check_active_file_changed` — both are **Banner** (error path only).
- **🚫** Blanket `try` around non-throwing work when the catch is only log / early return. Prefer one yield (or one notification emit) per `try`.
- **ℹ️** Wider `try` is OK when the catch does **Banner** / **Alert** (throw soft-fail into one handler) — still keep setup outside.
- **ℹ️** Items **6–13** applied (**✔️**). Plan ready for user **✅** / archive with **8.4.4.1**.
- **ℹ️** Item **12** “notification `rpc.*`” = ActivityBanner button actions prefixed `rpc.` in `Window.notification_reply` — **not** daemon `event.*` / `client.*`.
- **🚫** Alert/Banner on tool validate paths (item **13**) — return error string / LLM summary instead.
- **🚫** Alert on startup project load (item **10**) — use **Alert**, not Banner.
- **🚫** UI notification for CLI/examples (item **10** / **11**).
- **ℹ️** Phase 2 fences only for the numbered item being ticked.
