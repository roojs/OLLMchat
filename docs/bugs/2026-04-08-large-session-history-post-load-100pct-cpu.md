# Large session history: sustained ~100% CPU after load completes

**Status: FIXED (direct)** — Hotspot was **`RenderSourceView.scroll_bottom`** (unbounded **`upper < 10`** retry idles). **Merged fix:** bounded retries via **`try_again`** + defer when **`!target.get_realized()`** (see **Fix applied**). Larger **scroll_pending / queue** design in this doc remains **optional** if symptoms return.

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

## Current code (`scroll_bottom` after fix)

**File:** `libocmarkdowngtk/RenderSourceView.vala`

### 1. `scroll_bottom` — at most one follow-up idle (no unbounded chain)

**`try_again`** (default **`true`**) limits deferral: the idle scheduled from **`!get_realized()`** or **`upper < 10`** calls **`scroll_bottom(..., false)`**; on that second entry, **`try_again`** is false, so we **return** instead of queueing another idle. No extra fields on the class — only the parameter on the nested call.

```699:735:libocmarkdowngtk/RenderSourceView.vala
		private void scroll_bottom(Gtk.ScrolledWindow? sw = null, bool try_again = true)
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
			if (!target.get_realized()) {
				if (!try_again) {
					return;
				}
				GLib.Idle.add(() => {
					this.scroll_bottom(sw, false);
					return false;
				});
				return;
			}
			var vadjustment = target.vadjustment;
			if (vadjustment == null) {
				return;
			}
			if (vadjustment.upper < 10.0) {
				if (!try_again) {
					return;
				}
				GLib.Idle.add(() => {
					this.scroll_bottom(target, false);
					return false;
				});
				return;
			}
			vadjustment.value = vadjustment.upper;
		}
```

**Intent:** Same as before — **`upper`** tiny means “layout range not meaningful yet” (heuristic, same idea as **`ChatView.scroll_to_bottom`**’s **`upper < 100`**). **Change:** do **not** reschedule forever when **`upper`** stays small or when many chunks each enqueue work; at most **one** extra idle per logical retry chain.

### Historical (failure mode — pre-fix)

Each **`upper < 10`** visit did **`GLib.Idle.add(() => { this.scroll_bottom(target); return false; })`** with **no** guard, so a completed idle could schedule another while **`upper`** was still **&lt; 10** → main-loop churn (and stderr flood with debug). **`add_code_text`** also schedules an idle → **`scroll_bottom()`** per chunk, amplifying traffic.

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

