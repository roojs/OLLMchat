# 2.6.6 FUTURE — run_command VTE

> **Do not update `docs/plans/TOOLS-1.0-summary.md` for this plan.**

> Split from `TOOLS-2.6.4-URGENT-run-command-stop-live-tail-spill.md`. Done Stop/tail/frame: [`done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md`](done/TOOLS-2.6.4-DONE-run-command-stop-and-tail.md). Timeout / live / spill / libsecret: [`TOOLS-2.6.5-run-command-timeout-live-spill.md`](TOOLS-2.6.5-run-command-timeout-live-spill.md).

**Status:** **⏳** **FUTURE** — parked. Do **not** implement unless the user explicitly green-lights this file.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/2.6-DONE-run-terminal-command-tool.md`](done/2.6-DONE-run-terminal-command-tool.md)

**Precedent:** RooTerm `app.RooTerm/src/Terminal/Local.vala` (`Vte.Terminal.spawn_async`). Only if this plan is approved.

---

## Purpose

- **🔷** `⏳` Optional real PTY in the live tool frame after **2.6.5** (timeout, bounded live UI, spill) already works on the pipe path.
- **🔷** We may never do this. Heavy (PTY, bwrap argv, seccomp `child_setup`, meson/debian).
- **ℹ️** **2.6.4** already shows Stop + bold header in `ChatWidget` `tool_frame` via `client.run_tool.start` / `client.run_tool.end`. **2.6.5** is meant to add live tail + spill **without** a terminal widget.

---

## If approved later

- **🔷** GTK frame body becomes VTE. Keep bold tool header + Stop.
- **🔷** Same process-group kill / timeout / spill contracts as **2.6.4** / **2.6.5**.
- **ℹ️** History still does not resurrect a live VTE — persist the tail/spill fence.
- **ℹ️** `ChatView.add_widget_frame` is already used by `tool_frame`.
- **💩** Spawn via `Vte.Terminal.spawn_async` (RooTerm `Local.spawn`) vs pipe-and-`feed()`. Only relevant if this plan is approved.
- **💩** New `libollmchatgtk/CommandFrame.vala` + `dependency('vte-2.91-gtk4')` Linux-only — only if approved.
- **🔷** `⏳` **Linux GTK** only. **Windows:** no VTE. **Android:** do not add `vte` to the meson cut; `run_command` stays unregistered.

---

## Meson / debian — only if this plan is approved

**Where:** `libollmchatgtk` Linux meson; `debian/control` Build-Depends.

- **ℹ️** `dependency('vte-2.91-gtk4')` on `libollmchatgtk` for Linux only.
- **ℹ️** `libvte-2.91-gtk4-dev` in debian.

---

## LLM notes

- **🚫** Do not implement this plan or add VTE meson/debian deps unless the user explicitly approves this file.
- **🚫** Do not add `CommandFrame.vala` while implementing **2.6.5**.
- **🚫** Do not put VTE in `liboctools`.
- **🚫** Do not `dependency('vte-2.91-gtk4')` as required on Windows or Android meson.
- **🚫** Do not register `run_command` on Android in this plan.
- **🚫** Do not restore a live VTE from history JSON.
- **🚫** Do not design **2.6.5** to require a PTY.
