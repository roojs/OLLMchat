# 8.2.8.12 — DONE — Android editor chrome and bar placement

**Status:** **DONE** ✔️ — Phases 1–3 in tree

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](../RPC-8.2.8-filesd-connections-ui.md) Phase 14

**Split from:** [`RPC-8.2.8.11-DONE-android-startup-history-bars.md`](RPC-8.2.8.11-DONE-android-startup-history-bars.md) Phases 4–6. That plan is closed. Phase 1 here was Phase 4 there. Phase 2 here was Phase 5 there. Phase 3 here was Phase 6 there.

**Depends on:**

- [`RPC-8.2.8.11`](RPC-8.2.8.11-DONE-android-startup-history-bars.md) — phone buttons for browser, text editor, and chat. Tablet chat button is in the bar with `visible` false. A click activates the page. The active button is highlighted.
- [`RPC-8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md) — tablet chat stays the left column. `schedule_pane_update` shows or hides the right column.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`. Code fences after each phase is agreed, or when the existing bullets are enough to apply.

---

## Purpose

- **🔷** Editor chrome, where the tablet buttons sit, and moving the pickers to the right.
- **🔷** Desktop follows the tablet bar while a coding-edit agent is the session. Browser and code are page buttons. The right pane stays open.
- **🔷** Each phase below is the whole design for that slice. Read that phase on its own.
- **ℹ️** Startup hello, history when Agent Pi is off, and the phone pickers are [`8.2.8.11`](RPC-8.2.8.11-DONE-android-startup-history-bars.md).
- **ℹ️** Still one desktop environment. Home, office, and an online proxy host are [`8.2.8`](../RPC-8.2.8-filesd-connections-ui.md) Phase 13.
- **ℹ️** Remote `bash` is [`8.2.8.10`](../RPC-8.2.8.10-URGENT-android-remote-bash.md). Not this plan.

---

## Phase 1 — Editor chrome (`✔️`)

When the text editor is the visible page, the column is four bands, top to bottom.

- **🔷** `✔️` The normal OLLMchat header stays on top.
- **🔷** `✔️` Under that, a second bar: project dropdown and file dropdown. Those already exist inside the coder (`ProjectDropdown`, `FileDropdown`).
- **🔷** `✔️` Then the text area.
- **🔷** `✔️` When review is active, the review bar sits at the bottom of the text area. Not in this slice unless review is already showing there on desktop.
- **ℹ️** Desktop review footer is `liboccoder/Diff/ReviewBar.vala`. The phone reuses that band. It does not invent a second review widget.

**No hunk.** The four bands are already the mounted editor. Do not add a second dropdown bar or a second review widget.

- **ℹ️** Band 1. `ollmapp/android/OllmchatWindow.vala` keeps `Adw.HeaderBar` on `toolbar_view`. Project and file controls stay out of that bar.
- **ℹ️** Band 2. `liboccoder/SourceView.vala` builds `header_bar` and appends `ProjectDropdown`, then `FileDropdown`. Save and `Approvals` stay on that same bar. This phase does not move them.
- **ℹ️** Band 3. That constructor appends the scrolled `GtkSource.View` under `header_bar`.
- **ℹ️** Band 4. It then appends `OLLMcoder.Diff.ReviewBar`. `ReviewBar` shows itself when the pending queue is non-empty. Same footer as desktop.
- **ℹ️** `liboccoder/AgentPi/Factory.vala` `activate` puts that `SourceView` on `tab_view()` (`pane_stack`) and calls `schedule_pane_update(true)`. Phone and tablet both show this column. The chat composer under the phone pane is the picker bar from [`8.2.8.11`](RPC-8.2.8.11-DONE-android-startup-history-bars.md). It is not a fifth editor band.

---

## Phase 2 — Tablet bar (`✔️`)

- **ℹ️** Tablet `schedule_pane_update` only shows or hides the right column. Chat stays on the left ([`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md)).
- **🔷** `✔️` The same browser and text-editor buttons from [`8.2.8.11`](RPC-8.2.8.11-DONE-android-startup-history-bars.md) Phase 3. The chat button stays in the bar, invisible. A click activates that page and highlights it.
- **🔷** `✔️` Those two buttons sit on the right of the left column's bottom bar, not on its left edge.
- **🔷** `✔️` Selecting Agent Pi still fills the right column with the editor. The buttons choose browser vs code in that column.
- **ℹ️** Moving the model selector fully left, on phone and tablet together, is Phase 3. This phase only moves browser and code to the right of that left-column bar.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

Phone and tablet pack browser, code, and chat into `end_box`. Chat uses `visible = !this.is_tablet`. `tool_button_box` is hidden, so the model dropdown is the left edge. That is the Phase 3 bar. Phase 3 below adds the desktop coding-edit case on the same strip. Selecting Agent Pi still calls `factory.activate`. Those click handlers stay.

### 1. `libollmchatgtk/ChatBar.vala` — `end_box`

**Why:** The left column's bottom bar is `ChatBar`. `tool_button_box` is the leftmost child. Browser and code need a strip after the expanding spacer and before send. The model dropdown stays between `tool_button_box` and that spacer.

**Where:** Property next to `tool_button_box`. Create and append the box in `ChatBar()`, after the spacer `append` and before `action_button`.

**Depends on:** none.

The plan names `end_box`. Android shows it. Desktop shows it only while a coding-edit agent is the session.

#### Add — property after `tool_button_box`

```vala
		/**
		 * Right-hand strip, after the spacer and before send.
		 *
		 * Phone and tablet append browser, code, and chat.
		 * Desktop shows this strip for a coding-edit agent.
		 */
		public Gtk.Box end_box { get; private set; }
```

#### Add — after `this.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });`

Same construction as `tool_button_box`. `visible` is set after `append`, same as `action_button`.

```vala
			this.end_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
				hexpand = false,
				vexpand = false,
			};
			this.append(this.end_box);
			this.end_box.visible = false;
