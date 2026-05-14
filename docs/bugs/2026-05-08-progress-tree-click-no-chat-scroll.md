# Progress tree: click row does not scroll chat to message

**Status:** OPEN (investigation — no fix approved yet)

**Started:** 2026-05-08

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval. Do not patch symptoms or add defensive guards that hide failure.

**Related plans (context only — not a diagnosis):**

- **`docs/plans/done/7.14.6-DONE-progress-tree-click-scroll.md`** — archived **done**: pointer/keyboard → **`scroll_to_message`** / **`scroll_to_idx`** (see tree for **`idx_first` / `idx_last`**).
- **`docs/plans/done/7.14.6-DONE-progress-chat-scroll-issues.md`** — archived **done**: **`ProgressItem`** **`message`** binding + **`assign_message`** (historical fences may differ from final **`idx-last`** watcher).

---

## Problem

When the user **clicks a line** in the task **progress tree** (**`ProgressView`** / **`Gtk.ColumnView`** strip), the **chat transcript does not scroll** to the message that row represents.

**Expected:** Clicking a progress row scrolls the chat so the corresponding transcript message is visible (same intent as **`ChatView.scroll_to_idx`** / host **`scroll_to_message`** bridge described in the 7.14.6 plans).

**Actual:** Click does not bring the tied message into view (scroll does not occur or does not land on the correct place).

---

## Reproduction

(To be tightened during investigation — fill in exact steps and build/app invocation.)

1. Open a session where the progress strip shows multiple rows tied to chat messages.
2. Scroll the chat so the message for a given row is **off-screen**.
3. Click that row in the progress tree.
4. Observe whether the chat scrolls to show the message.

**Environment notes:** Record app binary, **`--debug`** usage, and session type (live vs restored) when filing evidence — scroll/index bugs sometimes differ across paths.

---

## Debug strategy (evidence-first — no guessing as fact)

Aligned with **`docs/bug-fix-process.md`** § **a) DEBUG first**:

1. **Establish a reliable repro** — same session, same row, same expected **`msg_idx`** / message identity every time.
2. **Trace the full chain with minimal logging** — only at real boundaries (not hot-loop spam):
   - Pointer/selection path: gesture or **`ColumnView`** handler → **`Gtk.SingleSelection`** / position → resolved **`ProgressItem`** → **`msg_idx`** value.
   - Bridge: **`ChatUserInterface.scroll_to_message(idx)`** (or equivalent) → **`Window`** → **`chat_view.scroll_to_idx(idx)`**.
   - **`ChatView.scroll_to_idx`**: whether it runs, whether **`idx`** is registered in **`idx_to_widget`** (or current map), whether adjustment/scroll calls execute.
3. **Use `GLib.debug()`** per project rules; run the relevant app with **`--debug`** so lines reach stderr (**`G_MESSAGES_DEBUG` alone is not enough** for apps that replace the GLib handler).
4. **Prefer readable debug output** — log **`msg_idx`**, selection position, and whether **`scroll_to_idx`** reports missing registration vs running scroll logic.
5. **Record each experiment** in this file: what changed, what was logged, outcome — so others do not repeat dead ends.
6. **Only after the chain is proven** (where it stops, and **why** — wrong index, handler not connected, expander swallowing clicks, scroll math, timing/idle) → **§ Conclusions** and a **separate** proposed fix for approval — **not** before.

**Explicit non-goals until root cause is known:**

- Do not “fix” by adding null checks or silent fallbacks that mask missing wiring or bad indices.
- Do not assume **`Gtk.ColumnView.activate`** is the same as “user clicked this row” without verifying (see Discussion in **`docs/plans/done/7.14.6-DONE-progress-tree-click-scroll.md`**).

---

## Attempts / changelog

| Date | Change | Purpose | Result |
|------|--------|---------|--------|
| 2026-05-08 | **`idx_map`** / **`scroll_msg`** / **`scroll_idx`** **`GLib.debug()`** only (**`ChatView`**, **`Window`**) — no registration **`set()`** | Prove whether **`idx_to_widget`** gains entries during restore/replay and whether click reaches **`scroll_to_idx`** | See **Conclusions** |

### Capture (stderr, **`--debug`), session restore / replay-style load

Representative lines:

- **`idx_map clear n=0`** — map empty before **`clear()`** wipe (expected at session switch).
- **`idx_map done idx=<n> has=n n=0 tv=GtkTextView`** — repeated for many message indices while hydrating the transcript: **`renderer.current_textview`** is non-null (**`GtkTextView`**), but **`idx_to_widget`** remains **size 0** and **`has=n`** for every **`idx`**. So nothing ever inserts into **`idx_to_widget`** on this path (there is no **`idx_to_widget.set`** in the tree today).
- **`scroll_msg idx=45 has=n n=0`** → **`scroll_idx miss idx=45 n=0`** — progress strip forwarded **`idx=45`**; **`scroll_to_idx`** correctly reports missing registration (**`map_size=0`**).

Unrelated noise in same capture: **`GLib-GIO` IPv6 DNS** / **`Operation was cancelled`** — environment/network; not causal for **`idx_map`**.

---

## Conclusions

- **Root cause (evidence-backed):** **`ChatView.idx_to_widget`** is **never populated** — no registration writes exist in **`libollmchatgtk/ChatView.vala`** (only **`clear()`**). **`scroll_to_idx`** therefore always misses once you rely on the map. Hydration logs show **`tv=GtkTextView`** alongside **`n=0`**, so the gap is **missing map insertion**, not “no widget for that message”.
- **Ruled out (for this repro):** Broken **`msg_idx`** on click — **`idx=45`** reached **`Window.scroll_to_message`** and **`scroll_to_idx`**; **`ProgressView`** pick path ran (**`select position=3`**).
- **Still open for other scenarios:** Live streaming (**`idx_map chunk`** / **`append_assistant_chunk`**) not excerpted here; optional **`scroll_to_idx`** viewport behaviour (**Issue 5**) remains irrelevant until the map registers a widget.
- **Plan doc mismatch (historical):** At investigation time the chat-scroll plan text and **`idx_to_widget`** registration diverged; plans are now archived under **`docs/plans/done/`** (2026-05-13) after implementation work — re-verify current tree before treating this bug as still open.

**Direction update (2026-05-09):** Replace map-based lookup design with widget-index IDs returned by `ChatView` append APIs; replay/live writers set `Message.idx` from returned widget ID. See **`docs/plans/done/7.14.6-DONE-progress-chat-scroll-issues.md`**.

**Next step (when approved to fix, not now):** Implement the widget-index plan; then re-run this repro and verify `scroll_idx` hits by list index.

---

## After a verified fix (later)

When fixed: rename with **`FIXED`** in the filename, move to **`docs/bugs/done/`**, strip temporary **`GLib.debug()`** from merged code (note in log if helpful).
