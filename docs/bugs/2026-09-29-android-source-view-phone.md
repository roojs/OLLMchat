# Android — source view on the phone

**Status:** ✔️ 2026-10-01 emulator (`Medium_Phone`, `sw411dp`): file `docs/bugs/2026-09-29-android-source-view-phone.md` open, header Agent Π, footer browser / text editor (selected) / chat. Problems 1 and 3 are still awaiting a phone check.

**Package:** `org.roojs.ollmchat.androidpoc`

**Related:**

- **ℹ️** Earlier scroll, search bar, and font: [`2026-09-28-android-source-view-usability.md`](2026-09-28-android-source-view-usability.md).
- **ℹ️** Editor: `liboccoder/SourceView.vala`. Desktop `open_file` shows the search bar. Android leaves it hidden.
- **ℹ️** Phone bottom bar: `ollmapp/android/OllmchatWindow.vala` (`chat_picker`, `browser_picker`, `editor_picker`).
- **ℹ️** Language id on a buffer: `liboccoder/BufferProvider.vala`.

---

## Problem 1 — Pinch zoom does not change the font

- **🔷** Pinch on the open file should change the source font size.
- **🔷** 2026-09-29, phone: it does not.

### Evidence

- **ℹ️** `.source-view` in `resources/style.css` sets the family only (`Droid Sans Mono`, then `monospace`). It does not set a size.

### Fix

- **✔️** Two-finger pinch and Ctrl+mouse wheel both change `.source-view` font size, clamped to 8–64 px, starting at 14 px. Wheel up grows the font by 2 px per step.
- **ℹ️** The same path runs on the phone and on the desktop.

### Next

- **⏳** **🔷** Confirm on the phone: pinch changes the source font size.

---

## Problem 2 — Hide the search bar for now

- **🔷** With a file open, the search bar stays on screen.
- **🔷** Hide it. Search is not useful enough on the phone to keep the bar.
- **🔷** Bring search back later. Do not design the replacement in this pass.

### Evidence

- **ℹ️** `open_file` sets `this.search_bar.visible = true` on desktop. The bar is hidden when no file is selected.
- **ℹ️** The 2026-09-28 note’s menu idea (window About button opens search) is not the current direction.

### Fix

- **✔️** On Android, `open_file` leaves the bar hidden. Desktop still shows it.

### Next

- **⏳** **🔷** Confirm on the phone: an open file has no search bar.

---

## Problem 3 — Viewing and editing are the same mode

- **🔷** Pan on the file works reasonably well.
- **🔷** It still loses to editing often enough that panning is not a reliable way to read a file.
- **🔷** A document opens read-only. A tap must not bring up the keyboard.
- **🔷** A tap shows a toast under the source view: long hold to start editing.
- **🔷** A long hold starts editing: keyboard up, cursor at the hold.
- **🔷** A tap anywhere that is not the source view locks it again. Toast: view mode, long hold to edit.
- **🚫** A bottom-bar Viewer / Editor pair. That split is not the control.

### Evidence

- **ℹ️** After a file loads, `open_file` sets `this.source_view.editable = true`. The view is focusable, so a tap opens the Android keyboard.
- **ℹ️** Scroll vs cursor is problem 1 in the 2026-09-28 note. This problem is the mode split, not a new scroll patch.

### Fix

- **✔️** On Android a file stays non-editable, with focus off, until a long-press. Desktop still opens editable.
- **✔️** The long-press places the cursor and focuses the view so the keyboard can show.
- **✔️** A short tap toasts `Long hold to start editing` at the bottom of the source view.
- **✔️** A button release outside the source view (header, review bar, footer) returns to view mode and toasts `View mode. Long hold to edit.`

---

## Problem 4 — Bottom bar button sequence

- **🔷** Phone bar today shows Chat and Browser. The editor control is missing or does nothing.
- **🔷** Do not add a separate Viewer button. View vs edit is problem 3.
- **🔷** The three phone buttons stay the ones from [`RPC-8.2.8.11`](../plans/done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) and [`RPC-8.2.8.12`](../plans/done/RPC-8.2.8.12-DONE-android-editor-chrome-bars.md): browser, text editor, chat, on the right of the bar.
- **🔷** A click activates that page. The editor click mounts Agent Pi’s source view.

### Evidence

- **ℹ️** The bar appends `browser_picker`, `editor_picker`, then `chat_picker`. That is the spec order.
- **ℹ️** `editor_picker` was shown only when the active agent `has_editor`, so Chatter hid it and the bar was Browser, Chat.
- **ℹ️** Its click set the pane to `{agent_name}-widget`. That child is absent until `Factory.activate` adds it, so the control did nothing.
- **ℹ️** The Android spec click is `agent_factories.get("agent-pi").activate()`.