```653:670:libocmarkdowngtk/RenderSourceView.vala
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

## Where the issue was in code (historical)

1. **`scroll_bottom` when `vadjustment.upper < 10.0` (pre-fix)**  
   Each call **always** scheduled **a new** `GLib.Idle.add` that called `scroll_bottom(target)` again, with **no** cap on how many times that could chain if **`upper`** stayed tiny.

2. **Interaction with `add_code_text`**  
   Every chunk schedules **one** idle → **`scroll_bottom()`**, which **multiplied** traffic into (1) for large restores.

3. **`resize_widget_callback`** was **ruled out** as the log-flood site compared to **`scroll_bottom`’s `upper < 10` branch** (instrumentation).

**If symptoms return:** **`ChatView.scroll_to_bottom`** can still **`return true`** while **`vadjustment.upper < 100.0`** (`libollmchatgtk/ChatView.vala`) — separate idle-spin risk.

---

## Fix applied (merged)

| Item | Detail |
| ---- | ------ |
| **File** | `libocmarkdowngtk/RenderSourceView.vala` — **`scroll_bottom(Gtk.ScrolledWindow? sw = null, bool try_again = true)`** |
| **`!target.get_realized()`** | One **`GLib.Idle.add`** → **`scroll_bottom(sw, false)`**; second entry does **not** defer again. |
| **`vadjustment.upper < 10.0`** | Same pattern → **`scroll_bottom(target, false)`** so **`upper`** cannot drive an **unbounded** idle chain. |
| **Trade-off** | At most **one** follow-up idle per caller chain: if layout needs **two** frames (e.g. realize then **`upper`**), scroll may not apply until the next **`scroll_bottom`** from a new chunk/event — acceptable vs. burning CPU. |
| **Validation** | Manual: large session / post-load — **high CPU resolved** after this change; temporary **`GLib.debug`** in **`scroll_bottom` / `add_code_text`** removed after confirmation. |

**Not merged (optional architecture):** **`scroll_pending`**, **`scroll_queue`**, **`abort_scroll_drain`** sketches elsewhere in this doc — revisit only if nested-scroll behaviour still needs batching.

---

## Related prior work

- `docs/plans/done/6.9-DONE-debugging-performance.md` — nested markdown / restore cost.
- `docs/plans/done/6.8-DONE-fixing-large-restore.md` — parser path for large restore (distinct symptom).

## Proposed design (architecture — optional follow-up)

**Shipped fix:** **`scroll_bottom` `try_again`** (see **Fix applied**) — **not** this section.

The sketches below are **optional** if further batching is needed: **`scroll_pending`**, **`scroll_queue`**, **`run_scroll_queue`**, **`retry_idle`**, **`abort_scroll_drain`** (cancel idle sources + clear queue **before** **`clear_chat()`**). Details in **Proposed code (mock)**.

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
| **`RenderSourceView`** | **`public bool is_scroll_queued`**; **`public`** nested **`scrolled_window`** (read access); guard → **`scroll_pending(this)`**. |
| **`MarkdownGtk.Render`** | **`signal void scroll_pending(MarkdownGtk.RenderSourceView view);`** only — **no** helper methods on **`Render`** for scroll completion. |
| **`ChatView`** | **`scroll_queue`**, **`scroll_pending`** handler → enqueue if **`chat_widget.restoring_session`**, else immediate scroll; **`run_scroll_queue`** / immediate path → after nested **`vadjustment`**, **`view.is_scroll_queued = false`**. |
| **`ChatWidget`** | **`switch_to_session`** start: **cancel drain idle**, **clear `scroll_queue`**, reset **`is_scroll_queued`** on queued views — **before** **`clear_chat()`**; same on load **error**; **`session_restored`** → **drain `scroll_queue`** for the **new** session only. |

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

```vala
// Optional: GLib.Idle.add before first vadjustment if upper still wrong — empirical.
```

---

## Proposed code (mock — not merged)

### 1. `MarkdownGtk.Render`

```vala
public signal void scroll_pending(MarkdownGtk.RenderSourceView view);
```

### 2. `RenderSourceView`

```vala
public bool is_scroll_queued = false;
public Gtk.ScrolledWindow scrolled_window { get; private set; }
```

```vala
// Was: GLib.Idle.add(() => { this.scroll_bottom(); return false; });
if (this.is_scroll_queued) {
	return;
}
this.is_scroll_queued = true;
this.renderer.scroll_pending(this);
```

### 3. `ChatView` — queue, pending idles, abort, drain

```vala
public Gee.ArrayList<MarkdownGtk.RenderSourceView> scroll_queue = new Gee.ArrayList<MarkdownGtk.RenderSourceView>();
private uint scroll_drain_idle = 0;
private uint scroll_pending_idle = 0;

