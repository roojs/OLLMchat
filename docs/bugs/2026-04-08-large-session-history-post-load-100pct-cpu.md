# Large session history: sustained ~100% CPU after load completes

**Status: OPEN** — Hotspot identified in **`RenderSourceView.scroll_bottom`** (see **Where the issue is in code**). **No fix merged** until a design is agreed.

## Problem

After the application **finishes** loading a **very large** session history into the chat UI, the process **continues** to use **~100% of one CPU core** indefinitely. With a **small** history, CPU returns to idle after load. The issue appears **tied to transcript size / UI work**, not to indexer or background file scanning (scanning runs for both cases; user reports it does not drive this symptom).

**Expected:** Once restore and layout settle, main-thread work should drop to near idle unless the user interacts or streaming runs.

**Actual:** Sustained high CPU matching a **main-loop hot path** (idle, layout, or timer).

**Repro notes:** ~100% CPU persists after the window is **hidden** or **focus is lost**. **`ibus-daemon`** may spike CPU early then settle; the **application process** can remain hot while **apparently idle** — treat IM separately from our main-loop work.

## Ruled out (current evidence)

- **`resize_widget_callback`** (fenced frame sizing): noisy when measured, but **not** the log flood site once per-idle tracing was added.
- **Background scanning** (`libocfiles` / tooling): does not explain large-only behaviour.

## Confirmed (instrumentation, since removed)

With **`GLib.debug("idle");`** at idle entry, stderr **flooded** from **`RenderSourceView.scroll_bottom`** (the branch that schedules **`GLib.Idle.add`** when **`vadjustment.upper < 10`**). That pins the hotspot to the code below — not a guess.

---

## Current code (what we have today)

**File:** `libocmarkdowngtk/RenderSourceView.vala`

### 1. `scroll_bottom` — nested scroll “wait for layout” retry

```698:721:libocmarkdowngtk/RenderSourceView.vala
		private void scroll_bottom(Gtk.ScrolledWindow? sw = null)
		{
			if (!this.body_revealer.reveal_child) {
				return;
			}
			var target = sw;
			if (target == null) {
				target = (this.nested_markdown_render != null)
					? this.scrolled_window
					: this.source_scrolled;
			}
			var vadjustment = target.vadjustment;
			if (vadjustment == null) {
				return;
			}
			if (vadjustment.upper < 10.0) {
				GLib.Idle.add(() => {
					this.scroll_bottom(target);
					return false;
				});
				return;
			}
			vadjustment.value = vadjustment.upper;
		}
```

**Intent:** If the `Gtk.ScrolledWindow`’s vertical range is not ready (`upper` tiny), **defer** one frame and try again, then set `value = upper` to show the bottom.

### 2. Who calls `scroll_bottom` (drivers)

Every streaming chunk for visible fenced content schedules **another** idle that ends in `scroll_bottom()`:

```602:607:libocmarkdowngtk/RenderSourceView.vala
			// Scroll visible content (rendered or source) to bottom after content is added
			GLib.Idle.add(() => {
				this.scroll_bottom();
				return false;
			});
			this.renderer.code_block_content_updated();
```

After a fenced **`markdown`** code block ends, **resize + scroll** paths also call it (directly or after timeout):

```653:668:libocmarkdowngtk/RenderSourceView.vala
				GLib.Timeout.add(200, () => {
					if (this.body_revealer.reveal_child) {
						this.resize_widget_callback((Gtk.Widget) this.rendered_box, ResizeMode.INITIAL);
						this.scroll_bottom(this.scrolled_window);
					}
					return false;
				});
			}
			// Finalize the sourceview - resize based on content rules
			if (this.source_view != null) {
				GLib.Idle.add(() => {
					if (!this.body_revealer.reveal_child) {
						return false;
					}
					var result = this.resize_widget_callback(this.source_view, ResizeMode.FINAL);
					this.scroll_bottom(this.source_scrolled);
					return result;
				});
			}
```

So: **large history** ⇒ many fenced blocks ⇒ many **`add_code_text`** chunks ⇒ **many** `Idle.add` → `scroll_bottom` invocations even when the user is not actively streaming.

---

## Where the issue is in code

