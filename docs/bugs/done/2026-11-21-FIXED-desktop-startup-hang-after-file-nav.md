# Desktop startup hangs after file nav appears

**Status:** ✅ Fixed 2026-11-21 — `TreeStore` idle loop, startup/project-pick hang verified clear (Topics 1–7 + append revert).

**Started:** 2026-11-21

**Pointer:** `docs/bug-fix-process.md` · related fixed work:
[`done/2026-10-27-FIXED-agent-pi-startup-does-not-open-project.md`](done/2026-10-27-FIXED-agent-pi-startup-does-not-open-project.md) (added `startup_activate_session`),
[`done/2026-11-02-FIXED-desktop-file-nav-root-only.md`](done/2026-11-02-FIXED-desktop-file-nav-root-only.md) (tree child model).

## Problem

- 🔷 **Expected:** Desktop cold start with saved Agent Pi + project finishes `initialize_client`, mounts `WindowPane` (chat + coder pane), focus composer; UI stays responsive.
- 🔷 **Actual:** Busy dialog clears, file navigation / project tree appears, then the window stops progressing — no chat column, composer not focused, high CPU (~50%+ on one core), further RPC after the first `Folder.fetch_children` is rare or absent.
- 🔷 **Repro (startup):** `./build/ollmapp/ollmchat --debug` with typical `~/.config/ollmchat/config.2.json` (here: `agent=agent-pi`, `project=/home/alan/gitlive/gtktest1`, pending review queue **1** file). Same on 2026-11-21 16:33 and 17:00 runs.
- 🔷 **Repro (project pick):** After Topics 1–3, cold start completes; open project chooser, pick another project → UI hangs (high CPU) again.

## Evidence

- ✔️ **`~/.cache/ollmchat/ollmchat.debug.log`** (2026-11-21 16:33:05–16:33:06 and 16:58:51–16:58:53): hello → `ProjectManager.db_projects` → `rpc_activate_project` → `Folder.fetch_pending_approvals` → `File.fetch` → **`Folder.fetch_children` id=6** → **log stops**; no `FileHistory.parts`, no further startup-phase RPC.
- ✔️ Live repro on this machine (2026-11-21 17:00): same RPC sequence ending at id=6; process still alive after 8s at **~55% CPU** (`ps`), `wchan` **0** (running, not sleeping on I/O).
- ✔️ **`ollmapp/Window.vala` `initialize_client`** closes `busy_dialog` and builds widgets **before** `yield this.startup_activate_session()`; `this.split_view.content = this.window_pane` runs **only after** that yield returns (lines 726–772). A hang there leaves the user with a partial shell (toolbar + file UI from in-flight Agent Pi `activate`) and no main pane.
- ✔️ **`liboccoder/Folder/TreeStore.vala`** `load`: after `Folder.fetch_children`, folder rows are appended from a `waiting` list inside `GLib.Idle.add`. When no row can be attached (`progress < 1`) but `waiting` is non-empty, the idle handler **`return true`** (lines 463–468), rescheduling forever — main-loop spin, starving other async work (including `startup_activate_session` / `switch_to_session`).
- ℹ️ Prior bug reports that only restated “call `startup_activate_session`” did not capture this hang; the 2026-10-27 fix opened the project but did not address the tree-store idle stall.

## Root cause

- ✔️ **Symptom:** Infinite `GLib.Idle` loop in **`TreeStore.load`**: `waiting` still has rows, `progress < 1`, handler does `return true` (~line 468), main loop spins (~55% CPU), startup never finishes.
- ✔️ **Why rows never attach on typical startup:** Project folder is often already in **`path_map`** from `db_projects` before the tree fetch. Row 0 runs **`copy_from`** on that object (updates **`id`** from the daemon) but **`id_map` is not re-keyed** — it still keys the old id. Children from `fetch_children` use **`parent_id`** against the new id → lookup fails every idle pass.
- ✔️ **Contributing (startup layering):** `startup_activate_session` starts **`activate.begin`** before `switch_to_session`; `Agent.Dropdown` and `startup_connect_signals` also call **`activate.begin`**. Overlapping Agent Pi activation + tree load widens the hang window.
- 🚫 **Not a fix:** Logging each stuck row in a loop — that is temporary diagnosis only; remove before merge. Product code should correct attachment and stop the idle reschedule.

