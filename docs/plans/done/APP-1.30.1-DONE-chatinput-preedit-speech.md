# 1.30.1 — ChatInput OS speech / IME preedit height

> Landed. Index: [`APP-1.0-summary.md`](../APP-1.0-summary.md).

**Status:** **DONE** — composer grows during IME / Sherpa ONNX preedit (`libollmchatgtk/ChatInput.vala`). Archived 2026-09-01.

**Parent:** [`APP-1.30-DONE-chat-input-composer.md`](APP-1.30-DONE-chat-input-composer.md)

**Related:** [`APP-6.2-speech-to-text.md`](../APP-6.2-speech-to-text.md) — composer mic starts Sherpa ONNX listen (not this plan).

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows `docs/coding-standards.md`

---

## Purpose

- **🔷** `✅` OS speech-to-text (and any IME composing text) into the composer `Gtk.TextView` must grow the field as the utterance wraps.
- **🔷** `✅` Wire this in the `ChatInput` constructor. `ScrolledView` already owns height via `queue_fit()`.
- **🔷** `✅` Call `this.scrolled.queue_fit()` when preedit changes so height refits without waiting for `buffer.changed`.
- **ℹ️** Preedit is not in `Gtk.TextBuffer` until commit. `ScrolledView` only auto-fits on `buffer.changed`.
- **💩** `✅` Use `Gtk.TextView.preedit_changed` (existing IM). Do not add a second `Gtk.IMMulticontext`.
- **💩** `✅` Track `has_preedit` so the placeholder does not bounce back on the idle `lines_changed(0)` from an empty buffer.

---

## Current behaviour

- **ℹ️** `ScrolledView.set_child` binds `buffer.changed` → Idle `buffer_change` → `content_height` + `lines_changed`.
- **ℹ️** `ChatInput` sets `this.placeholder.visible = lines == 0` and compact/expanded chrome from `lines`.
- **ℹ️** Speech / IME composing text is drawn as preedit. Buffer stays empty until commit. Fit never runs. Placeholder stays up.

---

## Proposed behaviour

- **🔷** During composing, composer height follows layout (`queue_fit` → yrange).
- **💩** Placeholder hides while `has_preedit` is true, even if `lines == 0`.
- **💩** Compact chrome (side play) stays until the buffer has committed text. Height may still grow beside the play button.
- **🚫** Move play to the footer while wrapping preedit (empty buffer, `lines` still 0). User: height already works; no extra chrome.

Intro: edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

---

### 1. `libollmchatgtk/ChatInput.vala` — field `has_preedit`

**Why:** `lines_changed(0)` after `queue_fit` would show the placeholder again unless both handlers share this flag.

**Where:** class fields, after `syncing`.

**Depends on:** none.

#### Add — after `private bool syncing = false;`

```vala
		private bool has_preedit = false;
```

---

### 2. `libollmchatgtk/ChatInput.vala` — `ChatInput()` `lines_changed`: keep placeholder down during preedit

**Why:** Idle `buffer_change` still sees `end_off == 0` and emits `lines_changed(0)`.

**Where:** `ChatInput()` — first line of the `this.scrolled.lines_changed.connect` lambda.

**Depends on:** §1.

#### Remove
```vala
				this.placeholder.visible = lines == 0;
```

#### Replace with
```vala
				this.placeholder.visible = lines == 0 && !this.has_preedit;
```

---

### 3. `libollmchatgtk/ChatInput.vala` — `ChatInput()`: `preedit_changed` → placeholder + `queue_fit`

**Why:** Hide placeholder immediately (fit is Idle). Ask `ScrolledView` to remeasure so wrapping preedit grows height.

**Where:** `ChatInput()` — after `this.scrolled.lines_changed.connect(…);` closes, before `var keys = new Gtk.EventControllerKey();`.

**Depends on:** §1, §2.

#### Add — after the `lines_changed.connect` lambda, before the Ctrl+Enter `EventControllerKey`

```vala
			this.text_view.preedit_changed.connect((preedit) => {
				this.has_preedit = preedit.length > 0;
				this.placeholder.visible = !this.has_preedit && this.buffer.get_char_count() == 0;
				this.scrolled.queue_fit();
			});
```

---

## LLM notes

- **🚫** `SpeechExtension` class, `set_data_full`, or a new file.
- **🚫** Second `Gtk.IMMulticontext` / `EventControllerKey.set_im_context`.
- **🚫** `retrieve_surrounding` (TextView already owns IM).
- **🚫** `widget == null` / `scrolled == null` guards. `ChatInput` owns these.
- **🚫** New methods (`on_preedit_changed`, helpers).
- **🚫** Change `ScrolledView` or the Ctrl+Enter key controller.
- **🚫** Move play to the footer during wrapping preedit (user: height already works).
