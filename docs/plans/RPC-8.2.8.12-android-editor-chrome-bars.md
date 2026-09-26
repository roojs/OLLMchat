# 8.2.8.12 — Android editor chrome and bar placement

**Status:** **⏳** — Phases 1–3 not started

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 14

**Split from:** [`RPC-8.2.8.11-DONE-android-startup-history-bars.md`](done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) Phases 4–6. That plan is closed. Phase 1 here was Phase 4 there. Phase 2 here was Phase 5 there. Phase 3 here was Phase 6 there.

**Depends on:**

- [`RPC-8.2.8.11`](done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) — phone buttons for browser, text editor, and chat. Tablet chat button is in the bar with `visible` false. A click activates the page. The active button is highlighted.
- [`RPC-8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md) — tablet chat stays the left column. `schedule_pane_update` shows or hides the right column.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`. Code fences after each phase is agreed, or when the existing bullets are enough to apply.

---

## Purpose

- **🔷** Editor chrome, where the tablet buttons sit, and moving the pickers to the right.
- **🔷** Each phase below is the whole design for that slice. Read that phase on its own.
- **ℹ️** Startup hello, history when Agent Pi is off, and the phone pickers are [`8.2.8.11`](done/RPC-8.2.8.11-DONE-android-startup-history-bars.md).
- **ℹ️** Still one desktop environment. Home, office, and an online proxy host are [`8.2.8`](RPC-8.2.8-filesd-connections-ui.md) Phase 13.
- **ℹ️** Remote `bash` is [`8.2.8.10`](RPC-8.2.8.10-android-remote-bash.md). Not this plan.

---

## Phase 1 — Editor chrome (`⏳`)

When the text editor is the visible page, the column is four bands, top to bottom.

- **🔷** `⏳` The normal OLLMchat header stays on top.
- **🔷** Under that, a second bar: project dropdown and file dropdown. Those already exist inside the coder (`ProjectDropdown`, `FileDropdown`).
- **🔷** Then the text area.
- **🔷** When review is active, the review bar sits at the bottom of the text area. Not in this slice unless review is already showing there on desktop.
- **ℹ️** Desktop review footer is `liboccoder/Diff/ReviewBar.vala`. The phone reuses that band. It does not invent a second review widget.

---

## Phase 2 — Tablet bar (`⏳`)

- **ℹ️** Tablet `schedule_pane_update` only shows or hides the right column. Chat stays on the left ([`8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md)).
- **🔷** `⏳` The same browser and text-editor buttons from [`8.2.8.11`](done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) Phase 3. The chat button stays in the bar, invisible. A click activates that page and highlights it.
- **🔷** `⏳` Those two buttons sit on the right of the left column's bottom bar, not on its left edge.
- **🔷** Selecting Agent Pi still fills the right column with the editor. The buttons choose browser vs code in that column.
- **ℹ️** Moving the model selector fully left, on phone and tablet together, is Phase 3. This phase only moves browser and code to the right of that left-column bar.

---

## Phase 3 — Pickers on the right (`⏳`)

- **🔷** `⏳` Later, the same bar on phone and tablet: pickers sit on the right, and the model selector moves fully left.
  - Phone: three pickers (browser, text editor, chat).
  - Tablet: browser and code show. The chat picker is in the bar with `visible` false. Chat is the left column.

---

## Suggested order

1. **⏳** Phase 1 — editor chrome (header, project/file dropdowns, text, review bar)
2. **⏳** Phase 2 — tablet bar: browser and code on the right of the left-column bar
3. **⏳** Phase 3 — pickers on the right, model selector fully left

---

## LLM notes

- **🚫** Code Assistant and Skill Runner on Android.
- **🚫** Changing Linux Agent Pi registration.
- **🚫** A left-rail editor toggle.
- **🚫** `Gtk.ToggleButton` for browser, editor, or chat. A click activates the page. The active one is highlighted.
- **🚫** A phone split (editor over a short chat strip) and a draggable sash (`Gtk.Paned`).
- **🚫** A spinner on the chat picker. Running is the fog frames, one wave at a time. Idle is a speech bubble.
- **🚫** More than one desktop environment. That is parent Phase 13.
- **🚫** Registering in-process `Bash` on Android. That is [`8.2.8.10`](RPC-8.2.8.10-android-remote-bash.md).
- **🚫** Reopening [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) or [`8.2.8.11`](done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) for these hunks.