## Ruled out

- 🚫 LLM connection / model verification (completes before filesd hello in the captured logs).
- 🚫 filesd hang on hello or `db_projects` (replies logged through id=2).
- 🚫 Blocking forever on `EmptySession.restore_messages` (not used on cold start with empty session).
- 🚫 Using hello version mismatch work (`docs/bugs/2026-11-21-FEATURE-rpc-daemon-hello-version-mismatch.md`) as the explanation for this hang (separate issue).

## Proposed fix

Apply **Topic 1** (all parts) first — restores folder attachment and ends the idle spin. **Topics 2–3** are startup UX / duplication; optional same build.

---

### Topic 1 — `TreeStore.load`: attach children after tree fetch

#### Topic 1a — Re-key `id_map` after `copy_from` on an existing path

**Why:** Daemon row 0 refreshes the project’s `id`; children’s `parent_id` targets that id. Without updating `id_map`, the idle loop never finds the parent.

**Where:** `liboccoder/Folder/TreeStore.vala`, `load`, block `if (this.path_map.has_key(folder.path))` (~lines 410–418).

#### Remove

```vala
			if (this.path_map.has_key(folder.path)) {
				folder.copy_from(incoming, {
					"manager",
					"children",
					"project-files",
					"parent",
					"points-to",
					"buffer"
				});
			}
```

#### Replace with

```vala
			if (this.path_map.has_key(folder.path)) {
				var old_id = (int) folder.id;
				folder.copy_from(incoming, {
					"manager",
					"children",
					"project-files",
					"parent",
					"points-to",
					"buffer"
				});
				if (old_id != (int) folder.id
					&& this.id_map.has_key(old_id)
					&& this.id_map.get(old_id) == folder) {
					this.id_map.unset(old_id);
				}
				this.id_map.set((int) folder.id, folder);
			}
```

#### Topic 1b — Resolve parent by `path_map` when `parent_id` misses

**Why:** Path order is authoritative for tree shape; covers alias/`link_parent` ids that still fail `id_map` after 1a.

**Where:** Same file, idle closure, inner `for` over `waiting` (~lines 449–455).

#### Remove

```vala
						var row = waiting.get(j);
						if (!this.id_map.has_key((int) row.parent_id)) {
							continue;
						}
						row.manager = folder_mgr;
						this.append(this.id_map.get((int) row.parent_id), row);
```

#### Replace with

```vala
						var row = waiting.get(j);
						OLLMfiles.Folder? parent = null;
						if (this.id_map.has_key((int) row.parent_id)) {
							parent = this.id_map.get((int) row.parent_id);
						}
						if (parent == null) {
							var parent_path = GLib.Path.get_dirname(row.path);
							if (parent_path != row.path
								&& this.path_map.has_key(parent_path)) {
								parent = this.path_map.get(parent_path);
							}
						}
						if (parent == null) {
							continue;
						}
						row.manager = folder_mgr;
						this.append(parent, row);
```

#### Topic 1c — Do not reschedule idle when a pass makes no progress

**Why:** Safety net so a remaining data bug cannot spin the main loop; does not substitute for 1a/1b.

**Where:** Same idle closure, tail after the `while (budget > 0 && waiting.size > 0)` loop (~lines 467–472).

#### Remove

```vala
				if (waiting.size > 0) {
					return true;
				}
				this.pending--;
				this.loading = this.pending == 0 ? false : this.loading;
				return false;
```

#### Replace with

```vala
				if (waiting.size > 0 && progress > 0) {
					return true;
				}
				if (waiting.size > 0) {
					this.pending--;
					this.loading = this.pending == 0 ? false : this.loading;
					return false;
				}
				this.pending--;
				this.loading = this.pending == 0 ? false : this.loading;
				return false;
```