```

### 2. `ollmapp/android/OllmchatWindow.vala` — pack browser and code

**Why:** Browser, code, and chat sit in `end_box`. Hiding chat on a tablet is `visible = !this.is_tablet`. Hiding `tool_button_box` puts the model dropdown fully left.

**Where:** `initialize_client`, the three `tool_button_box.append` lines after the pickers are created.

**Depends on:** §1.

#### Remove

```vala
			this.chat_picker.visible = !this.is_tablet;
			this.chat_picker.add_css_class("picker-on");
			this.chat_widget.chat_bar.tool_button_box.append(this.browser_picker);
			this.chat_widget.chat_bar.tool_button_box.append(this.editor_picker);
			this.chat_widget.chat_bar.tool_button_box.append(this.chat_picker);
```

#### Replace with

No `is_tablet` branch. Chat uses the same `visible` assignment as today.

```vala
			this.chat_picker.visible = !this.is_tablet;
			this.chat_picker.add_css_class("picker-on");
			this.chat_widget.chat_bar.end_box.append(this.browser_picker);
			this.chat_widget.chat_bar.end_box.append(this.editor_picker);
			this.chat_widget.chat_bar.end_box.append(this.chat_picker);
			this.chat_widget.chat_bar.end_box.visible = true;
			this.chat_widget.chat_bar.tool_button_box.visible = false;
```

---

## Phase 3 — Pickers on the right, desktop follows tablet (`✔️`)

- **🔷** `✔️` Later, the same bar on phone and tablet: pickers sit on the right, and the model selector moves fully left.
  - Phone: three pickers (browser, text editor, chat).
  - Tablet: browser and code show. The chat picker is in the bar with `visible` false. Chat is the left column.
- **🔷** `✔️` Desktop uses that same tablet bar while `Factory.has_editor` is true. The chat bar stays visible. Browser is always available: the toggle strip, or the browser and code buttons.
  - Chat stays the left column. There is no chat picker.
  - Browser and text editor are `Gtk.Button`. A click activates that page in the right pane and highlights it.
  - Those two buttons sit on the right. The model selector moves fully left.
  - The right pane stays open. Browser shows the browser child. Code shows `{agent name}-widget`.
- **🔷** `✔️` While `has_editor` is false, desktop keeps today's browser `Gtk.ToggleButton`. That button still shows or hides the browser pane.
- **ℹ️** Today's bug is `ollmapp/Window.vala` `tool_toggle`: turning the browser off always calls `schedule_pane_update(false)`. The button is `ChatBar.add_tool_toggle`. Only the browser tool implements `UiWidgets`.
- **ℹ️** `deactivate` already hides the pane when you leave the agent. Switching off a coding-edit agent returns the bar to the browser toggle.

Phone and tablet packing is the Phase 2 replace: all three pickers in `end_box`, `tool_button_box.visible = false`. No second Android hunk.

Edits are **Remove** / **Replace with** / **Add** from the tree after Phase 2. Verify surrounding context before applying.

### 1. `libollmchat/Agent/Factory.vala` — `has_editor`

**Why:** The desktop bar follows the agent type. The three editor factories set the flag. Chatter and the others stay false. No name list in the window.

**Where:** Property after `long_title`.

**Depends on:** none.

#### Add — after `long_title`

```vala
		/**
		 * True when this agent mounts the source editor.
		 *
		 * The desktop bar then shows browser and code on the
		 * right. The chat bar itself stays visible.
		 */
		public virtual bool has_editor { get; protected set; default = false; }
