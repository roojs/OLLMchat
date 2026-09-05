# 4.2.3.4 — SourceView diff Phase 3: view pending file

**Status:** **⏳** stub — design settled in parent; fences after Phase 2 lands

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md)

**Depends on:** [`CODER-4.2.3.2`](CODER-4.2.3.2-source-view-diff-db.md) · [`CODER-4.2.3.3`](CODER-4.2.3.3-source-view-diff-render.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

**Next:** Phase 4 [`CODER-4.2.3.5`](CODER-4.2.3.5-source-view-diff-approval.md)

---

## Purpose

- 🔷 When user opens / focuses a **pending-approval** file, build **`new OLLMfiles.Diff.Differ(V_backup, V_disk)`** and call **`SourceView.show_diff(differ)`**.
- 🔷 **V_backup** = `file_history.backup_path` contents; **V_disk** = current buffer / disk.
- 🔷 Active chunk = newest pending **`file_history`** (`reviewed=0`) for that path.
- 🔷 **`clear_diff`** when file leaves pending (whole-file approve / reject as shipped) or user opens a non-pending file.
- 🔷 Changed-files / **`Approvals`** bar still choose which file is under review (shipped).
- 🔷 ⏳ Add **Remove / Replace / Add** fences here after Phase 2 is ✔️.

---

## Likely touch points (names only)

- ℹ️ `liboccoder/SourceView.vala` — call `show_diff` / `clear_diff` from open/focus paths
- ℹ️ `liboccoder/Approvals.vala` — pending selection already opens file
- ℹ️ Daemon / client — read backup text for `backup_path` (may need a small read RPC or client `GLib.FileUtils.get_contents` if path is local)

---

## LLM notes

- 🚫 Per-hunk approve / reject (Phase **4**).
- 🚫 Carry-forward / stacked-edit merge UI.
- 🚫 Invent Vala fences until Phase 2 is implemented and this stub is expanded.