💩 **Temporary debug (investigation only — not part of the fix):** If 1a–1c still leave `waiting` non-empty on first run, add a single `GLib.debug` with `waiting.size` and `folder.path` for one repro, note it in **Attempts / changelog**, remove before merge.

---

### Topic 2 — `startup_activate_session`: drop eager `activate.begin`

**Why:** Saved `agent-pi` on `EmptySession` does not change `agent_name`, so `switch_to_session` does not emit `agent_activated`; `session_activated` (dropdown) and `session_restored` (`startup_connect_signals`) already call `Factory.activate.begin`. The block below races Agent Pi tree/RPC before `switch_to_session`.

**Where:** `ollmapp/ChatUserInterface.vala`, method `startup_activate_session` (lines 108–111).

#### Remove

```vala
			var active_factory = this.history_manager.get_active_agent();
			active_factory.activate.begin(this, (obj, res) => {
				active_factory.activate.end(res);
			});
```

ℹ️ **Keep** the following lines unchanged: `yield this.chat_widget.switch_to_session(...)` and the `GLib.Idle.add` for `agent_status_change`.

---

### Topic 3 — `initialize_client`: mount pane before session activation; close busy after

**Why:** Early `busy_dialog.close` plus late `split_view.content` exposes a half-built shell while `startup_activate_session` is blocked.

**Where:** `ollmapp/Window.vala`, `initialize_client`.

#### Remove — early busy close (before history browser)

```vala
			if (this.busy_dialog != null) {
				this.busy_dialog.close();
			}
			
```

#### Add — after `this.agent_manager = new Agent.Manager(this);`, before `this.startup_connect_signals();`

```vala
			this.split_view.content = this.window_pane;
```

#### Remove — late content assignment (after `yield this.startup_activate_session();`)

```vala
			// Set WindowPane as main content
			this.split_view.content = this.window_pane;

```

#### Add — immediately after `yield this.startup_activate_session();`

```vala
			if (this.busy_dialog != null) {
				this.busy_dialog.close();
			}
```

---

### Topic 4 — `Folder.Tree`: one expand pass per tree load

**Why:** `TreeStore.loading` flips false on every finished fetch (startup, `scan_end` reload, project change). The expand walker was changed from a synchronous loop to `GLib.Idle.add` that `return true` each step, but **each** `loading=false` started another walker with no cancel — stacked idles spin the main loop when picking a project.

**Where:** `liboccoder/Folder/Tree.vala` — fields on `Tree`, `folders.notify["loading"]` handler.

#### Add — private fields on `Tree` (after `private bool hiding`)

```vala
		/** Drop idle expand passes from an older tree load. */
		private uint expand_pass = 0;

		/** {@link GLib.Idle} that walks rows after {@link TreeStore.loading} clears. */
		private uint expand_idle = 0;
```

#### Remove — `notify["loading"]` handler body (inside `Tree` constructor)

```vala
			this.folders.notify["loading"].connect(() => {
				spinner.spinning = this.folders.loading;
				status.visible = this.folders.loading;
				if (this.folders.loading) {
					this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
					tree_view.opacity = 0;
					return;
				}
				this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
				tree_view.opacity = 1;
				/* Open every folder after the fetch. Opening during
				 * the fetch stops at the first level.
				 */
				var model = (Gtk.TreeListModel) this.tree_selection.model;
				model.autoexpand = true;
				var expand_index = 0;
				GLib.Idle.add(() => {
					if (expand_index >= model.n_items) {
						if (this.tree_selection.n_items > 0) {
							tree_view.scroll_to(
								0, Gtk.ListScrollFlags.NONE, null);
						}
						return false;
					}
					var row = model.get_row(expand_index);
					expand_index++;
					if (!row.expanded) {
						row.expanded = true;
					}
					return true;
				});
			});
```

#### Replace with

