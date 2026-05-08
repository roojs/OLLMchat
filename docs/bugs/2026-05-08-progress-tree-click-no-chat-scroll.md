# Progress tree: click row does not scroll chat to message

**Status:** OPEN (investigation — no fix approved yet)

**Started:** 2026-05-08

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval. Do not patch symptoms or add defensive guards that hide failure.

**Related plans (context only — not a diagnosis):**

- **`docs/plans/7.14.6-progress-tree-click-scroll.md`** — proposed wiring: pointer/keyboard → **`msg_idx`** → **`scroll_to_idx`** (still **Status: proposed**).
- **`docs/plans/7.14.6-progress-chat-scroll-issues.md`** — tracks **`msg_idx`** / **`scroll_to_idx`** integration and known follow-ups (e.g. Issue 4 **`TreeExpander`** / **`ListItem`**, Issue 5 viewport/`Idle`).

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
- Do not assume **`Gtk.ColumnView.activate`** is the same as “user clicked this row” without verifying (see Discussion in **`7.14.6-progress-tree-click-scroll.md`**).

---

## Attempts / changelog

| Date | Change | Purpose | Result |
|------|--------|---------|--------|
| — | — | — | — |

---

## Conclusions

- **Root cause:** *unknown — do not fill with speculation; update only with log-backed evidence.*
- **Ruled out:** *none yet.*
- **Open questions:** Does the click handler run? Is **`msg_idx`** `-1` or stale for nested/tool rows? Does **`scroll_to_idx`** see the **`idx`** in its map? Is the **`Idle`/bounds path failing silently?

---

## After a verified fix (later)

When fixed: rename with **`FIXED`** in the filename, move to **`docs/bugs/done/`**, strip temporary **`GLib.debug()`** from merged code (note in log if helpful).
