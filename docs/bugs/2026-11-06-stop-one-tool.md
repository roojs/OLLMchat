# Stop one tool

**Status:** ✔️ hunks applied. §2 skipped: `ollmapp/android/tools/Bash/Request.vala` is not in the tree.

**ℹ️** Follows [`2026-11-05-CLOSED-restore-bash-tool-output.md`](done/2026-11-05-CLOSED-restore-bash-tool-output.md). That cut connects `stop_clicked` with no id and stops every entry in `active_tools`.

## Problem

- 🔷 Stop on a shell frame stops that run.
- 🔷 The frame carries the request id. The signal passes that id.
- 🔷 `active_tools` is already keyed by that id. Look up one request and call `stop()` on it.
- 🚫 Routing output chunks by id. This cut is Stop only. One `tool_view` stays.

## Evidence

- ℹ️ `OLLMrpc.Notification.id` is an `int`. `RequestBase.request_id` is that int. `Agent.active_tools` is `Gee.HashMap<int, RequestBase>`.
- ℹ️ `client.run_tool.output` already sets `id = request_id`. `client.run_tool.start` does not. The frame is built on start, so the id has to be on that notification.
- ℹ️ `ChatView` connects `stop_clicked` and walks `active_tools.values`.

## Proposed code

- 🔷 Edits are **Remove** / **Replace with** / **Add**. Verify the surrounding lines before applying.
- 🚫 A second walk of `active_tools.values` on this click.
- 🚫 A new helper around `has_key` / `get` / `stop`.

### 1. `liboctools/Bash/Request.vala` — `execute`

**Why:** Chat reads `notif.id` when it builds the frame. Output already has the id. Start does not.

**Where:** the `client.run_tool.start` notification, next to `action`.

#### Remove

```vala
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.start",
				message = this.command.strip(),
				action = run_status,
			});
```

#### Replace with

```vala
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.start",
				message = this.command.strip(),
				action = run_status,
				id = this.request_id,
			});
```

### 2. `ollmapp/android/tools/Bash/Request.vala` — `execute`

Same start notification as §1.

#### Remove

```vala
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.start",
				message = this.command.strip(),
				action = run_status,
			});
```

#### Replace with

```vala
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.start",
				message = this.command.strip(),
				action = run_status,
				id = this.request_id,
			});
```

### 3. `liboctools/RunCommand/Request.vala` — `execute`

#### Remove

```vala
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.start",
				message = this.command.strip(),
				action = run_status,
			});
```

#### Replace with

```vala
			this.agent.notification(new OLLMrpc.Notification() {
				method = "client.run_tool.start",
				message = this.command.strip(),
				action = run_status,
				id = this.request_id,
			});
```

### 4. `libocmarkdowngtk/RenderToolOutput.vala` — field and click

**Why:** Stop is on that frame. The id has to be the one Chat stored at start.

**Depends on:** §1.

#### Add — after the `status` property

Request id from `client.run_tool.start`. Stop passes this value.

```vala
		public int request_id { get; set; default = 0; }
```

#### Remove

```vala
				this.renderer.stop_clicked();
```

#### Replace with

```vala
				this.renderer.stop_clicked(this.request_id);
```

### 5. `libocmarkdowngtk/Render.vala` — signal argument

#### Remove

```vala
		/** Stop was clicked on the open shell frame. */
		public signal void stop_clicked();
```

#### Replace with

```vala
		/**
		 * Stop was clicked on the open shell frame.
		 *
		 * @param request_id key in ''active_tools'' for that frame
		 */
		public signal void stop_clicked(int request_id);
```

### 6. `libollmchatgtk/ChatWidget.vala` — store `notif.id`

**Where:** `client.run_tool.start`, after `status` is set.

**Depends on:** §4 and §5.

#### Remove

```vala
					this.chat_view.renderer.tool_view.status = notif.action;
```

#### Replace with

```vala
					this.chat_view.renderer.tool_view.status = notif.action;
					this.chat_view.renderer.tool_view.request_id = notif.id;
```

### 7. `libollmchatgtk/ChatView.vala` — stop that id

**Where:** the `stop_clicked` connect, next to the other renderer signals.

**Depends on:** §5 and §6.

#### Remove

```vala
			this.renderer.stop_clicked.connect(() => {
				foreach (var req in this.chat_widget.manager.session.agent.active_tools.values) {
					req.stop();
				}
			});
```

#### Replace with

```vala
			this.renderer.stop_clicked.connect((request_id) => {
				var tools = this.chat_widget.manager.session.agent.active_tools;
				if (!tools.has_key(request_id)) {
					return;
				}
				tools.get(request_id).stop();
			});
```

## Next

- ✔️ 🔷 Applied §1 and §3–§7.
- ℹ️ §2 skipped. `ollmapp/android/tools/Bash/Request.vala` is not in the tree. Start is only emitted from `liboctools/Bash/Request.vala` and `liboctools/RunCommand/Request.vala`.