### Fix

- **✔️** The text-editor button is shown only for a coding agent. With no editor the phone bar is browser and chat.
- **✔️** Its click calls the active agent's `activate`, which adds that source view and shows the page.
- **🔷** 2026-09-30: On the phone, an agent with no editor does not show the text-editor button. That agent has no editor page. The bar is browser and chat. The text-editor button is shown when the agent has an editor, and that click shows the source view.
- **✔️** 2026-09-30 emulator (`Medium_Phone`, `sw411dp`): desktop `https://192.168.0.16:8443` connected, file `docs/bugs/2026-09-29-android-source-view-phone.md` open and coloured. Footer is the model dropdown, browser, and chat. The text-editor button is not there. The header agent reads Just Ask. The saved window agent is `agent-pi`. `filesd-client.state` stayed `2` (`ENABLED`).
- **✔️** `editor_picker.visible` is set from `get_active_agent().has_editor` before the desktop session switch. That switch uses `ensure_agent_handler()`, which does not emit `agent_activated`. `activate()` then shows the source view. The button stays hidden.
- **✔️** `History.Manager` keeps the `Config2` from before `load_config()` replaces `app.config`. `initialize_client` writes `LIVE` on the new object. The agent list watches the old one, so Agent Pi stays filtered out and the header stays on Just Ask.

### Fix — same config, button after the session switch

- **✔️** One `Config2` for startup and the agent list. `LIVE` reaches the list, so Agent Pi can be selected.
- **✔️** After the desktop session switch, the text-editor button follows that agent.
- **✔️** When the file-server state changes, the agent list selects the active agent. The select signal stays blocked across that filter change. An unblocked change was activating Just Ask (`Replacing chat from old agent` in the 2026-10-01 log) and hiding the button while the header still read Agent Π.
- **✔️** 2026-10-01 emulator, saved `filesd-client.state` set back to `2` (`ENABLED`) then launched: state became `LIVE`, no `Replacing chat` line, same open file, header Agent Π, text-editor button selected between browser and chat.

#### 1. `ollmapp/android/OllmchatWindow.vala` — do not reload config after startup

**Why:** The reload replaces `app.config`. The history manager and the agent list keep the previous object, so they never see `LIVE`.

**Where:** `load_config_and_initialize`, the success branch after `startup.run`.

**Depends on:** none.

#### Remove

```vala
			if (yield startup.run(this.app.config)) {
				this.startup_status_label.label = "Opening chat…";
				this.app.config = (this.app as AndroidApplication).load_config();
				AndroidConnectionConfigTls.apply_to_config(this.app.config);
				yield this.initialize_client(this.app.config);
				return;
			}
```

#### Replace with

```vala
			if (yield startup.run(this.app.config)) {
				this.startup_status_label.label = "Opening chat…";
				yield this.initialize_client(this.app.config);
				return;
			}
```

#### 2. `ollmapp/android/OllmchatWindow.vala` — text-editor button after the session switch

**Why:** The switch does not emit `agent_activated`. The button was set while the session was still Just Ask.

**Where:** `initialize_client`, immediately after the desktop-reached and desktop-unreachable session switches.

**Depends on:** none.

#### Add

```vala
			this.editor_picker.visible = this.history_manager.get_active_agent().has_editor;
```

#### 3. `ollmapp/AgentDropdown.vala` — select the active agent when the file server state changes

**Why:** Agent Pi enters the list only after the state becomes live. The closed button was left on Just Ask.

**Where:** `wire`, the `filesd_client.notify["state"]` handler.

**Depends on:** §1.

#### Remove

```vala
				this.filter.changed(Gtk.FilterChange.DIFFERENT);
				var listed_model = (Gtk.FilterListModel) this.dropdown.model;
				var listed_n = (int) listed_model.get_n_items();
				GLib.debug("agent list model n=%d", listed_n);
				for (var i = 0; i < listed_n; i++) {
					var listed = (OLLMchat.Agent.Factory) listed_model.get_item(i);
					GLib.debug("agent list model i=%d name=%s title=%s",
						i, listed.name, listed.title);
				}
```

#### Replace with

