# 4.2.3.5.5 — Diff items on the wire

**Status:** **⏳** proposed — no Vala fences yet

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Design:** [`CODER-4.2.3.5.4-source-view-diff-wire-model.md`](CODER-4.2.3.5.4-source-view-diff-wire-model.md)

**Supersedes:** [`done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) — do not apply its fences.

**Next:** [`4.2.3.5.6`](CODER-4.2.3.5.6-source-view-diff-approval-calls.md) — approval. [`4.2.3.5.7`](CODER-4.2.3.5.7-source-view-diff-resync.md) — resync after save.

**Depends on:**

- [`CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md`](CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md) — **✔️** editor hosts `ReviewBar`. Bulk accept / reject are in-memory stubs.
- [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md) — `file_diff_part`, Flow A–F

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 The file server stores one diff item per hunk, hunk text included, and sends that array down the wire.
- 🔷 Close and open again reloads those active items. The client hangs the text on the in-memory item and paints from it.
- 🔷 The client does not write diff items and does not read the backup.

---

## Load

The file server owns the store. Open returns the active items.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
File.read
  OLLMfilesd-File.read(project path)  →
                                   ←  File row + project text

show_pending_diff
  history id                        →
                                      stored items, if any
                                      else Differ, then store
                                  ←  diff items, hunk text on each
  hang the text on the in-memory item
  paint from that array
  backup stays on the daemon           (no wire)
```

- 🔷 The diff item contains the hunk text. That text goes down the wire with the item.
- 🔷 The file server writes the items to disk. A later open returns the active items, hunk text included.
- 🔷 The client hangs that text on the diff item in memory. The client does not write diff items.
- 🔷 `Differ` runs on `ollmfilesd`, and only when this history has no stored items yet. Inputs are the cache backup and the project file.
- 🔷 `show_pending_diff` does not call `RPC-File.read` on `backup_path`.
- ℹ️ `file_diff_part` today has no hunk text. `ollmfilesd/FileDiffPart.vala`. The daemon cannot link `libocfiles`, so `Differ` still has to be built into `ollmfilesd` the same way `Copyable.vala` is symlinked.
- 💩 The stored row is `file_diff_part` plus the hunk text. Not `edited/parts/…patch` holding the whole project text.
- 💩 Pending is its own state on the row. A row now exists before anyone decides.
- 💩 Call argument is `FileWithHistory.approve_id`. Method name is not chosen.

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md).
- 🚫 A hunk file that stores the full project text.
- 🚫 No row until Accept or Reject. The items exist when the diff is shown.
- 🚫 Client `Differ` on the backup body.
- 🚫 `RPC-File` rename in this plan. New calls use `OLLMfilesd-`. The hyphen joins the namespace and the class. The dot is only the method. `RPC-` stays for internal calls such as `RPC-Daemon.hello`.
- ℹ️ Touch points: `liboccoder/SourceView.vala` `show_pending_diff`, `ollmfilesd/FileDiffPart.vala`, `ollmfilesd/FileHistory.vala`, `libocfiles/Diff/Differ.vala`.