1. **`scroll_bottom` when `vadjustment.upper < 10.0` (lines 713–718)**  
   Each call **always** schedules **a new** `GLib.Idle.add` that calls `scroll_bottom(target)` again. There is **no** “already have a pending retry” guard. So:
   - If **`scroll_bottom` is invoked many times** before `upper` crosses 10 (e.g. many chunks × many frames), you queue **many** idles that all do the same retry.
   - If **`upper` stays below 10** for a long time (nested layout not finished, revealer/stack, or pathological adjustment), **each** completed idle schedules **another** single-shot idle → **continuous main-loop work** and logs that repeat on the same line (what we saw with debug).

2. **Interaction with `add_code_text` (lines 602–606)**  
   Every chunk schedules **one** idle → `scroll_bottom()`. That multiplies traffic into (1) for busy streams and large restores.

3. **Not the root cause by itself:** `resize_widget_callback` / fence resize can be frequent but was **ruled out** as the flooding source compared to **`scroll_bottom`’s `upper < 10` branch**.

**Secondary suspect (if anything remains after addressing the above):** `ChatView.scroll_to_bottom` — idle handler can **`return true`** while `vadjustment.upper < 100.0`, which can also spin the default idle source (`libollmchatgtk/ChatView.vala`). Revisit after `scroll_bottom` behaviour is understood and measured.

---

## Related prior work

- `docs/plans/done/6.9-DONE-debugging-performance.md` — nested markdown / restore cost.
- `docs/plans/done/6.8-DONE-fixing-large-restore.md` — parser path for large restore (distinct symptom).

## Proposed design (architecture — sensible direction)

**Idea:** Do **not** fight the storm inside **`scroll_bottom`** with ad-hoc caps alone. Instead, **separate “content arrived” from “scroll after layout is valid”**, and **batch** scroll work so the **“wait for layout”** path (`upper < 10` → retry **once** behind a redraw) runs in a **controlled** place — especially after **session load completes**.

1. **Signal `scroll_pending(Gtk.Widget target)`** on **`MarkdownGtk.Render`**  
   **`target`** is the **concrete widget** that needs a bottom scroll once layout is valid (e.g. the nested **`Gtk.ScrolledWindow`** **`RenderSourceView`** scrolls — pass **`this.scrolled_window`** or whatever actually owns **`vadjustment`**). Emit **`this.renderer.scroll_pending(this.scrolled_window);`** — no wrappers. Meaning: *this* scroller is pending — **not** **N**× **`Idle.add` → scroll_bottom** per chunk with no identity.

2. **Relay up the tree**  
   **`Render`** forwards the **`target`** with the signal so **`ChatView`** (or the session layer) does not guess which nested frame was last touched.

3. **Queue holds targets; dedupe on the caller, not in `ChatView`**  
   **`RenderSourceView`** (or whichever view emits **`scroll_pending`**) owns **`public bool is_scroll_queued`** (read-only outside, **`default = false`**). **Before** emitting **`scroll_pending`**, **`if (this.is_scroll_queued) return;`** then **`this.is_scroll_queued = true`**. That avoids **`scroll_queue.contains(target)`** on **`ChatView`** (no **`O(n)`** lookup, no identity questions across widget types). **`ChatView`** calls **`this.renderer.scroll_handled(target)`** after it has applied scroll (and any **`queue_allocate`** / resize step tied to that drain step) for **`target`** — **`RenderSourceView`** connects **`scroll_handled`** and clears **`is_scroll_queued`** when **`target == this.scrolled_window`**. While a **history restore** is in progress, **`scroll_pending`** **enqueues** **`target`**; use the **existing** **`ChatWidget.restoring_session`** — **do not** add **`history_loading`** on **`ChatView`** (see **Restore flag** below).

4. **After load → drain queue**  
   On **`session_restored`**: **`restoring_session`** is already cleared in **`ChatWidget`**; **`queue_allocate`** once if needed, then **drain** **`scroll_queue`** via **`run_scroll_queue`** (see mock).

5. **Live streaming**  
   When **`!this.chat_widget.restoring_session`**, **`scroll_pending(target)`** can **apply immediately** (allocate + idle) for that **`target`**, or coalesce per-frame — dedupe **`upper < 10`** with **`retry_idle`** inside **`RenderSourceView`** (see mock).

### Restore flag (existing — no duplicate property)

**`libollmchatgtk/ChatWidget.vala`** exposes **`internal bool restoring_session`** (read-only outside the class): **`true`** from **`switch_to_session`** (with **`scroll_enabled = false`**) until **`session_restored`** or load error. That is exactly “history is loading / replaying into the UI.”