public void abort_scroll_drain()
{
	if (this.scroll_drain_idle != 0) {
		GLib.Source.remove(this.scroll_drain_idle);
		this.scroll_drain_idle = 0;
	}
	if (this.scroll_pending_idle != 0) {
		GLib.Source.remove(this.scroll_pending_idle);
		this.scroll_pending_idle = 0;
	}
	foreach (var v in this.scroll_queue) {
		v.is_scroll_queued = false;
	}
	this.scroll_queue.clear();
}
```

```vala
this.renderer.scroll_pending.connect((view) => {
	if (this.chat_widget.restoring_session) {
		this.scroll_queue.add(view);
		return;
	}
	this.queue_allocate();
	if (this.scroll_pending_idle != 0) {
		GLib.Source.remove(this.scroll_pending_idle);
		this.scroll_pending_idle = 0;
	}
	this.scroll_pending_idle = GLib.Idle.add(() => {
		this.scroll_pending_idle = 0;
		var sw = view.scrolled_window;
		if (sw != null && sw.vadjustment != null) {
			sw.vadjustment.value = sw.vadjustment.upper;
		}
		view.is_scroll_queued = false;
		this.scroll_to_bottom();
		return false;
	});
});
```

```vala
public void run_scroll_queue()
{
	if (this.scroll_queue.size == 0) {
		this.scroll_to_bottom();
		return;
	}
	var view = this.scroll_queue.remove_at(0);
	var sw = view.scrolled_window;
	if (sw != null && sw.vadjustment != null) {
		sw.vadjustment.value = sw.vadjustment.upper;
	}
	view.is_scroll_queued = false;
	if (this.scroll_drain_idle != 0) {
		GLib.Source.remove(this.scroll_drain_idle);
		this.scroll_drain_idle = 0;
	}
	this.scroll_drain_idle = GLib.Idle.add(() => {
		this.scroll_drain_idle = 0;
		this.run_scroll_queue();
		return false;
	});
}
```

### 4. `ChatWidget.switch_to_session`

```vala
public async void switch_to_session(OLLMchat.History.SessionBase session)
{
	this.chat_view.abort_scroll_drain();
	this.chat_view.finalize_assistant_message();
	this.streaming_state(true);
	this.clear_chat();
	this.chat_view.scroll_enabled = false;
	this.restoring_session = true;

	try {
		yield this.manager.switch_to_session(session);
	} catch (Error e) {
		this.chat_view.abort_scroll_drain();
		GLib.warning("Error loading session: %s", e.message);
		this.streaming_state(false);
		this.chat_view.scroll_enabled = true;
		this.restoring_session = false;
		return;
	}
}
```

### 5. `ChatWidget.session_restored`

```vala
this.manager.session_restored.connect((_session) => {
	this.restoring_session = false;
	this.chat_view.scroll_enabled = true;
	this.chat_view.queue_allocate();
	this.chat_view.run_scroll_queue();
});
```

```vala
// Optional only if first-frame layout wrong without it:
// GLib.Idle.add(() => { this.chat_view.run_scroll_queue(); return false; });
```

### 6. `RenderSourceView.scroll_bottom` (`upper < 10`)

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

---

## Next steps (only if needed)

- **`try_again`** already caps **`scroll_bottom`** retries; mock **§6 `retry_idle`** in this doc is **optional** extra hardening, not merged.
- **Throttle** per-chunk **`add_code_text`** scroll (newline-only or timer) for live streams if profiling still shows hot paths after the fix.

## Evidence to collect

- **sysprof** (main thread) if CPU regressions reappear.
- Manual large-session check already **passed** for the **scroll_bottom** fix; keep as regression spot-check after related changes.

## Conclusions

- **Failure mode (addressed):** Unbounded **`GLib.Idle.add`** chaining inside **`scroll_bottom`** when **`vadjustment.upper < 10`** (and no cap on retries), amplified by **per-chunk** idles from **`add_code_text`** during large restores.
- **Fix shipped:** **`try_again`** bounds retries (see **Fix applied** and **Current code**); **`!get_realized()`** uses the same single-defer pattern.
- **Optional follow-up (not required for the reported symptom):** **`scroll_pending` / `scroll_queue` / `abort_scroll_drain`** architecture in this doc — only if profiling shows remaining nested-scroll cost. **`ChatView.scroll_to_bottom`** **`upper < 100`** retry loop remains a separate place to watch.

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
- 2026-04-08 — Design: signal carries **`RenderSourceView`**; **`scroll_queue`** holds views — not a bool-only **`scroll_queued`**.
- 2026-04-08 — **Dedupe:** **`public is_scroll_queued`** on **`RenderSourceView`**; **`ChatView`** assigns **`false`** after applying nested scroll — no **`Render`** helpers, no registry.
- 2026-04-08 — **Dropped `scroll_applied` / `register_scroll_target`:** public flag + signal payload **`view`** instead.
- 2026-04-08 — **`session_restored`** timing (**`Manager`** synchronous after **`restore_messages`**); drain via **`run_scroll_queue()`** (chain idles, no nested **`Idle`→`Idle`**); optional single pre-idle only if needed.
- 2026-04-08 — **Session switch:** **`scroll_queue` + drain idle** must be **cleared / cancelled** **before** **`clear_chat()`** (and on load **error**); avoids stale **`RenderSourceView`** after new session.
- 2026-04-08 — **Proposed code:** **`abort_scroll_drain`**, **`scroll_drain_idle` / `scroll_pending_idle`**, **`switch_to_session` + `catch`** as **Vala** blocks; trimmed architecture prose.
- 2026-04-08 — **`ChatWidget.restoring_session`**: concrete before/after in **Restore flag**; code uses **`internal bool … { get; private set; default = false; }`**.
- 2026-04-08 — **FIXED:** **`RenderSourceView.scroll_bottom`**: **`try_again`**, single defer for **`!get_realized()`** and **`upper < 10`**; status **FIXED (direct)**; doc updated with merged code, **Fix applied** table, conclusions; optional queue design remains future-only.
