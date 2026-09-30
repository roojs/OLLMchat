# Android — source view on the phone

**Status:** ⏳ open — problems 1–5 are in the tree. Not confirmed on a device.

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