```

### 2. Editor factories — `has_editor` true

**Why:** Coding Assistant, Agent Pi, and Skills Agent mount `SourceView`.

**Where:** Next to each factory's `name` property.

**Depends on:** §1.

#### Add — `liboccoder/AgentFactory.vala`, after `name`

```vala
		public override bool has_editor { get; protected set; default = true; }
```

#### Add — `liboccoder/AgentPi/Factory.vala`, after `name`

```vala
		public override bool has_editor { get; protected set; default = true; }
```

#### Add — `liboccoder/Skill/Factory.vala`, after `name`

```vala
		public override bool has_editor { get; protected set; default = true; }
```

### 3. `ollmapp/Window.vala` — picker fields

**Why:** Desktop needs the browser and code buttons. Chat is the left column, so there is no chat picker. The browser `Gtk.ToggleButton` stays in `tool_button_box` for the other agents.

**Where:** Fields next to `tool_error_banner`.

**Depends on:** Phase 2 §1.

#### Add — after `private Adw.Banner tool_error_banner;`

```vala
		private Gtk.Button browser_picker;
		private Gtk.Button editor_picker;
```

### 4. `ollmapp/Window.vala` — `schedule_pane_update`

**Why:** A click highlights the active page. Chat is the left column, so a hidden pane clears both highlights.

**Where:** `schedule_pane_update`, the whole method.

**Depends on:** §3.

#### Remove

```vala
		public void schedule_pane_update(bool visible)
		{
			this.window_pane.schedule_pane_update(visible);
		}
```

#### Replace with

```vala
		public void schedule_pane_update(bool visible)
		{
			this.window_pane.schedule_pane_update(visible);
			this.browser_picker.remove_css_class("picker-on");
			this.editor_picker.remove_css_class("picker-on");
			if (!visible) {
				return;
			}
			if (this.window_pane.tab_view.visible_child_name == "browser") {
				this.browser_picker.add_css_class("picker-on");
				return;
			}
			this.editor_picker.add_css_class("picker-on");
		}
```

### 5. `ollmapp/Window.vala` — pack the strip and keep the toggle

**Why:** Coding Assistant, Agent Pi, and Skills Agent use `end_box`. Any other agent keeps the browser toggle in `tool_button_box`, and that toggle still shows or hides the pane. `show_view` during a coding-edit session opens the browser page instead of the toggle. Turning the hidden toggle off does not collapse the editor.

**Where:** `initialize_client`, the tool `foreach` through `connect_agent_factory_signals()`.

**Depends on:** §1, §2, §3, §4.

#### Remove

```vala
			foreach (var tool in this.history_manager.tools.values) {
				var ui = tool as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					continue;
				}
				var widget_id = tool.name;
				this.chat_widget.chat_bar.add_tool_toggle(
					widget_id, ui.icon_name, ui.tooltip_text);
				ui.show_view.connect(() => {
					this.chat_widget.chat_bar.toggle_active_tool(widget_id, true);
				});
			}
			this.chat_widget.chat_bar.tool_toggle.connect((tool_name, active) => {
				if (!this.history_manager.tools.has_key(tool_name)) {
					return;
				}
				var ui = this.history_manager.tools.get(tool_name) as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					return;
				}
				var view = (Gtk.Widget) ui.view_widget;
				if (!active) {
					this.window_pane.schedule_pane_update(false);
					return;
				}
				if (this.window_pane.tab_view.get_child_by_name(tool_name) == null) {
					this.window_pane.tab_view.add_named(view, tool_name);
				}
				view.visible = true;
				this.window_pane.tab_view.set_visible_child_name(tool_name);
				this.window_pane.schedule_pane_update(true);
			});
			
			// Agent UI: factories receive this window as ChatDesktopInterface (§3b)
			this.connect_agent_factory_signals();
