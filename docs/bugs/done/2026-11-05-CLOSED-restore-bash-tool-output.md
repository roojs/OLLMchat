# Tool output and code blocks are two incomplete widgets

**Status:** 🚫 CLOSED 2026-11-08. The accepted hunks are in the tree. The missing row is [`2026-11-08-FIXED-bash-frame-not-in-chat.md`](2026-11-08-FIXED-bash-frame-not-in-chat.md).

## Problem

- 🔷 Reopen a session that ran `ls`.
  - 🔷 The listing is a collapsed frame.
  - 🔷 The title is Execution results.
- 🔷 While the command was running, that listing was the black tool pane.
  - 🔷 The command is in the header.
  - 🔷 Long lines scroll sideways.
- 🔷 Those are two widgets for one job.
  - 🔷 Each is missing what the other has.
  - 🔷 Neither can be both the live view and the restored view.
- 🔷 Building the live pane again at restore time is not a design.
  - 🔷 That leaves the split in place.

## The two widgets

- ℹ️ `OLLMchatGtk.ToolOutput` is the live shell pane.
  - ℹ️ `ChatWidget` creates it from `client.run_tool.start`.
  - ℹ️ It appends `client.run_tool.output`.
  - ℹ️ `close()` runs on `client.run_tool.end`.
- ℹ️ The pane has:
  - ℹ️ A command header.
  - ℹ️ A status line.
  - ℹ️ Stop.
  - ℹ️ Collapse.
  - ℹ️ A 2000-line cap.
  - ℹ️ Stick-to-bottom.
- ℹ️ The body is:
  - ℹ️ Black.
  - ℹ️ A fixed face.
  - ℹ️ No wrap.
  - ℹ️ Sideways scroll.
- ℹ️ The pane is not a markdown row.
  - ℹ️ No copy button.
  - ℹ️ No syntax language.
  - ℹ️ `add_widget_frame` does `appender`, so the live frame gets a `by_id` slot.
  - ℹ️ That id is never written onto the `tool` message.
  - ℹ️ `ChatView.clear()` drops the widget. Reopen never sees it.
- ℹ️ It is built only from those three notifications.
  - ℹ️ A saved session does not replay them.
  - ℹ️ The pane cannot build itself from a stored `tool` message.
- ℹ️ `MarkdownGtk.RenderSourceView` is the fenced block.
  - ℹ️ Assistant markdown uses it.
  - ℹ️ User quotes use it.
  - ℹ️ The restore path uses it.
- ℹ️ A fence can take text while it is parsed (`add_code_text`).
  - ℹ️ That includes an assistant message that is still streaming.
- ℹ️ The block has:
  - ℹ️ A language.
  - ℹ️ A frame theme.
  - ℹ️ Copy.
  - ℹ️ Height expand.
  - ℹ️ A row id.
- ℹ️ Wrap depends on the type.
  - ℹ️ Markdown wraps.
  - ℹ️ `raw` wraps.
  - ℹ️ Vala stays one line and scrolls sideways.
  - ℹ️ Python stays one line and scrolls sideways.
  - ℹ️ Other code does the same.
- ℹ️ The fence has no shell chrome.
  - ℹ️ No command header.
  - ℹ️ No Stop.
  - ℹ️ No status line.
  - ℹ️ No line cap.
  - ℹ️ No black shell face.
- ℹ️ Restore does not feed the fence the live notifications.
  - ℹ️ `ChatWidget.on_message_created` wraps the saved tail.
  - ℹ️ The fence header is `text.oc-frame-success.collapsed Execution results`.

## How a listing gets on screen

### Live — three notifications, one `ToolOutput`

- ℹ️ `liboctools/Bash/Request.vala` emits. `ChatWidget` builds. The command is `message`. The status line is `action`.

```vala
this.agent.notification(new OLLMrpc.Notification() {
	method = "client.run_tool.start",
	message = this.command.strip(),
	action = run_status,
});
```