```vala
				/* Filter growth moves the selected row. That must not
				   activate a different agent before the button is shown. */
				this.block_select_signal = true;
				this.filter.changed(Gtk.FilterChange.DIFFERENT);
				var listed_model = (Gtk.FilterListModel) this.dropdown.model;
				var listed_n = (int) listed_model.get_n_items();
				GLib.debug("agent list model n=%d", listed_n);
				var active = this.host.history_manager.get_active_agent();
				for (var i = 0; i < listed_n; i++) {
					var listed = (OLLMchat.Agent.Factory) listed_model.get_item(i);
					GLib.debug("agent list model i=%d name=%s title=%s",
						i, listed.name, listed.title);
					if (listed != active) {
						continue;
					}
					this.dropdown.selected = (uint) i;
				}
				this.block_select_signal = false;
```

---

## Problem 5 — Vala highlighting does not run

- **🔷** A Vala file open in the phone source view is not syntax-coloured.
- **💩** The language data files may not be on the device.

### Evidence

- **ℹ️** `BufferProvider.detect_language` asks `GtkSource.LanguageManager.get_default().guess_language` for the file name. `create_buffer` then calls `get_language` with that id.
- **✔️** `libgtksourceview-5.so` in the Pixiewood tree already contains the `.lang` files, including Vala, as gresources.
- **✔️** Parsing a spec still calls `xmlTextReaderRelaxNGValidate` on `language2.rng`. That call needs a filesystem path. `resource://` does not pass `g_file_test`.
- **✔️** The Android library’s `DATADIR` is `/share`. That path is not on the phone. The first place the manager looks is `XDG_DATA_HOME/gtksourceview-5/language-specs`, which is the extracted `assets/share/` tree.
- **✔️** The built APK listed no `language-specs` files. Style schemes already load from `resource://`, so they do not need a copy.

### Root cause

- **✔️** Without `language2.rng` on disk, every language spec fails validation. The buffer stays uncoloured. The `.lang` data itself is already in the library.

### Fix

- **✔️** The APK build copies `language2.rng`, `language.rng`, and `language.dtd` from the GtkSourceView 5.16.0 wrap into `assets/share/gtksourceview-5/language-specs/`. `verify-apk.sh` requires `language2.rng`.

### Next

- **⏳** **🔷** Rebuild the APK and confirm a `.vala` file is coloured on the phone.
- **⏳** **🔷** Confirm pinch changes font size, and an open file has no search bar.
- **⏳** **🔷** Open a file: no keyboard. A tap toasts “Long hold to start editing”. A long hold edits. A tap outside the file toasts “View mode. Long hold to edit.”
- **⏳** **🔷** Footer, left to right on the right: browser, text editor, chat. The editor button opens the source view.

---

## Appendix — Views by layout and agent

- **ℹ️** Spec: [`RPC-8.2.8.11`](../plans/done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) Phase 3 and [`RPC-8.2.8.12`](../plans/done/RPC-8.2.8.12-DONE-android-editor-chrome-bars.md) Phases 2–3.
- **ℹ️** A coding agent is `has_editor`: Agent Pi, the coder agent, and Skill. Chatter is not.
- **ℹ️** The model dropdown stays on the left in every case. Send follows the composer, not these pages.
- **🔷** Tablet and desktop are the same layout. The tablet is that layout in a smaller window.

### Phone

- **🔷** Coding agent.
  - **🔷** Editor view. Buttons: browser (not selected), text editor (selected), chat (not selected). The source view fills the screen.
  - **🔷** Browser view. Buttons: browser (selected), text editor (not selected), chat (not selected). The browser fills the screen.
  - **🔷** Chat view. Buttons: browser (not selected), text editor (not selected), chat (selected). Chat fills the screen.
- **🔷** No editor.
  - **🔷** Browser view. Buttons: browser (selected), chat (not selected). The browser fills the screen.
  - **🔷** Chat view. Buttons: browser (not selected), chat (selected). Chat fills the screen.

### Tablet and desktop

- **🔷** Chat stays the left column. It is not a separate view.
- **🔷** Coding agent.
  - **🔷** Editor view. Buttons: browser (not selected), text editor (selected). The right side is the source view.
  - **🔷** Browser view. Buttons: browser (selected), text editor (not selected). The right side is the browser.
- **🔷** No editor.
  - **🔷** Browser view. Buttons: browser (selected). The right side is the browser.
  - **🔷** Nothing. Buttons: browser (not selected). The right side is not shown.

---

## What has to change

- **✔️** The two replacements below are in the tree. Not confirmed on a device.

The appendix is the design. These were the places the windows did something else.

