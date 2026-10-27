# 4.2.3.5.7 — Resync after save

**Status:** done — archived after save resync merged to mainline

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-DONE-source-view-diff-approval.md`](CODER-4.2.3.5-DONE-source-view-diff-approval.md)

**Design:** [`CODER-4.2.3.5.4-DONE-source-view-diff-wire-model.md`](CODER-4.2.3.5.4-DONE-source-view-diff-wire-model.md)

**Supersedes:** [`done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md`](CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) — do not apply its fences.

**Depends on:** [`CODER-4.2.3.5.5-DONE-source-view-diff-items.md`](CODER-4.2.3.5.5-DONE-source-view-diff-items.md) — `FileHistory.parts` and `rebuild_parts`. [`CODER-4.2.3.5.6-DONE-source-view-diff-approval-calls.md`](CODER-4.2.3.5.6-DONE-source-view-diff-approval-calls.md) — approval calls, in the tree.

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 The user edits the file while a review is open, then saves. The stored diff items no longer match.
- 🔷 Diff update runs on the file server. The client re-renders and refills from the new array.
- 🔷 Old and new diffs are separated by `FileDiffPart.compare`, not by scanning a combined hunk.
- 🔷 The first pass indexes the stored parts by start line. Line numbers match and hunks match: that part is unchanged and drops out of the leftover set. The same pass walks the file by the line range.
- 🔷 `rebuild_parts` keeps, updates, or deletes each stored part from `compare`. [`4.2.3.5.5`](CODER-4.2.3.5.5-DONE-source-view-diff-items.md).

---

## Save

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
Save
  buffer.sync_to_file
    File.rpc_write                  →
                                      project file becomes that text

diff update
  FileHistory.parts
    history id                      →
                                      stamp miss
                                      FileHistory.rebuild_parts
                                      cache backup against the project file
                                  ←  the new array
  show_pending_diff clears and refills
  backup stays on the daemon           (no wire)
```

- 🔷 Save writes the project file. Then diff update. Then re-render and refill. Resync everything.
- 🔷 Diff update calls `FileHistory.rebuild_parts`. Same method as a `parts` cache miss. Cache backup against the project file just saved. It does not wipe the rows and insert a new set. `compare` keeps, updates, or deletes each part.
- 🔷 The reply is the new array. The desktop throws away the old paint and hangs the new text on the in-memory items.
- 🔷 `rebuild_parts` writes `FileHistory.live` and `FileHistory.live_stamp` for that history. The save path does not clear those maps.
- ℹ️ The write already in the tree is `buffer.sync_to_file`, which calls `File.rpc_write`. There is no `OLLMfilesd-File.rpc_write`.
- ℹ️ `FileHistory.parts` returns the remembered list only when `mtime_on_disk` still matches `live_stamp`. A miss calls `rebuild_parts`. A save changes that stamp.
- ℹ️ `show_pending_diff` is that `parts` call. If the file is not pending, it returns without painting.
- 🚫 A second diff-update RPC. Save calls `show_pending_diff` again.

---

## Phase 1

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

- 🔷 After a successful save, `show_pending_diff` runs for that file. `parts` sees the new modification time and `rebuild_parts` refills the items.
- ℹ️ The `try` wraps only `sync_to_file`. The resync runs after that call succeeds.

### 1. `examples/oc-test-source-diff/SourceView.vala` — resync the open review after save

**Why:** A save changes the project file. The hunks from the last `show_pending_diff` no longer match. The same paint path loads the new array.

**Where:** `examples/oc-test-source-diff/SourceView.vala` `save_file`, the `sync_to_file` try. Not `liboccoder/SourceView.vala`.

**Depends on:** [`4.2.3.5.5`](CODER-4.2.3.5.5-DONE-source-view-diff-items.md), [`4.2.3.5.6`](CODER-4.2.3.5.6-DONE-source-view-diff-approval-calls.md).

#### Remove

```vala
			try {
				yield this.current_file.buffer.sync_to_file();
				this.current_file.is_unsaved = false;
				
				this.save_current_file_state();
			} catch (Error e) {
				GLib.warning("Failed to save file %s: %s", this.current_file.path, e.message);
			}
```

#### Replace with

```vala
			var file = this.current_file;
			try {
				yield file.buffer.sync_to_file();
			} catch (Error e) {
				GLib.warning("Failed to save file %s: %s", file.path, e.message);
				return;
			}
			file.is_unsaved = false;
			this.save_current_file_state();
			yield this.show_pending_diff(file);
```

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md).
- 🚫 Carry a decision forward inside `OLLMfiles.Diff`. Matching is `FileDiffPart.compare`. An exact match drops that stored part from the leftover set. It does not delete the row.
- 🚫 Client `Differ` on the backup body.
- ℹ️ Touch points: `liboccoder/SourceView.vala`, `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/File.vala` `rpc_write`, `libocfiles/Diff/Differ.vala`.