- ℹ️ Chunks are the 500 ms flush, and the leftover in `finally`. `id` is `request_id`. `ChatWidget` ignores `id`.

```vala
this.agent.notification(new OLLMrpc.Notification() {
	method = "client.run_tool.output",
	message = string.joinv("\n", this.pending_output) + "\n",
	id = this.request_id,
});
```

- ℹ️ End runs in that same `finally`, unless the job detached.

```vala
if (!this.detached) {
	this.agent.notification(new OLLMrpc.Notification() {
		method = "client.run_tool.end",
		message = this.command.strip(),
	});
}
```

- ℹ️ One pointer. The frame goes into the same box as the markdown rows.

```vala
case "client.run_tool.start":
	this.current_output = new ToolOutput(
		this.manager, notif.message, notif.action);
	this.chat_view.add_widget_frame(this.current_output);
	return;

case "client.run_tool.output":
	this.current_output.output(notif.message);
	return;

case "client.run_tool.end":
	this.current_output.close();
	this.current_output = null;
	return;
```

```vala
public void add_widget_frame(Gtk.Frame frame)
{
	this.widgets.add(frame);
	this.renderer.box.appender(frame);
}
```

```vala
public void appender(Gtk.Widget child)
{
	base.append(child);
	this.by_id.add(child);
}
```

- ℹ️ The constructor is the shell chrome. Body starts as the command plus a newline.

```vala
public ToolOutput(OLLMchat.History.Manager manager, string command, string action)
{
	// header = bold command, status = action, Stop, collapse
	this.view = new Gtk.TextView() {
		editable = false,
		wrap_mode = Gtk.WrapMode.NONE,
		monospace = true,
		css_classes = { "tool-output" }
	};
	this.view.buffer.text = command + "\n";
	this.scroll = new Gtk.ScrolledWindow() {
		min_content_height = 200,
		max_content_height = 480,
		hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
		css_classes = { "tool-output" }
	};
}
```

- ℹ️ While it runs, `output` appends, drops past 2000 lines, and sticks to the bottom only if the user is already there. `close` hides Stop and collapses. The frame stays in the box. The pointer does not.

```vala
public void output(string chunk)
{
	var stick = adj.value >= adj.upper - adj.page_size - 8.0;
	this.view.buffer.insert(ref end, chunk, -1);
	// delete from the start while line count > 2000
	if (stick) {
		adj.value = adj.upper - adj.page_size;
	}
}

public void close()
{
	this.stop.visible = false;
	this.body.reveal_child = false;
}
```

- ℹ️ What is saved is not that buffer. `execute_tools` stores the tail the model saw. Live `on_message_created` hits `is_ui_visible == false` and returns. The command stays on the assistant call, `arguments.command`.

```vala
var tool_reply = new Message.tool_reply(
	tool_call.id,
	tool_call.function.name,
	result);
reply_messages.add(tool_reply);
```

```vala
public Message.tool_reply(string tool_call_id, string name, string content)
{
	this.role = "tool";
	this.tool_call_id = tool_call_id;
	this.name = name;
	this.content = content;
}
```

### Restore — that `tool` row becomes a fence

- ℹ️ `switch_to_session` sets `restoring_session`, calls `clear_chat()` (the live pane is gone), then replays messages. Bash and `run_command` are rewritten as an assistant fence before the normal role switch.

```vala
if (this.restoring_session && m.role == "tool" &&
		(m.name == "bash" || m.name == "run_command")) {
	var ui_msg = new OLLMchat.Message("assistant",
		OLLMchat.Message.fenced(
			"text.oc-frame-success.collapsed Execution results",
			m.content),
		m.thinking);
	ui_msg.idx_last = this.chat_view.append_complete_assistant_message(ui_msg, session);
	ui_msg.idx_first = this.chat_view.render_box.first_id;
	m.idx_first = ui_msg.idx_first;
	m.idx_last = ui_msg.idx_last;
	return;
}
```