**`ChatView`** keeps **`private ChatWidget chat_widget`** but **cannot** read **`private restoring_session`**. **Implementation:** expose read-only access on **`ChatWidget`** (same semantics, no second name). Prefer **`internal`** so only **`libollmchatgtk`** (e.g. **`ChatView`**) can read it; use **`public`** if a caller outside that library must see it.

**Concrete change (`libollmchatgtk/ChatWidget.vala`) — before:**

```vala
		/** True while restoring a session from history; used to keep autoscroll disabled until restoration is done. */
		private bool restoring_session = false;
```

**After (implemented: `internal`, read-only from outside the class):**

```vala
		/** True while restoring a session from history; used to keep autoscroll disabled until restoration is done. */
		internal bool restoring_session { get; private set; default = false; }
```

**Alternative** if something outside **`libollmchatgtk`** must read the flag — same pattern with **`public`** instead of **`internal`**.

Existing assignments (**`this.restoring_session = true/false`**) stay valid; **`scroll_pending`** uses **`if (this.chat_widget.restoring_session) { scroll_queue.add(…); }`** — **no** new property on **`ChatView`**.

**Touch points:**

| Layer | Role |
| ----- | ---- |
| **`RenderSourceView`** | **`is_scroll_queued`** guard → **`scroll_pending`**; listen for **`scroll_handled`** to clear **`is_scroll_queued`**. |
| **`MarkdownGtk.Render`** | **`signal void scroll_pending(Gtk.Widget target);`** and **`signal void scroll_handled(Gtk.Widget target);`** (emit **`scroll_handled`** after scroll/resize for that **`target`** is applied). |
| **`ChatView`** | **`scroll_queue`**, **`scroll_pending`** handler → enqueue if **`chat_widget.restoring_session`**, else immediate scroll; **`run_scroll_queue`** / immediate path → **`scroll_handled(target)`**. |
| **`ChatWidget`** | Already sets **`restoring_session`**; **`session_restored`** → **drain `scroll_queue`** via **`run_scroll_queue`** (no extra flag on **`ChatView`**). |

**sysprof** after this shape exists: confirm main thread is quiet when idle post-load.

**Instrumentation:** Temporary **`GLib.debug("idle");`** lines were removed from the tree after narrowing (`docs/bug-fix-process.md`).

### `session_restored` and idles

**`History.Manager.switch_to_session`** finishes **`yield restore_messages`**, then calls **`session_restored(loaded_session)`** **directly** on the same async continuation — **`Manager` does not wrap it in `GLib.Idle.add`**. Handlers run **right after** replay ends (main thread), not inside an extra idle from **`Manager`**:

```220:249:libollmchat/History/Manager.vala
		public async void switch_to_session(SessionBase session) throws Error
		{
			if (this.cancel_restore != null) {
				this.cancel_restore.cancel();
			}
			this.cancel_restore = new GLib.Cancellable();
			var cancellable = this.cancel_restore;

			this.session.deactivate();

			SessionBase? loaded_session = yield session.load();

			if (loaded_session == null) {
				throw new GLib.IOError.FAILED("Session load returned null");
			}

			this.session = loaded_session;
			loaded_session.activate();

			this.session_activated(loaded_session);
			this.agent_status_change();

			if (loaded_session is Session) {
				yield ((Session) loaded_session).restore_messages(cancellable);
			}

			this.session_restored(loaded_session);
		}
```

Whether you need **one** outer **`Idle.add`** before touching adjustments (let GTK flush layout from the last replay step) is **empirical** — start **without** extra nesting; add **at most one** pre-idle if **`upper`** is still wrong on first read.

**Draining the queue:** avoid **`Idle.add(() => { Idle.add(() => { … }); })`** for every item. Prefer **one** method that processes **one** queued **`target`**, applies the adjustment, then **`GLib.Idle.add(() => run_scroll_queue())`** so each remaining item runs on a **subsequent** idle — spreads work and keeps recursion shallow.

---

## Proposed code (mock — not merged)

Illustrative **Vala-shaped** sketches only: **not** a drop-in patch. **Naming:** at most **two words** per identifier where practical; **emit signals directly** (`this.renderer.signal_name();`) — **no** thin `emit_*` / `request_*` wrappers.

