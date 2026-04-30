# OPEN: Crash in `ChatView.clear` — `gtk_text_view_set_buffer` / GLib assertion (`g_assertion_message_expr`)

**Status: OPEN**

**Related:** `docs/plans/done/6.10-DONE-markdown-gtk-render-order-history-repro.md` (same GTK text stack / buffer invariants family).

## Problem

Process **aborts** inside GTK / GLib during **`gtk_text_view_set_buffer`** → **`g_object_unref`**, stack through **`oll_mchat_gtk_chat_view_clear`** (`ChatView.clear`), **`chat_widget_clear_chat`**, **`switch_to_session`**.

Often triggered when the user chooses **“start new chat with this text”** on a framed block (**`MarkdownGtk.Render.start_new_chat_requested`** → **`ChatWidget.start_new_chat_with_text`**), i.e. **`switch_to_session`** runs **`clear_chat`** immediately.

**Expected:** Clearing the chat tears down **`Gtk.TextView`** / **`Gtk.TextBuffer`** without GTK assertions.

**Actual:** **`g_assertion_message_expr`** along **`gtk_text_view_set_buffer`** (e.g. when nested fenced markdown had been rendered inside a **`RenderSourceView`** — **`nested_markdown_render`** hypothesis; **not confirmed resolved**).

## Root cause

GTK requires **`Gtk.TextMark`** removal from a buffer before that buffer or its **`Gtk.TextView`** is finalized. **`Table.set_renderer_to_fake`** documents the same class of failure (**`gtk_text_view_set_buffer` / mark_table**):

```76:79:libocmarkdowngtk/Table.vala
			// Leaving a real table cell: drop GtkTextMarks on its buffer before we orphan TopState.
			// Otherwise gtk_text_view_set_buffer / buffer finalize hits mark_table assertion (GTK).
```

**Historical `MarkdownGtk.Render.clear()` order** (failure mode):

1. **`childview = null`**
2. **`source_view_handlers.clear()`** — finalized **`RenderSourceView`** while nested **`MarkdownGtk.Render`** could still hold **`TopState`** marks on nested buffers
3. **`end_block()`** — **`delete_marks_recursive()`** only on the **main** render path **after** nested widgets could already be torn down.

## Attempted change 1 — `MarkdownGtk.Render.clear()` order

**Files:** `libocmarkdowngtk/Render.vala` (**`clear()`**), `libocmarkdowngtk/RenderSourceView.vala` (**`nested_markdown_render`** **`internal`**)

Reorder teardown: **`on_link_leave()`**; for each **`source_view_handlers`**, **`nested_markdown_render.clear()`** then null; **`childview = null`**, **`end_block()`**, **`source_view_handlers.clear()`**.

**Rollback:** Restore the previous **`clear()`** ordering (see git history on **`Render.vala`** around **`clear()`**).

---

## Attempted change 2 — `RenderSourceView.end_code_block()` after nested markdown ends (2026-04-28)

**Problem this targets:** After a fenced **markdown** block finishes, **`end_code_block()`** did **`nested_markdown_render.flush()`** then **`nested_markdown_render = null`**. **`flush()`** only drains **`Parser`** — it does **not** call **`delete_marks_recursive()`**. Marks stayed on buffers inside **`rendered_box`**, but the **`MarkdownGtk.Render`** reference was dropped, so **`ChatView.clear()`** → **`Render.clear()`** could no longer run **`nested_markdown_render.clear()`** on that frame (pointer already **null**) → teardown still hit **`gtk_text_view_set_buffer`** / **`mark_table`**.

**Fix:** In **`RenderSourceView.end_code_block()`**, after **`flush()`**, call **`nested_markdown_render.clear()`**, then null (same teardown as chat clear, before widgets are destroyed later).

**File / location:** `libocmarkdowngtk/RenderSourceView.vala` — block **`if (this.nested_markdown_render != null)`** in **`end_code_block()`** (after **`code_block_ended`**).

**Rollback (revert only change 2):** Delete **`this.nested_markdown_render.clear();`** and the three-line comment above it (parser / **`clear()`** / bug-doc reference).

Restored shape:

```vala
if (this.nested_markdown_render != null) {
    this.nested_markdown_render.flush();
    this.nested_markdown_render = null;
    GLib.Timeout.add(200, () => {
        /* existing timeout body unchanged */
    });
}
```

**Git:** To revert this attempt only:  
`git checkout HEAD -- libocmarkdowngtk/RenderSourceView.vala` (or `git revert <commit>` if committed alone).

Leave this doc **OPEN** until the repro above is exercised without abort.

## reproduction / verification

1. **`ninja -C build`** relevant targets.
2. Assistant message with a **frame** whose body uses **nested fenced markdown**; trigger **start new chat with this text** (or **`switch_to_session`** → **`clear_chat`**).
3. Session/history switches with large markdown + tables + code blocks.

Closing criteria: stable manual runs without abort; stack no longer implicates **`gtk_text_view_set_buffer`** on these paths.

## Follow-ups

- **`6.10`** **`gtk_text_buffer_apply_tag`** (wrong-buffer iters): separate invariant; compare stacks if both appear.

---

## Debug added — compare streaming vs restore paths (2026-04-28)

**Purpose:** isolate widget/renderer differences between **live streaming** (`initialize_assistant_message` calls `renderer.start()` immediately; `is_streaming` may stay true until finalize) and **history restore** (`append_complete_assistant_message` sets `is_streaming = false` and does **not** call `renderer.start()` until `start_block_direct()`).

**Code:** `libollmchatgtk/ChatView.vala`

| Location | What it logs |
|----------|----------------|
| End of `initialize_assistant_message` | After `renderer.start()`, `is_streaming` and `response.done` |
| After restore sets `renderer.is_streaming = false`, before processing message | `thinking_len`, `content_len` |
| Start of `clear()` | `is_assistant_message`, `content_state` (enum int), `renderer.is_streaming` |

**How to run:** `ollmchat --debug` (routes `GLib.debug()` via `ApplicationInterface.debug_log`; `G_MESSAGES_DEBUG` alone is not sufficient).

**Compare:** Capture stderr or `~/.cache/ollmchat/ollmchat.debug.log` for (A) stream a reply then clear/switch session, vs (B) restore session then clear — diff the three lines above.

**Remove:** Delete these `GLib.debug()` calls once the root cause is fixed and verified (per bug-fix process).
