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
                                      Differ(cache backup, project file)
                                      file server replaces the stored items
                                  ←  the new array, hunk text included
  clear bands and overlay
  refill the in-memory items
  backup stays on the daemon           (no wire)
```

- 🔷 Save writes the project file. Then diff update. Then re-render and refill. Resync everything.
- 🔷 `Differ` runs on the daemon again. Cache backup against the project file just saved.
- 🔷 The reply is the new array. The desktop throws away the old paint and hangs the new text on the in-memory items.
- 🔷 Replacing the stored items drops `FileHistory.live` for that history id. Otherwise the next `parts` returns the objects from before the save.
- 💩 Same return shape as `show_pending_diff` in [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md). The old stored items are replaced.

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md).
- 🚫 Carry a decision forward by matching hunk text inside `OLLMfiles.Diff`. This plan refills the set.
- 🚫 Client `Differ` on the backup body.
- ℹ️ Touch points: `liboccoder/SourceView.vala`, `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/File.vala` `rpc_write`, `libocfiles/Diff/Differ.vala`.
