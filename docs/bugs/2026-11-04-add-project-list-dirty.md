# Adding a project does not refresh the Android list

**Status:** ⏳ user closed 2026-11-04. Fences are applied. The tablet rebuild is the build to test. Adding a project still has to wait until the next one is created.

The desktop Add button creates the project on the daemon and shows it in that window. A tablet or phone that is already connected keeps the list it loaded at startup. Nothing tells it the list changed.

## Problem

- 🔷 Add a project on the desktop while the Android client is already connected to `ollmfilesd`.
- 🔷 The daemon must broadcast that the project list is dirty and needs a refresh.
- 🔷 The Android client marks the project list dirty. It does not call `db_projects` for that broadcast.
- 🔷 Opening Select project while the flag is set loads the list.
- 🔷 If Select project is already on screen, `is_project_dirty` becoming true loads the list.
- 🔷 The new project shows in Select project without reconnecting.

## Evidence

- ✔️ `ollmfilesd/ProjectManager.vala` `create_project` appends the folder, `saveToDB`, and sets `db.is_dirty`. It does not emit `notification`. `rpc_create_project` replies only to the caller.
- ✔️ The desktop caller updates itself. `libocfiles/ProjectManager.vala` `rpc_create_project` appends the returned folder. `ollmapp/SettingsDialog/ProjectsPage.vala` `add_project` is that caller. A second client never runs that append.
- ✔️ Android loads once. `liboccoder/AgentPi/Factory.vala` `activate` calls `db_projects`. `ollmapp/android/OllmchatWindow.vala` `reconnect` calls it again after a new session. Nothing between those two calls asks for the list.
- ✔️ Daemon notifications already reach the tablet. `OllmfilesdApplication` connects `ProjectManager.notification` to `broadcast`, which fans out on the plain and TLS listeners. Android forwards `project_manager.notification` onto the window `notification` signal. That switch handles `client.filesd.retry`, `Banner.show`, and `Alert.show`, then returns.
- ✔️ A second load is enough to show a new row. Client `db_projects` appends every returned folder. `libocfiles/ProjectList.vala` `append` skips an id or path it already has and emits `items_changed`. `ProjectSelector` binds `FilterListModel` / `SortListModel` to that list.
- ℹ️ `event.project.invalidate_cache` is the open-project file signal (`ollmfilesd/File.vala`). It is not a project-list signal.
- ℹ️ `remove_project` has the same missing broadcast. This bug is only the add.

## Root cause

- ✔️ `create_project` updates the daemon list and the database, then stops. No other connected client is told. Android keeps the snapshot from the last `db_projects`.

## Proposed fix

- 🔷 After `create_project` has saved the row, broadcast `event.project.list_dirty`. Same `notification` signal as `event.filesystem.scan_start`. No path. `OLLMrpc.Notification.message` is for user text, and a path belongs in `args`; this event needs neither.
- 🔷 The Android window sets `is_project_dirty` on that method and returns. The idle switch does not load.
- 🔷 Phone and tablet `ProjectSelector` calls `db_projects` when Select project opens with the flag set. The same call runs when `is_project_dirty` becomes true while that pull-over is already showing the project page. The selector watches the property. It does not connect to `notification` for this event.
- 🔷 `db_projects` clears the flag before the RPC. A throw sets it again, so the next open retries. A broadcast that arrives during the RPC sets the flag again and is not wiped by this call.
- 🚫 Do not connect `ProjectSelector` to `notification` for `event.project.list_dirty`. The Android window sets `is_project_dirty`. The selector watches that property.
- 🚫 Do not reuse `event.project.invalidate_cache`. That reloads the open file and the review list.
- 🚫 Do not clear `projects` before the reload. The open project is the existing `Folder` instance. A fresh list would drop it.
- 🚫 Do not add a reload helper. The two `db_projects` calls stay inline.
- 🚫 Do not handle `remove_project` here.
- 🚫 Do not change the desktop window. `Form.DESKTOP` ignores the broadcast. The window that added the project already appended the reply.

### `ollmfilesd/ProjectManager.vala` — `create_project`

**Why:** The row is in the daemon list and the database. Connected clients still have the old snapshot.

**Where:** After `this.db.is_dirty = true`, before `return project`.

#### Add

```vala
			this.notification(new OLLMrpc.Notification() {
				method = "event.project.list_dirty"
			});
```

### `libocfiles/ProjectManager.vala` — `is_project_dirty` and `db_projects`

**Why:** The broadcast is a flag. `db_projects` is the refresh, and every successful start of that call means the list is no longer stale.

**Where:** Property next to `disable_initial_scan`. Inside `db_projects`, clear the flag before the RPC and set it again if that RPC throws.

#### Add

```vala
		/**
		 * Project list is stale. Phone and tablet Select project
		 * calls {@link db_projects} on the next open.
		 */
		public bool is_project_dirty = false;
```

#### Replace

```vala
		public async void db_projects() throws GLib.Error
		{
			var response = yield this.rpc.call(new OLLMrpc.Request() {
				method = "ProjectManager.db_projects"
			});
			if (response.retval.type() == GLib.Type.INVALID) {
				return;
			}
			foreach (var folder in (Gee.ArrayList<Folder>) response.retval.get_object()) {
				folder.manager = this;
				this.projects.append(folder);
			}
		}
```