- ℹ️ `fenced` is a string. The header is the info string. The body is `m.content`.

```vala
return fence + header + "\n" + out_body + "\n" + fence + "\n";
```

````text
```text.oc-frame-success.collapsed Execution results
<saved tail>
```
````

- ℹ️ `append_complete_assistant_message` marks a row range, streaming off, and feeds that string to the markdown renderer.

```vala
this.render_box.mark();
this.renderer.is_streaming = false;
this.process_new_chunk_direct(message.content, false);
// ContentState.CONTENT:
this.renderer.add(text);
```

- ℹ️ A fence start constructs `RenderSourceView`. Body text is `on_code_text`.

```vala
this.childview = new RenderSourceView(this, lang, this.is_streaming);
this.source_view_handlers.add(this.childview);

public override void on_code_text(string text)
{
	this.childview.add_code_text(text);
}
```

- ℹ️ `language_id` is `text.oc-frame-success.collapsed Execution results`. First token splits on `.` into language `text` and classes `oc-frame-success`, `collapsed`. The title is `Execution results`. Collapsed and not streaming: the source view is not built. The frame is still appended.

```vala
if (is_streaming || (!has_collapsed_style && !this.collapse_on_done)) {
	this.body_widgets(is_streaming || !this.collapse_on_done);
	this.body_revealer.reveal_child = !has_collapsed_style;
}
frame.add_css_class("oc-frame");
this.renderer.box.appender(frame);
```

- ℹ️ Until the body exists, chunks only accumulate. Expand is the first `GtkSource.View`.

```vala
public void add_code_text(string text)
{
	if (!this.has_content) {
		this.code_text += text;
		return;
	}
	this.source_buffer.insert(ref end_iter, text, -1);
}
```

```vala
if (!this.has_widgets) {
	this.body_widgets(true);
	this.fill_widgets();
}
```

- ℹ️ `body_widgets` starts at `WrapMode.NONE` and a horizontal bar. `raw` switches to `WORD` and hides that bar. `markdown` paints the nested renderer, which wraps. `text`, Vala, and Python stay one line.

```vala
this.source_view = new GtkSource.View() {
	wrap_mode = Gtk.WrapMode.NONE,
	css_classes = { "code-editor" }
};
this.source_scrolled.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
if (this.code_language == "raw") {
	this.source_view.wrap_mode = Gtk.WrapMode.WORD;
	this.source_scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
}
```

- ℹ️ A streaming assistant fence is the same class with `is_streaming` true, so `body_widgets` runs in the constructor and `add_code_text` inserts as tokens arrive. Bash restore does not take that path.

### Same box, two objects

- ℹ️ Both end as children of `RenderBox` via `appender`.
- ℹ️ One is a `Gtk.Frame` built from the three notifications and dropped in `clear()`.
- ℹ️ The other is a `Gtk.Frame` built by parsing a fence string that exists only at restore.
- ℹ️ Neither object is asked to do both.

## Why restore looks wrong

- ℹ️ The saved row is still a `tool` message.
  - ℹ️ `name` is `bash` or `run_command`.
  - ℹ️ `content` is the tail.
  - ℹ️ `tool_call_id` points at the assistant call.
  - ℹ️ The command is `arguments.command` on that call.
  - ℹ️ `is_ui_visible` is false.
- ℹ️ The restore branch exists because the live pane cannot be rebuilt.
  - ℹ️ The fence was the widget that can show a finished block.
  - ℹ️ That choice is [`TOOLS-2.6.5`](../../plans/done/TOOLS-2.6.5-DONE-run-command-timeout-live-spill.md) §4a and §5.
- ✔️ The listing changes widget when the session is reopened.
  - ✔️ The fence was never the shell pane.
  - ✔️ The shell pane was never a restorable block.

## What one widget has to cover