- **🔷** The text-editor button is shown only for a coding agent. Phone, tablet, and desktop.
  - **ℹ️** Before this change, the phone and tablet always showed it. `12ef13e4` had stopped hiding it when the agent has no editor.
  - **ℹ️** Before this change, the desktop hid both the browser button and the text-editor button when the agent has no editor, and showed a browser on/off toggle on the left instead.
- **🔷** With no editor, the browser button stays. On the phone the chat button stays too. On a tablet and on the desktop the chat column stays, and there is no chat button.
- **🔷** Leaving a coding agent for one with no editor hides the text-editor button.
  - **🔷** Phone: chat view, whether the editor or the browser was showing. Chat selected. Browser not selected.
  - **🔷** Tablet and desktop, editor was showing: nothing. The right side is hidden. Browser not selected.
  - **🔷** Tablet and desktop, browser was showing: leave the browser open. Browser selected.
  - **ℹ️** Before this change, the tablet opened the browser when the editor was showing. Leaving a coding agent on the desktop hid the right side even when the browser was showing.
- **🔷** A coding agent on a tablet or the desktop always has the editor or the browser on the right. There is no hidden right side for that agent.
- **🔷** The text-editor click shows that coding agent's source view.
  - **ℹ️** Before this change, the phone click always opened Agent Pi, even when the session agent was Skill or the coder.

### 1. `ollmapp/android/OllmchatWindow.vala` — text-editor button and leaving a coding agent

**Why:** The text-editor button is shown only for a coding agent. Its click opens that agent's source view. On the phone, switching to an agent with no editor shows chat. On a tablet, an open browser stays open. If the editor was showing, the right side closes.

**Where:** `initialize_client`, the text-editor click handler and the `agent_activated` handler immediately after it.

**Depends on:** none.

#### Remove

```vala
			this.editor_picker.clicked.connect(() => {
				var factory = this.history_manager.agent_factories.get("agent-pi");
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
			});
			this.history_manager.agent_activated.connect((factory) => {
				if (factory.has_editor) {
					return;
				}
				if (this.pane_stack.visible_child_name != null
					&& this.pane_stack.visible_child_name.has_suffix("-widget")) {
					var ui = this.history_manager.tools.get("browser")
						as OLLMchat.Tool.UiWidgets;
					var view = (Gtk.Widget) ui.view_widget;
					if (this.pane_stack.get_child_by_name("browser") == null) {
						this.pane_stack.add_named(view, "browser");
					}
					this.pane_stack.set_visible_child_name("browser");
				}
				if (!this.is_tablet) {
					return;
				}
				this.schedule_pane_update(true);
			});
```

#### Replace with

The text-editor button follows the agent. The phone goes to chat. The tablet keeps an open browser and otherwise hides the right side.

```vala
			this.editor_picker.clicked.connect(() => {
				var factory = this.history_manager.get_active_agent();
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
			});
			this.editor_picker.visible = this.history_manager.get_active_agent().has_editor;
			this.history_manager.agent_activated.connect((factory) => {
				this.editor_picker.visible = factory.has_editor;
				if (factory.has_editor) {
					return;
				}
				if (!this.is_tablet) {
					this.schedule_pane_update(false);
					return;
				}
				if (this.pane_stack.visible_child_name == "browser") {
					this.schedule_pane_update(true);
					return;
				}
				this.schedule_pane_update(false);
			});
```

### 2. `ollmapp/Window.vala` — desktop bar matches the tablet

**Why:** The desktop keeps the browser button when the agent has no editor. The text-editor button hides. The browser on/off toggle stays off the bar. An open browser stays open. If the editor was showing, the right side closes.

**Where:** `OllmchatWindow` constructor, the `agent_activated` handler, then the startup block immediately after it.

**Depends on:** none.

#### Remove

```vala
			this.history_manager.agent_activated.connect((factory) => {
				if (factory.has_editor) {
					this.chat_widget.chat_bar.tool_button_box.visible = false;
					this.chat_widget.chat_bar.end_box.visible = true;
					return;
				}
				if (this.chat_widget.chat_bar.end_box.visible) {
					this.chat_widget.chat_bar.end_box.visible = false;
					this.chat_widget.chat_bar.toggle_active_tool("browser", false);
				}
				this.chat_widget.chat_bar.tool_button_box.visible = true;
				this.chat_widget.chat_bar.end_box.visible = false;
			});
			if (this.history_manager.get_active_agent().has_editor) {
				this.chat_widget.chat_bar.tool_button_box.visible = false;
				this.chat_widget.chat_bar.end_box.visible = true;
				if (this.window_pane.intended_pane_visible) {
					this.schedule_pane_update(true);
				}
			}
```

#### Replace with

