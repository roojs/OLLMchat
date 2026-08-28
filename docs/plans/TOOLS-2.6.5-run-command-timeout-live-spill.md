# 2.6.5 Timeout, live output, spill, libsecret

> **Do not update `docs/plans/TOOLS-1.0-summary.md` for this plan.**

> Split from `TOOLS-2.6.4-URGENT-run-command-stop-live-tail-spill.md`. Done cut: [`done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md`](done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md). VTE is **not** here: [`TOOLS-2.6.6-FUTURE-run-command-vte.md`](TOOLS-2.6.6-FUTURE-run-command-vte.md).

**Status:** **ACTIVE** — Phase **4a** live UI (widget-through-layers investigation first).

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/2.6-DONE-run-terminal-command-tool.md`](done/2.6-DONE-run-terminal-command-tool.md) · related: [`done/2.6.3-DONE-run-command-root-elevation.md`](done/2.6.3-DONE-run-command-root-elevation.md), [`TOOLS-2.6.2-bwrap-ux-fixes.md`](TOOLS-2.6.2-bwrap-ux-fixes.md)

**Precedent (password store + hold fill):** RooTerm — `app.RooTerm/src/Config.vala` (`Secret.password_store`), `app.RooTerm/src/Terminal/Ssh.vala` (`Secret.password_lookup_sync`), `app.RooTerm/src/Host/TabBar.vala` (overlay fill on hold/countdown), `app.RooTerm/resources/style.css` (`.host-tab-close-fill`).

---

## Purpose

- **🔷** `⏳` Stuck runs hit a **default wall-clock timeout**. The model can raise it per call.
- **🔷** `⏳` **Live** visibility while the command runs (streaming / updating UI) — **without** stuffing an unbounded blob into the chat text buffer.
- **🔷** `⏳` Phase **4a** starts here: revive a **live widget** in the transcript, not framed markdown firehose. Pass the widget through the GTK-free layers as **`GLib.Object`** (shell casts to `Gtk.Widget`).
- **🔷** `⏳` **Short** runs: keep output in memory for the tool result. **Long** runs: spill full output to a **temp file** and put that path in the result so the model can `read_file` / shell-read what it needs (still include a tail in the result).
- **🔷** `⏳` Repeated sudo typing: store with **libsecret**; **hold** Allow **two seconds** to reuse (not a single click). **Low priority** — after timeout / live / spill.
- **🔷** `⏳` **Linux GTK** gets live UI first; libsecret later. **Windows** keeps subprocess + text frames with timeout/tail/spill where possible. **Android:** tool stays unregistered.
- **ℹ️** Stop, last-50 tail, and `ChatWidget` `tool_frame` already landed in **2.6.4**. Reuse `Request.stop()` / `Bubble.stop()`. RPC methods are `client.run_tool.start` / `client.run_tool.end`.

**Suggested order**

- **Now:** Phase **4a** (live widget in the chat — investigation below, then implement).
- **Next:** Phase 3c (timeout) and Phase **4b** (spill-to-file).
- **Late:** Phase 2 (libsecret + hold two seconds).

---

## Current behaviour

- **ℹ️** Live frame: `ChatWidget` `tool_frame` / `tool_header` / `tool_status`. Shown on `client.run_tool.start`, unparented on `client.run_tool.end`. Header is bold `.command-preview`. Stop kills `agent.active_tools`. No live stdout in the frame.
- **ℹ️** Results are one `add_message` fence **after** the command finishes. Rolling last 50 lines in RAM. No spill file. No wall-clock timeout.
- **ℹ️** Root runs: type password every time → `sudo -S true` check → pipe into `sudo -S /bin/sh -c …`. Copy says the password is not saved. See `ChatPermission.vala`, `Request.execute_with_subprocess()`.
- **ℹ️** **Windows:** `run_command` is registered. No bwrap, no sudo, no libsecret.
- **ℹ️** **Android:** tool is **not** registered.

---

## Platforms

- **🔷** `⏳` **Linux GTK:** timeout, live bounded UI, spill file. Libsecret hold-password is late polish (Phase 2).
- **🔷** `⏳` **Windows:** subprocess + text frames. Apply timeout, last-slice, spill. No libsecret, no `run_as_root`.
- **🔷** `⏳` **Android:** leave the tool disabled. Do not register `run_command`. Do not add `libsecret` to the Android meson cut.
- **ℹ️** **Linux CLI** (`ollmchat-cli`): no live widget. Subprocess, last-slice, spill, timeout. No hold-password UI.

---

## Phase 3c — Timeout

Reuses `stop()` from **2.6.4**.

- **🔷** `⏳` Every `run_command` has a wall-clock timeout. When it fires, kill the process group (**same `stop()` as Stop**) and return the tail plus a clear timed-out line so the model can retry with a larger `timeout`.
- **🔷** `⏳` Tool argument **`timeout`** (seconds, integer). Document in `Tool.description` and `Tool.parameter_description`.
- **🔷** Default **60** seconds when omitted.
- **🔷** `timeout <= 0` (no timer / wait until Stop) is **not** in this phase. That would need a second permission (we may not support stacking prompts). Decide later — no `ERROR:` reject and no infinite hang here.
- **🔷** `⏳` User **Stop** still works before the timer.
- **ℹ️** Elapsed time from spawn, not idle-time.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `liboctools/RunCommand/Request.vala` — `timeout` property + kill on expiry

**Why:** Hung interactive prompts must not block the agent forever.

**Where:** property next to `allow_write`; after spawn, arm `GLib.Timeout.add_seconds`. **Inline** — no `arm_timeout()` helper.

**Depends on:** **2.6.4** `stop()`.

- **🔷** `⏳` After spawn: `GLib.Timeout.add_seconds(this.timeout, …)` calls `this.stop()` if still running, then lets wait/read finish.
- **🔷** `⏳` On exit: `GLib.Source.remove` the timeout id (`0` = none).
- **🔷** `⏳` Append when the timer fired: `Command timed out after N seconds. Raise timeout in run_command if this was expected to run longer.` Distinguish from user Stop (do not use the same `Command stopped by user.` line).
- **🔷** `⏳` Same timer on the subprocess path and the bwrap path.
- **🔷** `⏳` `to_summary()`: add `Timeout: ` + seconds when not 60.

#### Add — property next to `allow_write`

```vala
		/**
		 * Wall-clock seconds before the child is killed. Omitted JSON uses 60.
		 */
		public int timeout { get; set; default = 60; }