#### Replace with

```vala
		public async void db_projects() throws GLib.Error
		{
			this.is_project_dirty = false;
			try {
				var response = yield this.rpc.call(new OLLMrpc.Request() {
					method = "ProjectManager.db_projects"
				});
				if (response.retval.type() == GLib.Type.INVALID) {
					return;
				}
				foreach (var folder in (Gee.ArrayList<Folder>) response.retval.get_object()) {
					folder.manager = this;
					this.projects.append(folder);
				}
			} catch (GLib.Error e) {
				this.is_project_dirty = true;
				throw e;
			}
		}
```

### `ollmapp/android/OllmchatWindow.vala` — `project_manager.notification`

**Why:** This handler is connected before Agent Pi builds the project list, so a broadcast still sets the flag. It does not load.

**Where:** The existing `project_manager.notification` lambda that idle-forwards onto `this.notification`.

#### Replace

```vala
			this.project_manager.notification.connect((notif) => {
				GLib.Idle.add(() => {
					this.notification(notif);
					return false;
				});
			});
```

#### Replace with

```vala
			this.project_manager.notification.connect((notif) => {
				if (notif.method == "event.project.list_dirty") {
					this.project_manager.is_project_dirty = true;
				}
				GLib.Idle.add(() => {
					this.notification(notif);
					return false;
				});
			});
```

### `liboccoder/ProjectSelector.vala` — open and `is_project_dirty`

**Why:** The window has already turned the broadcast into the flag. The selector loads from that property. A load in flight ignores the flag write `db_projects` makes for itself, so a thrown call does not start another load.

**Where:** Private field next to `project_recent`. Constructor, after `this.selector` is set. On the phone and tablet branch of `button.clicked`, before `this.selector.visible = true`.

#### Add

Field `loading_projects`. True while this selector's `db_projects` call is running.

```vala
		/**
		 * A project reload from this selector is in flight.
		 * The {@link OLLMfiles.ProjectManager.is_project_dirty}
		 * notify ignores that call's own flag write.
		 */
		private bool loading_projects = false;
```

#### Add

Watch `is_project_dirty` after `this.selector = selector`. A true flag with the project page showing starts `db_projects`.

```vala
			this.manager.notify["is-project-dirty"].connect(() => {
				if (this.loading_projects) {
					return;
				}
				if (!this.manager.is_project_dirty) {
					return;
				}
				if (this.form == Form.DESKTOP) {
					return;
				}
				if (!this.selector.visible || this.selector.kind != "project") {
					return;
				}
				this.loading_projects = true;
				this.manager.db_projects.begin((obj, res) => {
					try {
						this.manager.db_projects.end(res);
					} catch (GLib.Error e) {
						if (e.code == (int) OLLMrpc.RpcErrorCode.NOT_CONNECTED) {
							this.manager.notification(new OLLMrpc.Notification() {
								method = "client.filesd.unreachable",
								id = e.code
							});
							this.loading_projects = false;
							return;
						}
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Alert.show",
							message = "Could not load projects: " + e.message
						});
					}
					this.loading_projects = false;
				});
			});
```

#### Add

On the phone and tablet branch of `button.clicked`, before `this.selector.visible = true`. An already-true flag loads when the page opens. That notify already ran while the page was hidden.

```vala
						if (this.manager.is_project_dirty) {
							this.loading_projects = true;
							this.manager.db_projects.begin((obj, res) => {
								try {
									this.manager.db_projects.end(res);
								} catch (GLib.Error e) {
									if (e.code == (int) OLLMrpc.RpcErrorCode.NOT_CONNECTED) {
										this.manager.notification(new OLLMrpc.Notification() {
											method = "client.filesd.unreachable",
											id = e.code
										});
										this.loading_projects = false;
										return;
									}
									this.manager.notification(new OLLMrpc.Notification() {
										method = "Alert.show",
										message = "Could not load projects: " + e.message
									});
								}
								this.loading_projects = false;
							});
						}
```

## Attempts / changelog

- ℹ️ 2026-11-04 — read `create_project`, the client append, the Android load sites, and the notification forward. No product change.
- ✔️ 2026-11-04 — renamed `rpc_load_projects_from_db` to `db_projects` on the daemon, the client, and the wire method `ProjectManager.db_projects`. No `rpc_` prefix: that prefix is for a handler that relays into a same-named method (`rpc_create_project` → `create_project`). This handler calls `load_projects_from_db`, which stays.
- 🔷 2026-11-04 — the broadcast sets `is_project_dirty`. `db_projects` runs when Select project opens, or immediately when that list is already visible.
- 🔷 2026-11-04 — `ProjectSelector` watches `is_project_dirty`. It does not subscribe to `event.project.list_dirty`.

- ✔️ 2026-11-04 — applied the fences in `ollmfilesd/ProjectManager.vala`, `libocfiles/ProjectManager.vala`, `ollmapp/android/OllmchatWindow.vala`, and `liboccoder/ProjectSelector.vala`.
- ⏳ 2026-11-04 — user closed this. The add-project check waits until the next project is created. Open Select project after that add. The new project is in the list. An add while Select project is already open shows the row without closing the list.

## Next

- ⏳ When the next project is created on the desktop, open Select project on the tablet. The new project is in the list.