- 🔷 The same listing in both cases.
  - 🔷 Chunks still arriving.
  - 🔷 The session opened again.
- 🔷 Shell output stays one line and scrolls sideways.
  - 🔷 The command stays in the header.
- 🔷 Markdown and raw text keep wrapping.
- 🔷 Vala and Python fences keep scrolling sideways.
  - 🔷 Those fences are not this widget.
- ⏳ 🔷 How a finished run is shown is part of the design.
  - ⏳ 🔷 Open or collapsed.
  - ⏳ 🔷 What the status line says.
  - ⏳ 🔷 Not settled here.
- 🚫 A restore-only constructor call on `ToolOutput`.
  - 🚫 That is not the fix.
- 🚫 Keep painting Execution results.
  - 🚫 And treat the live pane as a separate special case.

## Plan

- ℹ️ The design and the applied hunks are in this file.
- ℹ️ Stop still calls every `active_tools` entry. Follow-up: [`2026-11-06-stop-one-tool.md`](../2026-11-06-stop-one-tool.md).
- 🔷 Two classes. `on_code_block` constructs `RenderSourceView` or the shell class.
- 🔷 A type registry was a plugin example. `ToolOutput`'s only chat dependency is `History.Manager`, and only for Stop.
- 🚫 The registry. Withdrawn.

## Register a type, then `new` it — withdrawn

- 🔷 `Render` grows a registration method. The argument is an object type.
- 🔷 The map key is the fence token, the first piece of the info string, before `.oc-frame-*`.
- 🔷 No registration for a token means `new RenderSourceView`. Vala, Python, markdown, `raw`, and `text` stay on that default.
- 🔷 Chat registers the shell type against the shell token. A fence with that token does `new` of the registered type.
- ℹ️ Today there is no such method. `on_code_block` always runs `new RenderSourceView(this, lang, this.is_streaming)`.

```vala
private Gee.HashMap<string, GLib.Type> code_block_types;

public void register_code_block(string token, GLib.Type type)
{
	this.code_block_types[token] = type;
}
```

```vala
// libollmchatgtk/ChatView.vala, next to `new MarkdownGtk.Render`
this.renderer.register_code_block("bash", typeof(OLLMchatGtk.ToolOutput));
```

```vala
// fence start, inside Render.on_code_block
var token = lang.split(".")[0];
var type = typeof(MarkdownGtk.RenderSourceView);
if (this.code_block_types.has_key(token)) {
	type = this.code_block_types[token];
}
this.childview = GLib.Object.new(type,
	"renderer", this,
	"language-id", lang,
	"is-streaming", this.is_streaming);
this.source_view_handlers.add(this.childview);
```

- ℹ️ The code handler that exists today is `MarkdownGtk.RenderSourceView`. Its only `new` is `Render.on_code_block` in `libocmarkdowngtk/Render.vala`. The class body is `libocmarkdowngtk/RenderSourceView.vala`.
- ℹ️ The shell pane that exists today is `OLLMchatGtk.ToolOutput` in `libollmchatgtk/ToolOutput.vala`. Its only `new` is the `client.run_tool.start` branch in `libollmchatgtk/ChatWidget.vala`.
- 🔷 The registered type is `ToolOutput`. No third class.
- ℹ️ `libocmarkdowngtk` does not depend on `libollmchatgtk`, so `Render` cannot name `ToolOutput`. `ChatView` owns the renderer (`renderer` is private) and both classes live in `libollmchatgtk`, so the `typeof` call sits there.
- ℹ️ `childview` is a `RenderSourceView`. `ToolOutput` subclasses that class so the `new` result is the shell pane with the source-view frame behaviour.
- 🚫 A new `ShellBlock` class. That name was only a sketch.
- 🚫 Registering `ToolOutput` on `text`. That token is file reads and the other preformatted frames.
- ⏳ 🔷 The shell token is still open.
- ⏳ 🔷 How a finished run is shown is still open.

