# 4.2.3.5.7 — Resync after save

**Status:** **⏳** proposed — no Vala fences yet

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Design:** [`CODER-4.2.3.5.4-source-view-diff-wire-model.md`](CODER-4.2.3.5.4-source-view-diff-wire-model.md)

**Supersedes:** [`done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) — do not apply its fences.

**Depends on:** [`CODER-4.2.3.5.5-source-view-diff-items.md`](CODER-4.2.3.5.5-source-view-diff-items.md) — diff items stored on the file server.

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 The user edits the file while a review is open, then saves. The stored diff items no longer match.
- 🔷 Diff update runs on the file server. The client re-renders and refills from the new array.
- 🔷 Old and new diffs are separated by `FileDiffPart.compare`, not by scanning a combined hunk.
- 🔷 The first pass indexes the stored parts by start line. Line numbers match and hunks match: that part is unchanged and drops out of the leftover set. The same pass walks the file by the line range.
- 🔷 `rebuild_parts` keeps, updates, or deletes each stored part from `compare`. [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md).

---

## Save

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
Save
  OLLMfilesd-File.rpc_write
    path, new text                  →
                                      project file becomes that text

diff update
  history id                        →
                                      FileHistory.rebuild_parts
                                      cache backup against the project file
                                  ←  the new array, remove and add text included
  clear bands and overlay
  refill the in-memory items
  backup stays on the daemon           (no wire)
```

- 🔷 Save writes the project file. Then diff update. Then re-render and refill. Resync everything.
- 🔷 Diff update calls `FileHistory.rebuild_parts`. Same method as a `parts` cache miss. Cache backup against the project file just saved. It does not wipe the rows and insert a new set. `compare` keeps, updates, or deletes each part.
- 🔷 The reply is the new array. The desktop throws away the old paint and hangs the new text on the in-memory items.
- 🔷 `rebuild_parts` writes `FileHistory.live` and `FileHistory.live_stamp` for that history. The save path does not clear those maps.
- ℹ️ [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md) `parts` returns the remembered list only when the project file's modification stamp still matches `live_stamp`. A miss calls the same `rebuild_parts`.
- 💩 Same return shape as `show_pending_diff` in [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md).

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md).
- 🚫 Carry a decision forward inside `OLLMfiles.Diff`. Matching is `FileDiffPart.compare`. An exact match drops that stored part from the leftover set. It does not delete the row.
- 🚫 Client `Differ` on the backup body.
- ℹ️ Touch points: `liboccoder/SourceView.vala`, `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/File.vala` `rpc_write`, `libocfiles/Diff/Differ.vala`.