The browser and text-editor buttons stay on the right. Only the text-editor button follows the agent. The right side follows the same rule as the tablet.

```vala
			this.history_manager.agent_activated.connect((factory) => {
				this.chat_widget.chat_bar.tool_button_box.visible = false;
				this.chat_widget.chat_bar.end_box.visible = true;
				this.editor_picker.visible = factory.has_editor;
				if (factory.has_editor) {
					return;
				}
				if (this.window_pane.tab_view.visible_child_name == "browser") {
					this.schedule_pane_update(true);
					return;
				}
				this.schedule_pane_update(false);
			});
			this.chat_widget.chat_bar.tool_button_box.visible = false;
			this.chat_widget.chat_bar.end_box.visible = true;
			this.editor_picker.visible = this.history_manager.get_active_agent().has_editor;
			if (this.history_manager.get_active_agent().has_editor
				&& this.window_pane.intended_pane_visible) {
				this.schedule_pane_update(true);
			}
```

---

## Problem 6 — File field keeps the cursor after a file is chosen

- **🔷** Select a project, then a file. The caret pin stays in the file field.
- **🔷** The keyboard stays up with it.
- **🔷** Choosing a file drops focus. The pin goes away and the keyboard closes.
- **🚫** Leaving the file field focused so another search can start immediately. The next search is a new tap on the field.

### Evidence

- **ℹ️** The file list is `can_focus = false` so the entry keeps focus while the popup is open. `on_selected` clears the entry text and does not move focus.
- **ℹ️** Opening a project then focuses that entry on purpose, so a file can be typed. That focus is still there after the file is chosen.
- **✔️** 2026-10-01 emulator: opening the file field shows a blue ring, a caret, and the keyboard. A list tap there closed the popup without accepting a row, so that run did not show a finished selection.
- **✔️** 2026-10-01 phone: a finished selection left the caret in the file field. About showed `0.20260930` because that string was taken from the previous commit when the Android build was configured. The package itself was updated at 09:59.
- **ℹ️** The first focus clear ran in a normal idle. The click then put focus back on the entry, because the list cannot take focus.

### Current focus

- ℹ️ Click and Enter accept a row the same way.
- ℹ️ `SearchableDropdown.list` is `can_focus = false`. The row click does not move focus.
- ℹ️ `list.activate`, and Enter in `on_key_pressed`, call `set_popup_visible(false)` then `on_selected`.
- ℹ️ Showing a popup calls `entry.grab_focus()` when that entry does not already have focus.

Project:

- ℹ️ `ProjectDropdown.on_selected` emits `project_selected`.
- ℹ️ It clears the project entry text and sets the placeholder to the project name.
- ℹ️ It does not move focus.
- ℹ️ `SourceView.on_project_selected` opens the project.
- ℹ️ When that finishes, an idle calls `file_dropdown.grab_focus()`.
- ℹ️ That is `entry.grab_focus()` on the file field.
- ℹ️ After a project is chosen, focus is the file field.

File:

- ℹ️ The file field already has that focus, or the focus from a tap on it.
- ℹ️ The list cannot take focus, so the caret stays in the file entry while the list is open.
- ℹ️ `FileDropdown.set_popup_visible(false)` clears the entry text.
- ℹ️ `on_selected` emits `file_selected`, clears the text again, and sets the placeholder to the file name.
- ℹ️ Neither step moves focus.
- ℹ️ `SourceView.on_file_selected` does not grab or drop focus.
- ℹ️ On Android, `open_file` makes the source view unfocusable.
- ℹ️ It calls `set_focus(null)` only when the source view itself has focus.
- ℹ️ The file entry still has focus, so the caret and the keyboard stay there.

### Rejected

- 🚫 A late idle that clears focus inside `SearchableDropdown`. It runs after `on_project_selected` has focused the file field, and takes that focus away.

### Next

- 🔷 The list stays `can_focus = false`. A row click must not move focus before the row is chosen.
- 🔷 Click and Enter call `grab_focus()` while the popup is still open. That focuses the dropdown itself, so the entry loses the caret.
- 🔷 With the popup closed, `grab_focus()` still focuses the entry. Choosing a project can still hand focus to the file field.
- 🚫 Letting the row take focus. The click blurred the entry with focus already null, the list closed, and the file was not chosen.
- ✔️ 2026-10-01 emulator: chose `.gitattributes`. Log: `accept focus=OLLMcoderFileDropdown took=true`, then `file read` of that file. No `entry focus`. The keyboard was gone and the file field had no caret. Same package installed on the phone at 22:50.