### Files

- 🔷 `libocmarkdowngtk/Render.vala` — the map, `register_code_block`, and the lookup inside the existing `on_code_block`.
- 🔷 `libocmarkdowngtk/RenderSourceView.vala` — construct properties so `GLib.Object.new` can build this class and a subclass. The fence behaviour stays here.
- 🔷 `libollmchatgtk/ToolOutput.vala` — subclass `RenderSourceView`. This is the type chat registers.
- 🔷 `libollmchatgtk/ChatView.vala` — the `register_code_block` call where the renderer is created.
- 🔷 `libollmchatgtk/ChatWidget.vala` — the live `new ToolOutput` / `add_widget_frame` branch. That construction moves to the fence `new`.
- 🚫 A new `.vala` file. `meson.build` file lists stay as they are.

## Proposed code

- 💩 These hunks use the signal, connected once when the `Render` is created. The interface is the other shape. It is not in the fences.
- 💩 Fence token `bash`. `run_command` rows use that same token at restore.
- 💩 The shell class is `MarkdownGtk.RenderToolOutput`.
- 💩 End hides Stop and collapses, which is today's `close()`. A collapsed info string starts collapsed. Restore has no status line.
- 🔷 Edits are **Remove** / **Replace with** / **Add**. Verify the surrounding lines before applying.

### 1. `libocmarkdowngtk/RenderToolOutput.vala` — shell frame

**Why:** The listing is a fence frame. It does not store `History.Manager`.

**Where:** new file next to `RenderSourceView.vala`.

**Depends on:** §2, which declares `Render.stop_clicked`.

