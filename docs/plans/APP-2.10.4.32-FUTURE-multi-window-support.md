# 2.10.4.32 — Multi-window Config2 support (FUTURE)

> **Do not update `docs/plans/APP-1.0-summary.md` for this plan.**

**Status:** ⏳ **FUTURE** — no code until a second GTK window is a real product feature

ℹ️ Checklist: `docs/guide-to-writing-plans.md`.  
ℹ️ Parent: [`FILES-2.10.4.0-summary.md`](FILES-2.10.4.0-summary.md).  
ℹ️ Prerequisite (DONE): [`done/2.10.4.7-DONE-active-project-file-outside-db.md`](done/2.10.4.7-DONE-active-project-file-outside-db.md) — single-window `Config2.windows[uuid]` + `window_config()` already ship.

---

## Purpose

- 🔷 When a **second** GTK window is created: allocate `GLib.Uuid.string_random()`, insert `Config2.windows[id]`, bind that window’s `ProjectManager` to that row.
- 🔷 Each window keeps its own in-memory `active_project` / `active_file` (already true per PM instance).
- 💩 Closing a window: keep last `windows` map entry vs delete key — decide at implementation.
- 🚫 Do not add `window_id` on daemon activate RPCs — multi-window is client Config2 only (daemon has no UI “active” after 2.10.4.7 Phase 3).

---

## Why not now

- ℹ️ App only opens one `OllmchatWindow` (`ollmapp/Application.vala`).
- ℹ️ 2.10.4.7 Phase 2 already seeds/reuses a **single** UUID + `Settings.Window` row via `window_config()`.

---

## Starting point (today)

- ℹ️ `OllmchatWindow.uuid` + `window_config()` — if map empty, create UUID; if non-empty and `uuid` unset, reuse **first** entry.
- ℹ️ Factories restore from `window_config().project` / `.file`.
- ℹ️ Persist on `active_project_changed` / `active_file_changed` + agent dropdown.

---

## Work (when product wants multi-window)

1. ⏳ 🔷 Second-window creation path allocates a **new** UUID (do not reuse first entry).
2. ⏳ 🔷 Each window’s PM + agent chrome bind to its own `Config2.windows` row.
3. ⏳ 💩 Close policy: keep vs delete map entry.
4. ⏳ 💩 Decide whether first-entry reuse in `window_config()` remains for the primary window only.

🚫 Do not implement until second window UI exists.

---

## Relationship

| Plan | Role |
| ---- | ---- |
| [`done/2.10.4.7`](done/2.10.4.7-DONE-active-project-file-outside-db.md) | Single-window Config2 + daemon `is_active` slim — **done** |
| [`2.10.4.8`](FILES-2.10.4.8-per-client-project-notifications.md) | Daemon notifications per client project — separate |
