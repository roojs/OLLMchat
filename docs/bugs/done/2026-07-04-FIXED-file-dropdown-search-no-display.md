# FileDropdown search — pulldown display and search quality

**Status:** **FIXED** (2026-07-09) — Phases A + D verified (pulldown displays rows). Follow-up E–G deferred / not pursued.

**Started:** 2026-07-04

**Log file:** `~/.cache/ollmchat/ollmchat.debug.log` (truncates each run). Run with **`build/ollmapp/ollmchat --debug`**.

**Process:** **`docs/bug-fix-process.md`**. Code fences use **`docs/guide-to-writing-plans.md`** (**Remove** / **Replace with** / **Add**).

---

## Problem

**Original:** FileDropdown RPC returned rows but pulldown showed nothing.

**Now (after Phase D):** Pulldown list works. Remaining issues: labels show basename only (no relative path), wrong file-type icons, apparent duplicate rows, and many `.gitignore` hits on search (likely search/RPC behaviour, not layout).

**Reproduce:** Open code editor → focus file dropdown → type e.g. `oll` → wait ~500 ms.

---

## What we know (2026-07-04)

| Finding | Status |
|---------|--------|
| Popup open on debounce | **Fixed** (Phase A) |
| Rows visible in pulldown | **Fixed** (Phase D) |
| `items_changed` + model wiring | **Confirmed** — was not the display bug |
| Labels: basename only, no grey relpath | **Code cause** — binds wrong property (Phase E) |
| Wrong file-type icons | **Open** — RPC / `icon_name` (Phase F) |
| Duplicate-looking rows | **Open** — needs path debug (Phase G) |
| Many `.gitignore` on search `oll` | **Likely search logic** — path substring match (Phase G) |
| Entry blur → popup hide | Phase C (deferred) |
| Loading indicator | Phase B (deferred) |

**Model chain:**

```
ProjectFiles → FilterListModel → SingleSelection → Gtk.ListView
  (inside Gtk.ScrolledWindow → popup_wrapper → Gtk.Popover)
```

Set in `update_project()` → `set_item_model()`. Failure is **after** the model: zero-height scrolled area.

---

## Phases

Implement and verify **one phase at a time**. Each section below is complete — no cross-references.

---

### Phase A — Popup opens on debounce search

**Status:** ✔️ **Implemented**

**Goal:** Debounce → `popup show` → RPC → model filled. (Rows still need Phase D.)

**Evidence (before fix, run 18:03):**

```
debounce refresh done … filtered=50 popup=false   ← nothing opened popup
```

**Evidence (after fix, run 18:29):**

```
debounce fire query=oll … popup=false
file popup show filtered=50 …
debounce refresh done … filtered=50 popup=true
```

---

#### A1. `liboccoder/SearchableDropdown.vala` — drop empty-list block

**Why:** Popup must open before rows exist (loading / async fill).

**Where:** `set_popup_visible()`, visible branch.

#### Remove

```vala
				// Don't show if no items to display
				if (this.filtered_items.get_n_items() == 0) {
					GLib.debug("popup blocked filtered=0 entry=%s", this.entry.text);
					return;
				}
				
```

---

#### A2. `liboccoder/V2/FileDropdown.vala` — open popup on debounce fire

**Why:** 18:03 log — RPC returned 50 rows but popup never opened.

**Where:** `on_entry_changed()`, debounce timeout + remove keystroke `filtered > 0` gate.

#### Remove

```vala
			this.search_debounce_id = GLib.Timeout.add(500, () => {
				this.search_debounce_id = 0;
				GLib.debug(
					"debounce fire query=%s filtered=%u popup=%s",
					search_text,
					this.filtered_items.get_n_items(),
					this.popup.visible.to_string()
				);
				this.project_files.refresh.begin(search_text, (obj, res) => {
					this.project_files.refresh.end(res);
					GLib.debug(
						"debounce refresh done entry=%s filtered=%u list=%u popup=%s",
						this.entry.text,
						this.filtered_items.get_n_items(),
						this.project_files.get_n_items(),
						this.popup.visible.to_string()
					);
				});
				return false;
			});

			if (this.filtered_items.get_n_items() > 0) {
				GLib.debug(
					"popup on keystroke filtered=%u query=%s",
					this.filtered_items.get_n_items(),
					search_text
				);
				this.set_popup_visible(true);
			} else {
				GLib.debug(
					"popup deferred query=%s filtered=0",
					search_text
				);
			}
```