#### Add — new file

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace MarkdownGtk
{
	/**
	 * Shell listing for a bash fence. The command is the title.
	 *
	 * Stop emits {@link Render.stop_clicked}. Chat connects that
	 * signal when the renderer is created.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var frame = new RenderToolOutput(renderer,
	 *     "bash.oc-frame-info ls", true);
	 * frame.output("a.txt\n");
	 * }}}
	 */
	public class RenderToolOutput : Gtk.Frame
	{
		/**
		 * Renderer that owns {@link Render.stop_clicked}.
		 */
		public Render renderer { get; construct; }
		/**
		 * Fence info string. The title after the classes is the command.
		 */
		public string language_id { get; construct; }
		/**
		 * True while chunks are still arriving. Shows Stop.
		 */
		public bool is_streaming { get; construct; }
		/**
		 * Status line. Live sets this from the start notification.
		 * ''Running command as root (sudo)'' adds the ''root'' class.
		 */
		public string status { get; set; default = ""; }

		private Gtk.Button stop;
		private Gtk.Button collapse;
		private Gtk.Revealer body;
		private Gtk.ScrolledWindow scroll;
		private Gtk.TextView view;
		private Gtk.Label status_label;

		/**
		 * @param renderer parent renderer
		 * @param language_id fence info string
		 * @param is_streaming true while output is still arriving
		 */
		public RenderToolOutput(Render renderer, string language_id, bool is_streaming)
		{
			Object(renderer: renderer, language_id: language_id, is_streaming: is_streaming);
		}

		construct
		{
			var info = this.language_id.strip();
			var tokens = info.split(" ", 2);
			var language = tokens.length > 0 ? tokens[0] : "";
			var command = tokens.length > 1 ? tokens[1].strip() : "";
			var lang_parts = language.split(".");
			var frame_theme_classes = lang_parts.length > 1 ?
				lang_parts[1:lang_parts.length] : new string[0];
			var collapsed = "collapsed" in frame_theme_classes;
			string[] frame_classes = { "tool-frame", "oc-frame" };
			foreach (var c in frame_theme_classes) {
				if (c == "collapsed") {
					continue;
				}
				frame_classes += c;
			}
			this.css_classes = frame_classes;
			var header = new Gtk.Label("") {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				hexpand = true,
				css_classes = { "command-preview" },
				tooltip_text = command,
				label = "<b>" + GLib.Markup.escape_text(command) + "</b>"
			};
			this.status_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				wrap = true
			};
			this.notify["status"].connect(() => {
				this.status_label.label = this.status;
				if (this.status == "Running command as root (sudo)") {
					this.add_css_class("root");
				}
			});
			this.body = new Gtk.Revealer() {
				reveal_child = !collapsed,
				hexpand = true
			};
			this.collapse = new Gtk.Button() {
				icon_name = collapsed ? "go-next-symbolic" : "go-up-symbolic",
				tooltip_text = collapsed ? "Expand" : "Collapse",
				valign = Gtk.Align.CENTER
			};
			this.collapse.clicked.connect(() => {
				this.body.reveal_child = !this.body.reveal_child;
				this.collapse.icon_name = this.body.reveal_child
					? "go-up-symbolic" : "go-next-symbolic";
				this.collapse.tooltip_text = this.body.reveal_child
					? "Collapse" : "Expand";
			});
			this.stop = new Gtk.Button.with_label("Stop") {
				valign = Gtk.Align.CENTER,
				visible = this.is_streaming,
				css_classes = { "destructive-action" }
			};
			this.stop.clicked.connect(() => {
				this.stop.visible = false;
				this.renderer.stop_clicked();
			});
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				css_classes = { "oc-frame-header" }
			};
			row.append(this.collapse);
			row.append(header);
			row.append(this.stop);
			this.view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.NONE,
				monospace = true,
				hexpand = true,
				css_classes = { "tool-output" }
			};
			this.view.buffer.text = command + "\n";
			this.scroll = new Gtk.ScrolledWindow() {
				min_content_height = 200,
				max_content_height = 480,
				propagate_natural_height = true,
				propagate_natural_width = false,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				hexpand = true,
				vexpand = false,
				margin_top = 4,
				margin_bottom = 4,
				margin_start = 4,
				margin_end = 4,
				css_classes = { "tool-output" }
			};
			this.scroll.set_child(this.view);
			this.body.set_child(this.scroll);
			var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			col.append(row);
			col.append(this.status_label);
			col.append(this.body);
			this.set_child(col);
		}

		/**
		 * Append a chunk. Cap at 2000 lines. Stick to the bottom
		 * only when the view is already there.
		 *
		 * @param chunk text still arriving, or the restored tail
		 */
		public void output(string chunk)
		{
			var adj = this.scroll.get_vadjustment();
			var stick = adj.value >= adj.upper - adj.page_size - 8.0;
			Gtk.TextIter end;
			this.view.buffer.get_end_iter(out end);
			this.view.buffer.insert(ref end, chunk, -1);
			var extra = this.view.buffer.get_line_count() - 2000;
			if (extra > 0) {
				Gtk.TextIter start;
				Gtk.TextIter cut;
				this.view.buffer.get_start_iter(out start);
				this.view.buffer.get_iter_at_line(out cut, extra);
				this.view.buffer.delete(ref start, ref cut);
			}
			if (stick) {
				adj.value = adj.upper - adj.page_size;
			}
		}

		/**
		 * Run finished. Hide Stop and collapse. Leave the frame.
		 */
		public void close()
		{
			this.stop.visible = false;
			this.body.reveal_child = false;
			this.collapse.icon_name = "go-next-symbolic";
			this.collapse.tooltip_text = "Expand";
		}
	}
}
```

### 2. `libocmarkdowngtk/Render.vala` — construct the shell frame

**Why:** `on_code_block` already constructs `RenderSourceView`. A `bash` token constructs `RenderToolOutput` instead. Stop is one signal on the renderer.

**Where:** field next to `childview`, signal next to `start_new_chat_requested`, the end branch and the `new RenderSourceView` lines inside `on_code_block`, `on_code_text`, and `clear`.

**Depends on:** §1.

#### Add — after the `childview` property

The open shell frame. Null after the fence ends. The widget stays in the box.

```vala
		public RenderToolOutput? tool_view { get; set; default = null; }