```vala
			this.folders.notify["loading"].connect(() => {
				spinner.spinning = this.folders.loading;
				status.visible = this.folders.loading;
				if (this.folders.loading) {
					this.expand_pass++;
					if (this.expand_idle != 0) {
						GLib.Source.remove(this.expand_idle);
						this.expand_idle = 0;
					}
					this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
					tree_view.opacity = 0;
					return;
				}
				this.expand_pass++;
				var pass = this.expand_pass;
				if (this.expand_idle != 0) {
					GLib.Source.remove(this.expand_idle);
					this.expand_idle = 0;
				}
				this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
				tree_view.opacity = 1;
				/* Open every folder after the fetch. Opening during
				 * the fetch stops at the first level.
				 */
				var model = (Gtk.TreeListModel) this.tree_selection.model;
				model.autoexpand = true;
				var expand_index = 0;
				this.expand_idle = GLib.Idle.add(() => {
					if (pass != this.expand_pass) {
						this.expand_idle = 0;
						return false;
					}
					if (expand_index >= model.n_items) {
						this.expand_idle = 0;
						if (this.tree_selection.n_items > 0) {
							tree_view.scroll_to(
								0, Gtk.ListScrollFlags.NONE, null);
						}
						return false;
					}
					var row = model.get_row(expand_index);
					expand_index++;
					if (!row.expanded) {
						row.expanded = true;
					}
					return true;
				});
			});
```

## Attempts / changelog

- ✔️ 2026-11-21 — Reproduced hang locally; logs + ~55% CPU; traced stall to `TreeStore` idle `return true` with `progress < 1`.
- ✔️ 2026-11-21 — Rewrote **Proposed fix** fences: verbatim **Remove** / **Replace with** / **Add** per `docs/guide-to-writing-plans.md`.
- ✔️ 2026-11-21 — Dropped warning-loop “fix”; Topic 1 is `id_map` sync + path parent resolution + idle stop.
- ✔️ 2026-11-21 — Applied Topics 1a–c (`TreeStore.vala`), Topic 2 (`ChatUserInterface.vala`), Topic 3 (`Window.vala`); user verified startup no longer hangs.
- ✔️ 2026-11-21 — Project pick still hangs; traced to stacked expand idles in `Tree.vala` (idle expand without cancel on new load). Applied Topic 4.
- ✔️ 2026-11-21 — File browser / folder select still hung: per-row expand idle (one `return true` per flat row) saturates the main loop on large trees; user selection did not cancel the walk. Applied Topic 5 (batch 40 rows per idle; cancel expand on `selection_changed`).
- ✔️ 2026-11-21 — Repro log 20:06:15 `Folder.fetch_children` id=7 **replied**, then silence — hang is **post-RPC** on the GTK thread. Full-tree expand after `loading=false` (`autoexpand` + every flat row) can run inside one idle batch without yielding. **Topic 6:** expand **project row only** after fetch; skip `scan_end` tree reload while `TreeStore.loading` (`Nav.vala`).
- ✔️ 2026-11-21 — Repro still ~64% CPU after id=7 with Topic 6 installed (`/usr/bin/ollmchat`). Root cause: **`TreeStore.load` append batch** used `GLib.Idle.add` with **`return true`** (main-loop spin). **Topic 7:** same batching as pre-RPC (`Idle.add(this.load.callback); yield`) — no rescheduling idle; drop per-bind `bind_property` on tree rows (copy css/tooltip once).
- ✔️ 2026-11-21 — User: stop layering hacks. **Reverted append to pre-idle design:** path-sorted first pass + offset/`skipped` waiting drain (see `bab78f46`), keep **1a** `id_map` re-key only; path parent fallback in both passes. **Removed** post-load expand idle in `Tree.vala` — project row opens in `tree_factory.bind` when `!loading`.
- ℹ️ Deleted prior shallow startup notes; this log replaces them with evidence and code-owned proposals.

## Next

- ✅ User verified startup and project pick responsive after Topics 1–7 + append revert.