#### Replace with

```vala
			this.search_debounce_id = GLib.Timeout.add(500, () => {
				this.search_debounce_id = 0;
				GLib.debug(
					"debounce fire query=%s filtered=%u popup=%s",
					search_text,
					this.filtered_items.get_n_items(),
					this.popup.visible.to_string()
				);
				this.set_popup_visible(true);
				this.project_files.refresh.begin(search_text, (obj, res) => {
					this.project_files.refresh.end(res);
					GLib.debug(
						"debounce refresh done entry=%s filtered=%u list=%u popup=%s",
						this.entry.text,
						this.filtered_items.get_n_items(),
						this.project_files.get_n_items(),
						this.popup.visible.to_string()
					);
					if (this.entry.text != search_text) {
						return;
					}
				});
				return false;
			});
```

---

#### A3. `liboccoder/V2/FileDropdown.vala` — remove duplicate refresh on popup open

**Why:** Opening with search text re-fetched and cleared the model mid-open.

**Where:** `set_popup_visible()` override.

#### Remove

```vala
			if (visible && this.entry.text != "") {
				GLib.debug(
					"refresh on popup open query=%s",
					this.entry.text
				);
				this.project_files.refresh.begin(this.entry.text);
			}

```

**Verify Phase A:** Type `oll` → log shows `popup show` → `debounce refresh done … popup=true`. No `popup blocked filtered=0`.

---

### Phase D — Rows visible (zero-height scrolled window)

**Status:** ✅ **Verified** — user confirmed pulldown list working

**Goal:** Pulldown shows file rows after search.

**Evidence (run 18:29, after Phase A):**

```
items_changed pos=0 removed=50 added=50 query=oll
debounce refresh done filtered=50 list=50 popup=true
popup after refresh scroll_upper=0 page=0 scrolled_h=0 popup_h=76
```

Model has 50 items; `scrolled_window` height is 0. V2 constructor adds an extra **`outer` `GtkBox`** around base `popup_wrapper` for `loading_label`. Base `SearchableDropdown` uses `popup.child = popup_wrapper` only.

**Target widget tree:**

```
popup.child = popup_wrapper (Gtk.Box — same as base)
  ├── Gtk.ScrolledWindow (vexpand, hexpand)
  │     └── Gtk.ListView
  └── loading_label
```

---

#### D1. `liboccoder/V2/FileDropdown.vala` — constructor: remove outer popup box

**Why:** Extra `outer` box correlates with `scrolled_h=0` / `popup_h=76`.

**Where:** `FileDropdown()` constructor.

#### Remove

```vala
			var popup_wrapper = this.popup.child as Gtk.Box;
			this.scrolled_window = popup_wrapper.get_first_child() as Gtk.ScrolledWindow;
			var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			popup_wrapper.unparent();
			outer.append(popup_wrapper);
			this.loading_label = new Gtk.Label("Loading…") {
				visible = false,
				margin_top = 4,
				margin_bottom = 4,
				halign = Gtk.Align.CENTER
			};
			outer.append(this.loading_label);
			this.popup.child = outer;
```

#### Replace with

```vala
			var popup_wrapper = this.popup.child as Gtk.Box;
			this.scrolled_window = popup_wrapper.get_first_child() as Gtk.ScrolledWindow;
			this.scrolled_window.vexpand = true;
			this.scrolled_window.hexpand = true;
			this.loading_label = new Gtk.Label("Loading…") {
				visible = false,
				margin_top = 4,
				margin_bottom = 4,
				halign = Gtk.Align.CENTER
			};
			popup_wrapper.append(this.loading_label);
```

**💩 Fallback** (only if `scrolled_h` still 0): set `min_content_height = 200` on `this.scrolled_window` in ctor.

**Verify Phase D:** Type `oll` → `popup after refresh` shows `scrolled_h > 0`, `scroll_upper > 0` → rows visible in UI. **Done.**

---

### Phase E — Show relative path in each row

**Status:** ⏳ **Awaiting approval**

**Goal:** Each row shows basename + grey relative path from project root (intended design per `docs/plans/done/4.2-DONE-code-editor-tool.md`).

**Evidence (code, not guess):** `V2/ProjectFile` defines `display_with_path` (basename + grey relpath). Factory binds `display_with_indicators` instead, which delegates to `File.display_basename` (basename + status marks only).

**Where:** `liboccoder/V2/FileDropdown.vala` — `create_factory()` bind.