### 1. `MarkdownGtk.Render` — **`scroll_pending`** and **`scroll_handled`**

```vala
public signal void scroll_pending(Gtk.Widget target);
public signal void scroll_handled(Gtk.Widget target);
```

Emit **`scroll_pending`** with the **widget that owns the pending scroll** (nested **`Gtk.ScrolledWindow`** is the usual **`target`**). After **`ChatView`** applies scroll (and any resize/allocate step for that step), emit **`scroll_handled(target)`** so the **caller** can clear **`is_scroll_queued`**.

### 2. `RenderSourceView` — caller guard + **`scrolled_window`**

**Field** (public read, private write — set/clear only here and via **`scroll_handled`**):

```vala
public bool is_scroll_queued { get; private set; default = false; }
```

**Connect once** (e.g. after **`this.renderer`** exists):

```vala
this.renderer.scroll_handled.connect((target) => {
	if (target == this.scrolled_window) {
		this.is_scroll_queued = false;
	}
});
```

Replace the per-chunk idle that only called **`scroll_bottom()`** with guarded emit — **no** **`scroll_queue.contains`** on **`ChatView`**:

```vala
// Was: GLib.Idle.add(() => { this.scroll_bottom(); return false; });
if (this.is_scroll_queued) {
	return;
}
this.is_scroll_queued = true;
this.renderer.scroll_pending(this.scrolled_window);
```

**`scroll_bottom`** (`upper < 10`) — see **(6)** — may still exist for internal paths; must **not** schedule unbounded idles.

### 3. `ChatView` — **`scroll_queue`**, **`scroll_pending`**, **`run_scroll_queue()`**

**Handler** (live path: still one idle for immediate scroll; bulk path: enqueue only while **`ChatWidget.restoring_session`** — **no** **`contains`** on the list):

```vala
public Gee.ArrayList<Gtk.Widget> scroll_queue = new Gee.ArrayList<Gtk.Widget>();

this.renderer.scroll_pending.connect((target) => {
	if (this.chat_widget.restoring_session) {
		this.scroll_queue.add(target);
		return;
	}
	this.queue_allocate();
	GLib.Idle.add(() => {
		var sw = target as Gtk.ScrolledWindow;
		if (sw != null) {
			sw.vadjustment.value = sw.vadjustment.upper;
		}
		this.scroll_to_bottom();
		this.renderer.scroll_handled(target);
		return false;
	});
});
```

**Drain** — **pop one**, apply scroll, **`scroll_handled`**, then **`Idle.add` → `run_scroll_queue`** until the queue is empty, then **`scroll_to_bottom`** for the outer chat.

```vala
public void run_scroll_queue()
{
	if (this.scroll_queue.size == 0) {
		this.scroll_to_bottom();
		return;
	}
	var w = this.scroll_queue.remove_at(0);
	var sw = w as Gtk.ScrolledWindow;
	if (sw != null) {
		sw.vadjustment.value = sw.vadjustment.upper;
	}
	this.renderer.scroll_handled(w);
	GLib.Idle.add(() => {
		this.run_scroll_queue();
		return false;
	});
}
```

**Note:** **`scroll_queue`** may hold **duplicate** **`target`** pointers if something bypassed the caller guard — **`scroll_handled`** still fires per dequeue; the second dequeue clears **`is_scroll_queued`** again harmlessly. Prefer the **caller** guard so the queue stays short.

### 4. `ChatWidget` — **`session_restored`**: no double-idle by default

**`restoring_session = true`** is already set before **`yield switch_to_session`** in **`switch_to_session`** — do **not** duplicate a **`ChatView`** flag.

```vala
this.manager.session_restored.connect((_session) => {
	this.restoring_session = false;
	this.chat_view.scroll_enabled = true;
	this.chat_view.queue_allocate();
	this.chat_view.run_scroll_queue();
});
```

Optional **single** **`GLib.Idle.add(() => { this.chat_view.run_scroll_queue(); return false; })`** **only if** first-frame layout is still wrong without it — **not** the default **Idle → Idle** sandwich from the old mock.

Cast / widget type details unchanged — **the queue drains through **`run_scroll_queue`****, not a **foreach** inside nested idles.

### 5. `RenderSourceView.scroll_bottom` — `upper < 10` (dedupe idle, two-word field)