```

### 2. `liboctools/RunCommand/Tool.vala` — describe timeout

**Where:** `description` Timeout bullets; `parameter_description` after `run_as_root`.

**Depends on:** **2.6.4** Tool Output bullet, §1.

#### Add — in `description` (after the Output bullets)

```
Timeout:
- Default is 60 seconds. Commands that block (SSH password, missing TTY) are killed at that cap.
- Set `timeout` (seconds) higher for installs, compiles, or other long jobs.
```

#### Add — in `parameter_description`

```
@param timeout {integer} [optional] Wall-clock seconds before the command is killed. Defaults to 60. Increase for long jobs.
```

---

## Phase 4 — Live output (bounded UI) + spill to file

**Why:** See progress and Stop on the existing pipe path. Avoid filling chat `TextBuffer` / markdown frames with megabytes.

### 4a. Live streaming to the UI — bounded widget (start here)

- **🔷** `⏳` While the command runs, the user can **see output updating** (not only the final fence).
- **🔷** `⏳` Do **not** append unbounded stdout into the embedded chat text buffer / `RenderSourceView` frame body.
- **🔷** `⏳` Hook a **live widget** through the layers (GTK-free core types it as **`GLib.Object`**; GTK shell casts to `Gtk.Widget`). Same idea as `OLLMchat.Tool.UiWidgets.view_widget` and `ChatDesktopInterface.above_input_widget()`.
- **ℹ️** History restore: persist the **final** results fence (tail + spill note), not a live buffer replay.

#### What the original widget hook was

- **ℹ️** `RunTerminalCommand.create_terminal_widget()` returned `GLib.Object?` (`null` in the GTK-free base). `RunTerminalCommandGtk` overrode it with a `GtkSource.View`.
- **ℹ️** The base called `client.tool_message("$ " + command, widget)`, then `send_or_append_message(line)` / `append_to_widget(line)` as stdout arrived.
- **ℹ️** `OLLMchatGtk.Message` (`libollmchatgtk/Message.vala`) subclassed `OLLMchat.Message` with `public Gtk.Widget widget`.
- **ℹ️** `ChatView.append_tool_message` did `if (message is OLLMchatGtk.Message)`, wrapped that widget in a `Gtk.Frame`, and called `add_widget_frame`.

#### What is still in the tree

- **ℹ️** `ChatView.add_widget_frame(Gtk.Frame)` — live. **2.6.4** already uses it for `ChatWidget.tool_frame` on `client.run_tool.start` (unparent on `client.run_tool.end`). Header + status + Stop only. No live stdout.
- **ℹ️** `History.Manager.tool_message` → `ChatWidget` → `ChatView.append_tool_message`. The **widget extract branch is gone**. The method still documents it. Implementation is Pango insert only.
- **ℹ️** `handle_tool_message` does **not** persist to `session.messages`. `add_message` does. Live widget should stay on the tool_message / notification path. Final fence stays `add_message(Message.fenced(…))`.
- **ℹ️** `UiWidgets.view_widget` as `GLib.Object` — ChatBar / `view_stack` host, **not** the transcript. Pattern to copy, not the mount point.
- **ℹ️** `Notification.buffer` is already a non-serialized `GLib.Object` on `OLLMrpc.Notification`. `idx_first` / `idx_last` on `Message` already skip JSON.
- **ℹ️** Commented `send_initial_tool_message` / `send_or_append_message` in `liboctools/RunCommand/Request.vala` are the old **fenced-text** stream, not the widget path.

#### What is gone

- **ℹ️** `libollmchatgtk/Message.vala` (`OLLMchatGtk.Message`) — deleted (`a637f8ac`).
- **ℹ️** `Tools/RunTerminalCommandGtk.vala` / ToolsUI subclass — deleted. `create_terminal_widget` / `append_to_widget` are not on `Request`.
- **ℹ️** Tools switched to framed markdown: `agent.add_message(new Message("ui", Message.fenced("text.oc-frame-…", body)))`. That is the **after-the-run** results path. Do not reuse it for live stdout.

#### Revive (confirm before coding)

- **🔷** `⏳` Do **not** resurrect `OLLMchatGtk.Message`. `libollmchat` stays GTK-free. Put an optional **`GLib.Object`** on `OLLMchat.Message` (skip serialize, same as `idx_first`). GTK casts at `append_tool_message`.
- **🔷** `⏳` Restore the extract in `ChatView.append_tool_message`: non-null widget `GLib.Object` on the message → wrap in `Gtk.Frame` (or reuse `tool_frame`) → `add_widget_frame`. Null → keep today’s Pango/markdown path.
- **🔷** `⏳` `RunCommand.Request` gets the old virtuals back, typed GTK-free: `create_terminal_widget()` → `GLib.Object?`, `append_to_widget(string)`. CLI / no-UI: both no-ops. GTK path creates a **capped** `GtkSource.View` / `Gtk.TextView` and appends lines there.
- **💩** `⏳` Where the GTK `GLib.Object` is constructed: `liboctools` already links `gtk4`, so `Request` *could* build the view itself. Cleaner is a GTK-side factory (old ToolsUI subclass, or ChatWidget builds it and the request only appends). Confirm.
- **💩** `⏳` Live view shows a **rolling tail** only (same N as the LLM slice, or a slightly larger UI window). Older lines drop from the widget; full text goes to spill (4b). Confirm N for UI vs LLM.
- **💩** `⏳` Throttle UI updates (e.g. idle / 100ms) so a tight `yes` loop does not starve the main loop. Confirm.
- **ℹ️** `tool_frame` from **2.6.4** stays the chrome (bold command, status, Stop). The live output widget is the **body** of that frame, or the object passed on `tool_message` parented into it. Do not open a second live frame.

### 4b. Save output + spill past a size threshold

- **🔷** `⏳` **Short output:** keep it in memory. Tool result is the full (or tailed) text — **no** temp file.
- **🔷** `⏳` **Long output:** write the full stdout/stderr to a **temporary file**, then after the run give the LLM the **absolute path** in the tool result / results fence so it can `read_file` or a narrow shell read to inspect what it needs.
- **🔷** `⏳` When spilled, the model still gets a **tail** in the tool result (last N lines) **plus** a clear line naming the file (e.g. full output saved at `…/run_command-<id>.log`).
- **💩** `⏳` Threshold that flips “short” → “long”: **1 MiB** or **~10k lines** — pick one metric. Confirm.
- **💩** `⏳` Path under session/project temp (visible to later sandboxed `read_file` / commands), not a host-only `/tmp` the bwrap child cannot see. Confirm bind/visibility.

### 4c. Open design (confirm before coding)

- **💩** `⏳` While running long: ring buffer in RAM for the live UI + LLM tail, **and** stream all bytes to the spill file as they arrive (constant RAM). Short runs never open a file. Confirm.
- **💩** `⏳` stderr merged into the same spill file / memory blob, or separate. Confirm (today often concatenated).

---

## Phase 2 — libsecret + hold two seconds (late)

**Deferred.** Do this only after Phase 3c timeout and Phase 4 live/spill.

- **🔷** `⏳` First successful sudo password is stored in libsecret.
- **🔷** `⏳` Later root prompts: **hold** the allow control for **two seconds**. Background fill animates while held. Release early cancels. A single click must not approve.
- **🔷** `⏳` Deny stays a normal click.
- **ℹ️** RooTerm fill: `Gtk.Overlay` child is a box whose `width_request` grows; CSS paints `.host-tab-close-fill`. Copy that overlay-on-the-button idea, do not import RooTerm widgets.
- **ℹ️** RooTerm secret: `Secret.Schema` + `Secret.password_store.begin` / `Secret.password_lookup_sync`. Inline the same calls in `ChatPermission` (no secret-helper class).

**When a secret exists**

- **🔷** `⏳` Hide the password entry.
- **🔷** `⏳` Allow (root) becomes a hold target. Label along the lines of `Hold 2s — use saved password`.
- **💩** `⏳` A small `Use a different password` control that reveals the entry and restores click-Allow (typed password overwrites the secret on success). Confirm.

**When no secret exists**

- **🔷** `⏳` Keep today’s type-then-Allow path (`sudo -S true` before resume).
- **🔷** `⏳` On success, `Secret.password_store` the password, then proceed as now.

**Wrong stored password**

- **🔷** `⏳` `sudo -S true` still runs after a completed hold (same check as typed).
- **🔷** `⏳` Failure: show the entry, error label, delete the bad secret, do **not** resume.

**Schema (confirm)**

- **💩** `⏳` Schema `org.roojs.ollmchat.Elevation`, attribute `user` = `GLib.Environment.get_user_name()`, label `OLLMchat sudo`. One secret per login user.

**Build**

- **🔷** `⏳` `dependency('libsecret-1')` on `libollmchatgtk` (**Linux only**). `--pkg=libsecret-1`.
- **🔷** `⏳` `debian/control` Build-Depends: `libsecret-1-dev`.
- **ℹ️** Windows / Android meson: do not `dependency('libsecret-1', required: true)`. Root elevation stays Linux-only.

### 1. `libollmchatgtk/ChatPermission.vala` — hold fill on Allow when a secret exists

**Why:** Friction is the hold, not a second click.

**Where:** constructor (overlay around `allow_once_btn`); `request()` when `high_risk`; press/release controllers. **Inline** — no `start_hold()` / `on_hold_tick()` helpers.

**Depends on:** **2.6.4** permission `command_label`.

- **🔷** `⏳` Overlay fill box, CSS class `.elevation-hold-fill`, `halign = START`, width 0 until press.
- **🔷** `⏳` `Gtk.EventController` pressed: arm `GLib.Timeout.add(50)` (or 100). Each tick: `fill.width_request = (button_width * elapsed_ms) / 2000`. At `>= 2000` and still pressed: lookup secret, run existing `validate_elevation_and_resume`.
- **🔷** `⏳` Released or leave before 2000: remove timeout, `fill.width_request = 1`, `visible = false`.
- **🔷** `⏳` While holding, do **not** fire the existing `clicked` handler on Allow.
- **ℹ️** Match RooTerm tick math in `Host/TabBar.vala` (`width_request = (row.get_width() * left) / total`) — here fill **grows** with elapsed, it does not shrink.

### 2. `resources/style.css` — hold fill

**Where:** after `.command-preview`.

#### Add

```css
.permission-widget .elevation-hold-fill {
  background-color: alpha(@destructive_color, 0.45);
}
```

### 3. Secret store / lookup — inline in `validate_elevation_and_resume` and `request()`

**Where:** `validate_elevation_and_resume` after `ok` is true (store); `request()` when `high_risk` (lookup to decide hold vs type).

**Depends on:** meson `libsecret-1`.

- **🔷** `⏳` After typed (or held) password passes `sudo -S true`, `Secret.password_store.begin` with the schema above, then resume as today.
- **🔷** `⏳` At the start of a high-risk `request()`, `Secret.password_lookup_sync`. Non-empty → hold mode. Empty / error → type mode.
- **🔷** `⏳` Failed held password: `Secret.password_clear` (or store empty / delete), then type mode.

---

## LLM notes

- **🚫** Do not add a secret-helper class or `start_hold()` / `on_hold_tick()` — inline in `ChatPermission`.
- **🚫** Do not make Allow-Always remember root commands (still `one_time_only` for `run_as_root`).
- **🚫** Do not kill the child because the tail is long.
- **🚫** Do not put libsecret in `liboctools`.
- **🚫** Do not `dependency('libsecret-1')` as required on Windows or Android meson.
- **🚫** Do not implement Phase 2 (libsecret/hold) before Phase 4a / 3c / 4b (or the user reorders).
- **🚫** Do not resurrect `OLLMchatGtk.Message` (`Gtk.Widget` on a GTK subclass). Use `GLib.Object` on `OLLMchat.Message`.
- **🚫** Do not stream live stdout into `Message.fenced` / `RenderSourceView` (that is the **final** results path).
- **🚫** Do not implement VTE, add `CommandFrame.vala`, or add `vte-2.91-gtk4` — that is **2.6.6**.
- **🚫** Do not design Phase 4 to require a PTY or libsecret (pipe + bounded UI + spill must stand alone).
- **🚫** Do not register `run_command` on Android in this plan.
- **🚫** Do not treat a single click as “use saved password”.
- **🚫** Do not use output-idle as the timeout (elapsed time from spawn only).
- **🚫** Do not wait forever when `timeout` is omitted.
- **🚫** Do not add helpers (`format_tail`, `arm_timeout`, `kill_child`). Named stop methods already exist from **2.6.4**.