```

#### Add — after `start_new_chat_requested`

Stop was clicked on the open shell frame.

```vala
		public signal void stop_clicked();
```

##### Part 1 — `on_code_block` end

#### Remove

```vala
			if (!is_start) {
				// Code block ended - delegate to childview
				if (this.childview != null) {
					this.childview.end_code_block();
					// Keep handler in array so it doesn't go out of scope
					// (buttons and other handlers need to remain functional)
					this.childview = null;
				}
```

#### Replace with

```vala
			if (!is_start) {
				if (this.tool_view != null) {
					this.tool_view.close();
					this.tool_view = null;
					return;
				}
				if (this.childview != null) {
					this.childview.end_code_block();
					this.childview = null;
				}
```

##### Part 2 — `on_code_block` start

#### Remove

```vala
			this.childview = new RenderSourceView(this, lang, this.is_streaming);

			// Keep handler in array so it doesn't go out of scope
			this.source_view_handlers.add(this.childview);
```

#### Replace with

```vala
			var token = lang.split(".")[0];
			if (token == "bash") {
				this.tool_view = new RenderToolOutput(this, lang, this.is_streaming);
			} else {
				this.childview = new RenderSourceView(this, lang, this.is_streaming);
				this.source_view_handlers.add(this.childview);
			}
```

#### Remove — `on_code_text`

```vala
		public override void on_code_text(string text)
		{
			// Delegate to childview
			if (this.childview != null) {
				this.childview.add_code_text(text);
			}
		}
```

#### Replace with — `on_code_text`

```vala
		public override void on_code_text(string text)
		{
			if (this.tool_view != null) {
				this.tool_view.output(text);
				return;
			}
			if (this.childview != null) {
				this.childview.add_code_text(text);
			}
		}
```

#### Add — inside `clear`, after `this.childview = null`

```vala
			this.tool_view = null;
```

### 3. `libocmarkdowngtk/meson.build` and `docs/meson.build`

**Why:** a new source file is on both lists.

**Where:** the line after `RenderSourceView.vala` in each list.

**Depends on:** §1.

#### Add

```meson
  'RenderToolOutput.vala',
```

`docs/meson.build` uses the path form already on that list:

#### Add

```meson
    '../libocmarkdowngtk/RenderToolOutput.vala',
```

### 4. `libollmchatgtk/ChatView.vala` — connect Stop, show the renderer

**Why:** one connection when the renderer is created. `ChatWidget` has to reach `on_code_block`, and `renderer` is private.

**Where:** the `renderer` field, and immediately after the `start_new_chat_requested` connect.

**Depends on:** §2.

#### Remove

```vala
		private MarkdownGtk.Render renderer;
```

#### Replace with

```vala
		internal MarkdownGtk.Render renderer;
```

#### Add — after the `start_new_chat_requested` connect

Stop on a shell frame runs the active tool requests.

```vala
			this.renderer.stop_clicked.connect(() => {
				foreach (var req in this.chat_widget.manager.session.agent.active_tools.values) {
					req.stop();
				}
			});
```

### 5. `libollmchatgtk/ChatWidget.vala` — live chunks and restore

**Why:** live start opens the same fence restore parses. The `active_tools` loop is no longer in the frame.

**Where:** drop `current_output`. Replace the `client.run_tool` switch. Replace the restore fence header and look up `arguments.command`.

**Depends on:** §2 and §4.

#### Remove

```vala
		private ToolOutput? current_output;
```

#### Remove

```vala
				case "client.run_tool.start":
					this.current_output = new ToolOutput(
						this.manager, notif.message, notif.action);
					this.chat_view.add_widget_frame(this.current_output);
					return;

				case "client.run_tool.output":
					this.current_output.output(notif.message);
					return;

				case "client.run_tool.end":
					this.current_output.close();
					this.current_output = null;
					return;
```

#### Replace with

```vala
				case "client.run_tool.start":
					this.chat_view.renderer.on_code_block(true,
						"bash.oc-frame-info " + notif.message);
					this.chat_view.renderer.tool_view.status = notif.action;
					return;

				case "client.run_tool.output":
					this.chat_view.renderer.tool_view.output(notif.message);
					return;

				case "client.run_tool.end":
					this.chat_view.renderer.on_code_block(false, "");
					return;
```

#### Remove

```vala
			if (this.restoring_session && m.role == "tool" &&
					(m.name == "bash" || m.name == "run_command")) {
				var ui_msg = new OLLMchat.Message("assistant",
					OLLMchat.Message.fenced(
						"text.oc-frame-success.collapsed Execution results",
						m.content),
					m.thinking);
```

#### Replace with

```vala
			if (this.restoring_session && m.role == "tool" &&
					(m.name == "bash" || m.name == "run_command")) {
				var command = "";
				for (int i = 0; i < session.messages.size; i++) {
					var prior = session.messages.get(i);
					for (int c = 0; c < prior.tool_calls.size; c++) {
						var call = prior.tool_calls.get(c);
						if (call.id != m.tool_call_id) {
							continue;
						}
						if (call.function.arguments.has_member("command")) {
							command = call.function.arguments.get_string_member("command");
						}
					}
				}
				var ui_msg = new OLLMchat.Message("assistant",
					OLLMchat.Message.fenced(
						"bash.oc-frame-info.collapsed " + command,
						m.content),
					m.thinking);
```

### 6. `libollmchatgtk/ToolOutput.vala` — delete

**Why:** `RenderToolOutput` is the listing.

**Where:** the file, and its line in `libollmchatgtk/meson.build`.

**Depends on:** §5.

#### Remove — `libollmchatgtk/meson.build`

```meson
  'ToolOutput.vala',
```

Delete `libollmchatgtk/ToolOutput.vala`.

## Attempts / changelog

- ✔️ 2026-11-05 — first note proposed a `ChatWidget` branch.
  - ✔️ It built `ToolOutput` from the saved `tool` row.
  - ✔️ Withdrawn.
- ✔️ 2026-11-05 — product code still unchanged.
- ✔️ 2026-11-06 — added the construct / insert / handle sites for both widgets.
- ✔️ 2026-11-06 — first handler note described the current `add_code_text` / `end_code_block` calls. Withdrawn. The registration is a method that stores a `Type` and `new`s it.
- ✔️ 2026-11-06 — no product code.
- ✔️ 2026-11-06 — registry withdrawn. `ToolOutput` depends on `History.Manager` only for Stop.
- ✔️ 2026-11-06 — proposed hunks applied. `libocmarkdowngtk` and `libollmchatgtk` compile. Not checked in the app.
- ✔️ 2026-11-08 — tablet `emulator-5556`, `org.roojs.ollmchat.androidpoc` pid 30273, installed 10:01. Bash runs: `Sandbox-Bubble.rpc_create`, `rpc_run`, `wait`, then RPC `output` and `finished`. The tool reply is stored (17 bytes, preview `done`; later 2435 bytes). `role=tool` is not UI-visible, so the live chat skips that row. `ChatWidget` only logs the waiting line. No crash. `RenderToolOutput` is constructed in `on_code_block` and never passed to `renderer.box.appender`.

## Next

- 🚫 More hunks in this file. The accepted proposal stays as applied.
- ✔️ 2026-11-09 — the frame is in the chat. [`2026-11-08-FIXED-bash-frame-not-in-chat.md`](2026-11-08-FIXED-bash-frame-not-in-chat.md).
- ⏳ 🔷 Stop one request. [`2026-11-06-stop-one-tool.md`](../2026-11-06-stop-one-tool.md).