```

#### Replace with

Buttons are created the same way as Android, one property per line. `end_box` stays hidden until `has_editor` is true. The chat bar stays visible. The check after `connect` covers an agent that activated before this handler.

```vala
			this.browser_picker = new Gtk.Button();
			this.browser_picker.icon_name = "web-browser-symbolic";
			this.browser_picker.tooltip_text = "Browser";
			this.editor_picker = new Gtk.Button();
			this.editor_picker.icon_name = "document-edit-symbolic";
			this.editor_picker.tooltip_text = "Text editor";
			this.chat_widget.chat_bar.end_box.append(this.browser_picker);
			this.chat_widget.chat_bar.end_box.append(this.editor_picker);
			this.browser_picker.clicked.connect(() => {
				var ui = this.history_manager.tools.get("browser") as OLLMchat.Tool.UiWidgets;
				var view = (Gtk.Widget) ui.view_widget;
				if (this.window_pane.tab_view.get_child_by_name("browser") == null) {
					this.window_pane.tab_view.add_named(view, "browser");
				}
				this.window_pane.tab_view.set_visible_child_name("browser");
				this.schedule_pane_update(true);
			});
			this.editor_picker.clicked.connect(() => {
				var widget_id = this.history_manager.session.agent_name + "-widget";
				this.window_pane.tab_view.set_visible_child_name(widget_id);
				this.schedule_pane_update(true);
			});
			foreach (var tool in this.history_manager.tools.values) {
				var ui = tool as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					continue;
				}
				var widget_id = tool.name;
				this.chat_widget.chat_bar.add_tool_toggle(
					widget_id, ui.icon_name, ui.tooltip_text);
				ui.show_view.connect(() => {
					if (this.chat_widget.chat_bar.end_box.visible) {
						var view = (Gtk.Widget) ui.view_widget;
						if (this.window_pane.tab_view.get_child_by_name(widget_id) == null) {
							this.window_pane.tab_view.add_named(view, widget_id);
						}
						this.window_pane.tab_view.set_visible_child_name(widget_id);
						this.schedule_pane_update(true);
						return;
					}
					this.chat_widget.chat_bar.toggle_active_tool(widget_id, true);
				});
			}
			this.chat_widget.chat_bar.tool_toggle.connect((tool_name, active) => {
				if (!this.history_manager.tools.has_key(tool_name)) {
					return;
				}
				var ui = this.history_manager.tools.get(tool_name) as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					return;
				}
				var view = (Gtk.Widget) ui.view_widget;
				if (!active) {
					if (this.chat_widget.chat_bar.end_box.visible) {
						return;
					}
					this.window_pane.schedule_pane_update(false);
					return;
				}
				if (this.window_pane.tab_view.get_child_by_name(tool_name) == null) {
					this.window_pane.tab_view.add_named(view, tool_name);
				}
				view.visible = true;
				this.window_pane.tab_view.set_visible_child_name(tool_name);
				this.window_pane.schedule_pane_update(true);
			});

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

			// Agent UI: factories receive this window as ChatDesktopInterface (§3b)
			this.connect_agent_factory_signals();
```

---

## Suggested order

1. **✔️** Phase 1 — editor chrome already in tree (header, project/file dropdowns, text, review bar). No hunk.
2. **✔️** Phase 2 — `end_box`, phone and tablet pickers on the right, model fully left. Applied with Phase 3.
3. **✔️** Phase 3 — desktop coding-edit agents use that same bar. Applied with Phase 2.

---

## LLM notes

- **🚫** Code Assistant and Skill Runner on Android.
- **🚫** Changing Linux Agent Pi registration.
- **🚫** A left-rail editor toggle.
- **🚫** `Gtk.ToggleButton` for browser, editor, or chat on Android, and on desktop while a coding-edit agent is the session. A click activates the page. The active one is highlighted. The desktop browser toggle remains only when the session agent does not mount an editor.
- **🚫** A desktop chat picker. Chat is the left column.
- **🚫** A phone split (editor over a short chat strip) and a draggable sash (`Gtk.Paned`).
- **🚫** A spinner on the chat picker. Running is the fog frames, one wave at a time. Idle is a speech bubble.
- **🚫** More than one desktop environment. That is parent Phase 13.
- **🚫** Registering in-process `Bash` on Android. That is [`8.2.8.10`](../RPC-8.2.8.10-URGENT-android-remote-bash.md).
- **🚫** Reopening [`8.2.8.9`](RPC-8.2.8.9-DONE-android-agent-pi.md) or [`8.2.8.11`](RPC-8.2.8.11-DONE-android-startup-history-bars.md) for these hunks.
