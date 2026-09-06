# FIXED: SortedList finalize double-disconnects signal handlers

**Status:** ✔️ FIXED — await re-smoke ✅

**Started:** 2026-09-06

**Process:** `docs/bug-fix-process.md`

**Package / area:** `liboccoder/List/SortedList.vala` (surfaced by `oc-test-source-diff` → `SourceView` → `Approvals`)

---

## Problem

🔷 Boot `oc-test-source-diff` → two GLib-GObject CRITICAL:

`instance '…' has no handler with id '357'` / `'358'`

---

## Evidence

✔️ `--debug-critical` + gdb:

```
g_signal_handler_disconnect
← SortedList.finalize (SortedList.vala:91)
← gtk_single_selection_set_model
← Approvals.activate_project(project=null)
← Approvals / SourceView construct
```

---

## Root cause

✔️ `~SortedList` manually disconnected handlers that GObject already auto-removed when the instance died (Vala instance-method `.connect`).

---

## Fix applied

✔️ Removed `~SortedList` manual disconnects (and unused handler id fields).

✔️ `Approvals` ctor: only call `activate_project` when a project is already active (skip needless empty→empty replace).

---

## Changelog

- ✔️ 2026-09-06 — Stack confirmed; destructor removed; smoke with `--debug-critical` clean.
