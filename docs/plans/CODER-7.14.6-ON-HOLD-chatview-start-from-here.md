# 7.14.6 — “Start from here” control on `ChatView` (task review entry)

**Status:** on hold

**Parent:** `docs/plans/CODER-7.14.6-continue-replay-as-new.md`

**Checklist:** `docs/guide-to-writing-plans.md` — **Checklist for plans**.

**Plan layout / workflow:** `docs/guide-to-writing-plans.md` — **Required shape**, **Discussion style (emoji prefixes)**, **Concrete code proposals**.

---

## Purpose

- **🔷** Offer an explicit **“Start from here”** (or equivalent label) control **on the chat UI**, positioned at **task review entry points** — points where the skills runner begins **task list review / iteration** (the **“Reviewing and updating task list”** / revised-list UX), so the user can trigger **continue-from** behaviour aligned with **`7.14.6`** once the backend hook exists.

---

## Scope

| In scope | Out of scope |
| -------- | ------------- |
| **`ChatView`** (and minimal **`ChatWidget`** glue) for **showing/hiding** a button or **Adw** action row + **signal** emission | Full **`replay_as_new`** / transcript fork implementation (**parent plan**) |
| **One** agreed **call site** (or **two** if both use the **same** API) in **`Runner`** where task review **starts** — only wiring that **reveals** the control and connects **signal → stub or existing agent API** | **New** **`Runner`** **public** methods unless the parent plan already names them |

---

## Discussion

- **🔷** **Task review start points** (initial scope): **`OLLMcoder.Skill.Runner.run_task_list_iteration`** — immediately **before** or **after** the existing **`add_message`** that shows the fenced **“Reviewing and updating task list”** / **“Sending revised task list to LLM”** summary (**`liboccoder/Skill/Runner.vala`**). Each **retry** (**`ir.try_no > 0`**) may count as another **start** — **🔷** confirm: **once per outer iteration** vs **every retry**.
- **💩** Optional later: analogous anchor at **task creation** list-parse (**`send_async`** / **`PhaseEnum.LIST`**) — **not** in scope unless added to **Scope** table after user approval.
- **ℹ️** **`Runner`** does not reference **`ChatView`**; **`liboccoder`** must **not** link **`libollmchatgtk`**. Prefer **`Session`**, **`Manager`** signals, or **`Agent.Base`** hooks already used for **`message_added`** — or **`ChatUserInterface`** extension **only if** it stays **GTK-free** (same pattern as **`scroll_chat_to_message_idx`** sibling plan).
- **⏳** Label/copy: **“Start from here”** vs **“Continue from here”** — match product wording (**🔷** confirm).

---

## Acceptance criteria

- **🔷** At each agreed **task review entry**, the user sees the control **unless** hidden by policy (e.g. **`in_replay`** — **🔷** confirm).
- **🔷** Clicking the control emits a **single** discoverable signal (or **`GLib.Action`**) **`ChatWidget`** / **`Window`** can connect to; **no-op stub** is acceptable until **`7.14.6`** cut-point API lands.
- **🔷** **`ChatView.clear()`** removes/hides the control so restores **do not** leak stale buttons.

---

## Concrete code proposals

Intro: verify fences against the tree before apply.

### Files touched (planned)

| # | File |
|---|------|
| 1 | `libollmchatgtk/ChatView.vala` |
| 2 | `libollmchatgtk/ChatWidget.vala` |
| 3 | `liboccoder/Skill/Runner.vala` *(or bridging file named in revision)* |

---

### 1. `libollmchatgtk/ChatView.vala` — banner + signal

#### Discussion

- **💩** Implementation options (**pick one** in approved fences):
  - **A)** Thin **`Gtk.Box`** (**horizontal**) above **`text_view_box`** (sibling before transcript stack) containing **`Gtk.Button`**.
  - **B)** **`Adw.ButtonRow`** / **`Adw.ActionRow`** if **`ChatView`** already links **`libadwaita`** — verify **`meson.build`** before choosing.

#### Add — fields (after existing **`widgets`** / **`idx_to_widget`** — **Keep** anchor from tree)

Purpose: hold **`Gtk.Widget?`** banner container or button; nullable when unused.

```vala
		private Gtk.Widget? continue_from_here_banner = null;

```

#### Add — signal (class scope, near other **`public`** API)

```vala
		public signal void continue_from_here_clicked();

```

#### Add — methods

Placement: near **`clear()`** / **`scroll_to_idx`** — exact **`Keep`** anchor during implementation.

Purpose: create/locate button once; **`hide`** when **`visible = false`**.

```vala
		public void set_continue_from_here_visible(bool visible)
		{
			// Allocate banner on first show; parent next to transcript per § Discussion; map visible → show/hide/unparent.
		}

```

*(Flesh out the method body in the implementing PR — **no** compile-empty stubs landing on **`main`**.)*

#### Add — inside **`clear()`** — after **`idx_to_widget`** / **`widgets`** clears (**Keep** anchor from **`7.14.6`** parent)

Purpose: destroy or hide **`continue_from_here_banner`** and clear reference.

---

### 2. `libollmchatgtk/ChatWidget.vala` — optional forward + connection

#### Add — **`ChatWidget`** ctor or **`constructed`** (**Keep** anchor)

- **`this.chat_view.continue_from_here_clicked.connect(...)`** — forward to **`Manager`** signal, **`Window`** callback, or **`Session`** (**🔷** choose lowest coupling approved with parent **`7.14.6`**).

---

### 3. `liboccoder/Skill/Runner.vala` — show banner at task review entry

#### Keep — **`run_task_list_iteration`**, top of loop body after **`iteration_prompt`** / **`fill_tools`** / **`try_no`** UI messages (**exact anchor from tree**)

#### Add — call **`set_continue_from_here_visible(true)`** via **approved bridge**

The bridge **must not** import **`OLLMchatGtk`** from **`liboccoder`**. Options (**document the chosen one**):

- **💩** **`Session`** gains **`signal void request_continue_from_here()`** implemented in **`libollmchat`** / **`Session`** subclass — **`ChatWidget`** connected in **`ollmapp`**.
- **💩** **`OLLMchat.ChatUserInterface`** gains **`show_continue_from_here(bool)`** — **`Window`** forwards to **`chat_widget.chat_view.set_continue_from_here_visible`**.

---

## Related

- **ℹ️** `docs/plans/CODER-7.14.6-continue-replay-as-new.md` — **`msg_idx`**, **`scroll_to_idx`**, **`replay_as_new`**
- **ℹ️** `docs/plans/done/7.14.6-DONE-progress-tree-click-scroll.md` — sibling **`scroll_to_idx`** wiring (archived)