```vala
private bool retry_idle = false;

if (vadjustment.upper < 10.0) {
	if (this.retry_idle) {
		return;
	}
	this.retry_idle = true;
	GLib.Idle.add(() => {
		this.retry_idle = false;
		this.scroll_bottom(target);
		return false;
	});
	return;
}
```

Combine with **(3)–(4)** so bulk work does not hammer this path during restore, or centralize nested scroll entirely from **`ChatView`** after **`scroll_pending`** + **`run_scroll_queue`**.

---

## Next steps (smaller tactics — only if needed after the architecture above)

- **Dedupe** a single pending **`upper < 10`** retry per `RenderSourceView` / target as a **safety net** inside **`scroll_bottom`** while the new pipeline is rolled out.
- **Throttle** per-chunk **`add_code_text`** scroll (newline-only or timer) for live streams if profiling still shows hot paths.

## Evidence to collect

- **sysprof** (main thread) after a chosen approach is prototyped.
- Manual: large session → confirm CPU drops when idle storm is gone.

## Conclusions

- **Failure mode:** Unbounded or repeated **`GLib.Idle.add`** from **`scroll_bottom`** when **`upper < 10`**, amplified by **per-chunk** idle scheduling in **`add_code_text`** during large restores.
- **Preferred direction:** **`scroll_pending` / `scroll_handled`**, **`scroll_queue`**, **`run_scroll_queue()`** (one adjustment per idle, then re-enter). **Dedupe** with **`RenderSourceView.is_scroll_queued`** on the **caller** — **not** **`scroll_queue.contains`** on **`ChatView`**. Reuse **`ChatWidget.restoring_session`** for **`ChatView`** — **no** separate **`history_loading`**. **`session_restored`** is **not** pre-wrapped in **`Idle.add`** by **`Manager`**. **`retry_idle`** in **`scroll_bottom`** is optional safety net.

## Changelog

- 2026-04-08 — File created: problem statement, ruled-out items, idle suspects, evidence plan (per `docs/bug-fix-process.md`).
- 2026-04-08 — Repro: high CPU **after hide / focus lost**; **ibus-daemon** settles while app stays hot. Evidence plan: **idle `GLib.debug` first**, then **sysprof**.
- 2026-04-08 — **Phase 1 instrumentation:** `GLib.debug("idle");` at idle entry (thread→main continuations after `yield` in select/read_dir). **`examples/oc-test-gtkmd.vala` omitted.**
- 2026-04-08 — **Confirmed:** flood at **`RenderSourceView.scroll_bottom`** **`upper < 10`** idle path.
- 2026-04-08 — **Temporary `GLib.debug("idle");` and fence-resize diagnostics removed** from the tree after narrowing (build verified).
- 2026-04-08 — **Doc rework:** **Current code** + **Where the issue is** with line citations; removed prescriptive coalesce/cap **Implementation** block; **Next steps** as open design.
- 2026-04-08 — **Proposed design (architecture):** signal **scroll-after-layout**, **Render** relay, **queue during session load**, **flush once** after load + redraw; **`scroll_bottom`** retry as single controlled pass, not per-chunk storm.
- 2026-04-08 — **Proposed code (mock):** Vala sketches — **`scroll_pending`**, **`scroll_queue`**, **`run_scroll_queue`**, **`retry_idle`** — **not merged**.
- 2026-04-08 — Use existing **`ChatWidget.restoring_session`** (expose for **`ChatView`**) instead of a new **`history_loading`** property.
- 2026-04-08 — Mock tightened: **short names**, **direct signal emit**, **no helper wrappers**.
- 2026-04-08 — Design: signal carries **`target`**; **`scroll_queue`** holds widgets — not a bool-only **`scroll_queued`**.
- 2026-04-08 — **Dedupe:** **`is_scroll_queued`** on **`RenderSourceView`** (caller); **`scroll_handled`** clears it after **`ChatView`** applies scroll — no **`contains`** on queue.
- 2026-04-08 — **`session_restored`** timing (**`Manager`** synchronous after **`restore_messages`**); drain via **`run_scroll_queue()`** (chain idles, no nested **`Idle`→`Idle`**); optional single pre-idle only if needed.
- 2026-04-08 — **`ChatWidget.restoring_session`**: concrete before/after in **Restore flag**; code uses **`internal bool … { get; private set; default = false; }`**.