#### Replace

```vala
				if (label != null) {
					project_file.bind_property("display_with_indicators", 
						label, "label", BindingFlags.SYNC_CREATE);
				}
```

#### With

```vala
				if (label != null) {
					project_file.bind_property("display_with_path",
						label, "label", BindingFlags.SYNC_CREATE);
				}
```

**Verify Phase E:** Rows show two lines — filename and grey path under it (e.g. `/libocrpc/Client.vala`).

---

### Phase F — File-type icons

**Status:** ⏳ **Investigate first**

**Goal:** Correct MIME/type icon per row.

**Evidence:** Factory binds `project_file.icon_name` → `Gtk.Image`. Client `File.icon_name` uses cached `_icon_name` or `GLib.ContentType.guess(path)`. RPC returns `File` copies from daemon — may not carry content type set at scan time.

**Next (debug, not fix yet):** Log `path` + `icon_name` in factory bind for a few rows; compare daemon `File` fields over RPC vs local guess.

---

### Phase G — Duplicates and `.gitignore` noise in search

**Status:** ⏳ **Investigate first**

**Goal:** Understand whether duplicates and `.gitignore` flood are RPC bugs or search semantics.

**Evidence (daemon `cached_search`, `ollmfilesd/ProjectFiles.vala`):**

- Search matches if **basename OR full path** contains query (case-insensitive).
- Query `oll` matches any path containing `oll` — e.g. `/home/alan/gitlive/OLLMchat/...` matches **`ollmchat`**, so many unrelated paths (including nested `.gitignore` files) qualify.
- `add_file_if_new` skips `file.is_ignored` when **building** the index, but `cached_search` does not re-filter ignored files.
- Duplicates: daemon keys `child_map` by real `file.path`; same file via symlinks should not append twice. Client may show same basename from **different paths** (looks like repeats).

**Next (debug, not fix yet):** Log first 10 `path` values returned for query `oll` in `ProjectFiles.refresh` callback — check for duplicate paths vs duplicate basenames.

**Possible fixes (only after debug confirms):**

- Search: prefer basename match; path match secondary; or exclude `.gitignore` / ignored paths in `cached_search`.
- UI: dedupe by path in client (only if RPC sends dup paths).

---

### Phase B — Loading indicator

**Status:** ⏳ After Phase D

**Goal:** “Loading…” visible during debounce + RPC; hides when rows arrive.

**Why deferred:** Does not fix missing rows; UX polish once Phase D works.

---

#### B1. `libocfiles/V2/ProjectFiles.vala` — `refresh()`: toggle `loading`

**Where:** Start of `refresh()` and after `yield fetch_files`.

#### Remove

```vala
		public async void refresh(string query = "")
		{
			this.query = query;
			this.offset = 0;
			this.total = 0;

			var old_n_items = this.items.size;
			this.items.clear();

			var response = yield this.project.fetch_files(0, 50, query);
			if (response.error != null) {
				GLib.debug(
					"refresh failed query=%s error=%s",
					query,
					response.error.message
				);
				return;
			}
```

#### Replace with

```vala
		public async void refresh(string query = "")
		{
			this.loading = true;
			this.query = query;
			this.offset = 0;
			this.total = 0;

			var old_n_items = this.items.size;
			this.items.clear();

			var response = yield this.project.fetch_files(0, 50, query);
			this.loading = false;
			if (response.error != null) {
				GLib.debug(
					"refresh failed query=%s error=%s",
					query,
					response.error.message
				);
				return;
			}
```

---

#### B2. `liboccoder/V2/FileDropdown.vala` — drive `loading_label`

**Where:** `on_entry_changed()` non-empty branch + `update_project()` notify handler.

#### Add — top of non-empty branch in `on_entry_changed()`, after clearing debounce id

```vala
			this.loading_label.visible = false;
```

#### Add — start of debounce timeout (inside `Timeout.add`, before `set_popup_visible`)

```vala
				this.loading_label.visible = true;
```

#### Add — in refresh callback after `refresh.end`

```vala
					this.loading_label.visible = this.project_files.loading;
```

#### Replace — in `update_project()` notify handler

```vala
				this.loading_label.visible =
					this.project_files.loading
					|| (this.search_debounce_id != 0 && this.entry.text != "");
```

(was: `this.loading_label.visible = this.project_files.loading;`)

#### Add — in `set_popup_visible()` `if (!visible)` block, after clearing debounce id

```vala
				this.loading_label.visible = false;
```

**Verify Phase B:** Type `oll` → “Loading…” before `refresh done` → label hides, rows remain.

---

### Phase C — Arrow browse: popup stays open

**Status:** ⏳ After Phase D (optional before B)

**Goal:** Click arrow → popup stays open → pick a row. Editor click closes popup.

**Evidence:** `entry blur focus=GtkText` → `popup hide` ~1s after open.

**Focus model:**

- **🔷 Search:** entry keeps focus while typing.
- **🔷 Browse (arrow):** focus moves to list after open.
- **🚫** No `entry.grab_focus()` on arrow press.

**Ship all three edits below together.**

---

#### C1. `liboccoder/SearchableDropdown.vala` — `ListView.can_focus = true`

#### Remove

```vala
			this.list = new Gtk.ListView(this.selection, factory) {
				single_click_activate = true,  // Click activates item
				can_focus = false  // Don't allow list view to receive focus - keep focus on entry
			};
```

#### Replace with

```vala
			this.list = new Gtk.ListView(this.selection, factory) {
				single_click_activate = true,
				can_focus = true
			};
```

---

#### C2. `liboccoder/SearchableDropdown.vala` — deferred entry blur close

#### Remove

```vala
			focus_controller.leave.connect(() => {
				if (!this.popup.visible) {
					return;
				}
				var focus = this.get_root()?.get_focus() as Gtk.Widget;
				GLib.debug(
					"entry blur entry=%s focus=%s",
					this.entry.text,
					focus == null ? "null" : focus.get_type().name()
				);
				this.set_popup_visible(false);
			});
```

#### Replace with

```vala
			focus_controller.leave.connect(() => {
				if (!this.popup.visible) {
					return;
				}
				GLib.Idle.add(() => {
					if (!this.popup.visible) {
						return false;
					}
					var focus = this.get_root()?.get_focus() as Gtk.Widget;
					GLib.debug(
						"entry blur entry=%s focus=%s",
						this.entry.text,
						focus == null ? "null" : focus.get_type().name()
					);
					if (focus == this.entry || focus == this.list) {
						return false;
					}
					if (focus != null && this.is_ancestor(focus)) {
						return false;
					}
					this.set_popup_visible(false);
					return false;
				});
			});
```

---

#### C3. `liboccoder/SearchableDropdown.vala` — focus list (browse) or entry (search)

#### Remove

```vala
				// Ensure entry has focus before showing popup
				// Only grab focus if entry doesn't already have it to avoid selecting text
				if (!this.entry.has_focus) {
					this.entry.grab_focus();
				}
				// Always ensure cursor is at end and no text is selected when showing popup
				this.entry.set_position(-1);
				this.entry.select_region(-1, -1);
				this.popup.popup();
```

#### Replace with

```vala
				this.popup.popup();
				if (this.entry.text == "") {
					this.list.grab_focus();
				} else {
					if (!this.entry.has_focus) {
						this.entry.grab_focus();
					}
					this.entry.set_position(-1);
					this.entry.select_region(-1, -1);
				}
```

**Verify Phase C:** Clear entry → click arrow → no immediate `popup hide` → select file → click editor → popup closes.

---

## Deferred

**Scroll-to-top idle** in `SearchableDropdown` — only after Phase D shows `scrolled_h > 0`. Repositioning a zero-height scroller was not the issue.

---

## Debug lines (remove when bug closed)

| File | Grep for |
|------|----------|
| `V2/FileDropdown.vala` | `debounce`, `file popup show`, `popup after refresh` |
| `SearchableDropdown.vala` | `popup show`, `popup layout`, `entry blur` |
| `V2/ProjectFiles.vala` | `items_changed`, `refresh done` |

---

## Changelog

| Date | Phase | Result |
|------|-------|--------|
| 2026-07-04 | Debug + investigation | RPC OK; popup blocked; layout suspect |
| 2026-07-04 | **A** implemented | Popup opens; rows still invisible |
| 2026-07-04 | Run 18:29 | `items_changed` OK; `scrolled_h=0` confirmed |
| 2026-07-04 | **D** verified | Pulldown list working |
| 2026-07-04 | Follow-up E–G documented | paths, icons, search quality |
| 2026-07-04 | Doc reorganized by phase | — |
| 2026-07-09 | **Closed** — primary display bug fixed; E–G (paths, icons, search quality) deferred |
