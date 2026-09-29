# 4.2.3.5.4 — Diff wire and cache model

**Status:** **⏳** design — [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md), [`4.2.3.5.6`](CODER-4.2.3.5.6-source-view-diff-approval-calls.md), [`4.2.3.5.7`](CODER-4.2.3.5.7-source-view-diff-resync.md)

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Supersedes:** [`done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) — do not apply that plan

**Phases:** [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md) diff items · [`4.2.3.5.6`](CODER-4.2.3.5.6-source-view-diff-approval-calls.md) approval · [`4.2.3.5.7`](CODER-4.2.3.5.7-source-view-diff-resync.md) resync

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) is superseded. One plan per phase: [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md), [`4.2.3.5.6`](CODER-4.2.3.5.6-source-view-diff-approval-calls.md), [`4.2.3.5.7`](CODER-4.2.3.5.7-source-view-diff-resync.md). This file is the design.
- 🔷 Two sides: `ollmfilesd` holds the texts. The desktop paints. Start from what crosses the wire.
- 🔷 The client computes the diff today. That is the wrong side.
- 🔷 The daemon already has the backup in the cache. Review data should come from that cache.
- 🔷 Approval must not ship large bodies back. The server already holds the rows and the texts.
- 🔷 `show_pending_diff` does not read the backup. That call runs `Differ` on the daemon, creates one diff-item row per hunk, and returns the array of those rows.
- 🔷 One hunk sends only the decision for that diff item. That row applies the change.
- 🔷 The menu that covers every diff item on the file is `OLLMfilesd-FileHistory.decide`. One method. The action says accept, reject, or reset. Individual acceptance stays on the diff item.
- 🔷 A save after the user has edited the file means the diff items are stale. Diff update, then re-render and refill. Resync everything.
- 💩 This file stays the wire design. Each phase is its own plan. No Vala fences here.

---

## What is already on disk

The daemon wrote these before the editor opens anything.

```
file_history                         one agent write
  id, path, filebase_id
  backup_path  →  cache file
  reviewed      0 until the chunk is closed

~/.cache/ollmchat/edited/{date}-{history id}-{filename}
  full project text from before that write

project file on the daemon
  full text after that write
  client loads it with File.read (RPC-File.read)

file_diff_part                       empty until a hunk is decided
  file_history_id, part_index, accepted, decided_at
```

- ℹ️ Backup path is built in `ollmfilesd/FileHistory.vala` `create_backup`.
- ℹ️ `file_diff_part` is created and unused. `ollmfilesd/FileDiffPart.vala`.

---

## Open a pending file — wire

The project file comes from the daemon. So does the backup. The desktop then diffs the two full texts.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
ReviewFiles.refresh
  RPC-Folder.fetch_pending_approvals
    project path, since id          →
                                    ←  FileWithHistory list
                                       path, backup_path, ids
                                       no file text

SourceView.open_file
  File.read
    RPC-File.read(project path)     →
                                       reads the project file
                                   ←  File row
                                      + entire project text in msg
                                       editor buffer filled from that

show_pending_diff   (only if pending)
  RPC-File.read
    backup_path                 →
                                    reads the cache file
                                ←  File row tagged along
                                   + entire backup in msg
  Differ(backup, editor text)
    patches stay on the desktop        (no wire)
```

- 🔷 `File.read` is the client load. `RPC-File.read`. The daemon reads the path. The client does not. `libocfiles/File.vala` `read`. Save is already `File.rpc_write`. Reload is already `File.read` (`ProjectManager.reload_file_from_disk`).
- ℹ️ `SourceView.open_file` and `refresh_file` still call `buffer.read_async`. `GtkSourceFileBuffer.read_async` then reads `GLib.File.new_for_path` on the client. That local read is the wrong path. `liboccoder/SourceView.vala`, `liboccoder/GtkSourceFileBuffer.vala`.
- ℹ️ `FileWithHistory` is the pending-list row. `backup_path` is only a path string. `ollmfilesd/FileWithHistory.vala` `pending`.
- ℹ️ `SourceView.show_pending_diff` is the diff. It calls `RPC-File.read` with `backup_path`, keeps `response.msg`, ignores the `File` in `retval`, then `new OLLMfiles.Diff.Differ(v_backup, gtk_buffer.text)`. `liboccoder/SourceView.vala`.
- ℹ️ `RPC-File.read` always attaches a `File` row beside the body. For a cache path that row is `id = -1`. The desktop throws it away. `ollmfilesd/File.vala` `read`.
- 🔷 Two full texts cross the wire: the project file, then the backup. The backup call is the extra one. The cache file is already on the daemon. The desktop only needs the hunks.

---

## Open a pending file — what it should do

Same open. `show_pending_diff` does not read the backup. The file server returns the stored diff items, or runs `Differ` and stores them. Each item includes its hunk text.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
ReviewFiles.refresh
  RPC-Folder.fetch_pending_approvals
    project path, since id          →
                                    ←  FileWithHistory list
                                       path, backup_path, ids
                                       no file text

SourceView.open_file
  File.read
    RPC-File.read(project path)     →
                                       reads the project file
                                   ←  File row
                                      + entire project text in msg
                                       editor buffer filled from that

show_pending_diff   (only if pending)
  RPC (pending history id)        →
                                    stored rows, if this history has them
                                    else Differ(cache backup, project file)
                                         and the file server stores them
                                ←  array of diff items
                                   each item includes its hunk text
  hang that text on the in-memory item
  paint bands and colours from the array
  backup file stays on the daemon      (no wire)
```

- 🔷 `show_pending_diff` is an RPC. It does not call `RPC-File.read` on `backup_path`.
- 🔷 The `parts` request is the trigger. The diff itself is `FileHistory.rebuild_parts`. Inputs are the cache backup and the project file.
- 🔷 No rows yet: `Differ`, store the rows, set `hunk_remove`, `hunk_add`, and the line range on the objects, and remember them.
- 🔷 A later `parts` in the same process returns those objects only when the project file's modification stamp still matches the stamp captured when that list was diffed. The history id alone is not enough. Settled in [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md).
- 🔷 Rows already in the table, with no remembered objects: `checksum` is still on the row. The hunk text is not.
- 💩 Do not match those rows by `part_index`.
- 🔷 `FileDiffPart.compare` checks one stored part against another file part and returns an int. `0` neither. `1` line numbers only. `2` checksum only. `3` both.
- 🔷 A later diff indexes stored parts by start line and `compare`s each to the new part. `3` keeps the row. `1` replaces the hunk text and clears the decision. `2` keeps the decision and writes the new line range. `0` deletes that row and inserts the new part. A stored part with no new part at its start line is deleted. [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md).
- 🔷 The diff item holds `hunk_remove` and `hunk_add`. Those strings are properties on the object that comes down the wire. They are not database columns. No `+` or `-` prefix. The line range is on the object too. Counts come from the range.
- 🔷 The file server writes the diff items to disk and is in charge of that store. `hunk` is not in that row. A later open sets the text on the object and returns it.
- 🔷 The client hangs that text on the diff item in memory. The client does not write diff items.
- ℹ️ `file_diff_part` today is only `id`, `file_history_id`, `part_index`, `accepted`, `decided_at`. No hunk text. Rows are unused. `ollmfilesd/FileDiffPart.vala`.
- 🔷 Settled in [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md). The table is `file_diff_part`. `hunk_remove` and `hunk_add` are properties on that object, not columns. `accepted` `0` is undecided, `1` accepted, `-1` rejected. `OLLMfilesd-FileHistory.parts` takes the `file_history` id.
- 🔷 The review diff belongs with the file server. Move `Differ`, `Patch`, and `PatchApplier` out of `libocfiles` into `ollmfilesd` when that is the only user.
- 💩 Not this phase. Still used from `SourceView.show_diff`, `ReviewBar`'s `Differ` / `Patch` API, `examples/oc-diff.vala`, and `examples/oc-test-source-diff.vala`. Symlink until those are gone.

---

## Save while a review is open

The user edits the file after the diff items exist, then saves. Those hunks no longer match the project file. Diff update calls `FileHistory.rebuild_parts`. The desktop throws away the old paint and refills from the new array. The rows stay.

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
                                  ←  the new array
  clear bands and overlay
  refill from that array
  backup file stays on the daemon      (no wire)
```

- 🔷 Save writes the project file. The diff items from the earlier `show_pending_diff` are stale.
- 🔷 Diff update calls `FileHistory.rebuild_parts`. Cache backup against the project file just saved. The rows stay.
- 🔷 The reply is the new array. The desktop re-renders and refills everything from it.
- 💩 Same return shape as `show_pending_diff`. One history id in. The array comes back.

---

## Approval call — superseded

Not built. [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) sent one hunk through `FileHistory.decide`, re-read both full texts, and replied with a `File` row. [`4.2.3.5.6`](CODER-4.2.3.5.6-source-view-diff-approval-calls.md) replaces that.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
FileHistory.decide
  history id, part index, action     →
                                       read project file      (full text)
                                       read cache backup      (full text)
                                       read hunk files        (full text each)
                                       Differ again
                                       maybe rewrite project file
                                   ←  whole File row
                                      (client method discards it)

after reject, or reset of a reject
  File.read                          →
                                   ←  entire project text again
```

- ℹ️ Planned hunk file is not a patch. It is another copy of the full project text, written on the first Accept or Reject, under `edited/parts/`. `FileDiffPart.path`.
- ℹ️ Planned `decide` reply is `retval = File`. `libocfiles/FileHistory.decide` does not read that retval.

---

## Approval call — what it should do

Individual acceptance is a call on the diff item. The menu that covers every diff item on the file is `OLLMfilesd-FileHistory.decide`.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
one hunk — Accept / Reject / Reset on the bar
  diff item
    diff-item id, approval          →
                                      that row applies it
                                      accept: project file stays
                                      reject: undo this hunk
                                      reset:  reverse that decision
                                  ←  that same row, updated
  bar repaints that one item

menu — Accept file changes
       Reject file changes
       Reset
  OLLMfilesd-FileHistory.decide
    history id, action              →
                                      action is accept, reject, or reset
                                      applied to every diff item
                                      on that history

backup and project text stay put        (no wire)
```

- 🔷 One hunk goes through the diff item. The request is that item and the approval. That item makes the adjustment.
- 🔷 **Accept file changes**, **Reject file changes**, and **Reset** are one method: `OLLMfilesd-FileHistory.decide`. The action is the difference. It is not a separate accept method and reject method.
- 🔷 That call covers every diff item on that history. It does not call the diff item once per hunk.
- 🔷 The daemon does not run `Differ` again. The hunk text is already on the object from `show_pending_diff`.
- ℹ️ The menu labels are in `liboccoder/Diff/ReviewBar.vala`. Today they only flip in-memory hunk decisions.
- ℹ️ Today the whole-file wire is two methods, `RPC-FileHistory.rpc_approve` and `RPC-FileHistory.rpc_revert`. Each sends `path` and `history id`. `libocfiles/FileHistory.vala`, `ollmfilesd/FileHistory.vala`.
- 💩 **Accept changes to all files** and **Reject changes to all files** are `decide` once per file. Not a new call.
- 💩 The hunk reply is that one updated row. The desktop adjusts the editor from the hunk it already has.

---

## Call prefix

`RPC-File` is the wrong prefix for these calls. The daemon class is `OLLMfilesd-File`. The hyphen joins the namespace and the class. The dot is only the method.

```
today                         should
RPC-File.read                 OLLMfilesd-File.read
RPC-File.rpc_write            OLLMfilesd-File.rpc_write
RPC-FileHistory.rpc_approve   OLLMfilesd-FileHistory.decide
RPC-FileHistory.rpc_revert    OLLMfilesd-FileHistory.decide
```

- 🔷 Hyphen between `OLLMfilesd` and the class. Dot before the method.
- 🔷 `RPC-` stays for internal calls such as `RPC-Daemon.hello`.
- 🔷 `rpc_approve` and `rpc_revert` become one `decide`. The action argument is accept, reject, or reset.
- ℹ️ Registered today in `ollmfilesd/File.vala` `rpc_register` and `ollmfilesd/Application.vala` as `RPC-File`. Methods: `read`, `exists`, `fetch`, `apply_permissions`, `register`, `changed.check`, `rpc_write`, `rpc_delete`, `ast_lookup`, `ast_summarize`.
- 💩 Rename the whole `RPC-File` prefix in one pass with the callers. This plan does not do that rename.
- 💩 `decide` here is the menu for every diff item on that history. It is not the per-hunk `decide` in the superseded plan. The individual hunk call stays on the diff item. Its method name is still open.

---

## Working backwards

What the bar needs in order to paint, and who should own it.

```
ReviewBar bands + editor colours
  need: the diff-item rows for this history
        editor already has the project text from File.read

show_pending_diff
  ollmfilesd runs Differ
  writes one row per hunk
  returns that array
  backup stays on the daemon
```

- 🔷 Diff runs on `ollmfilesd`. The desktop paints the returned rows.
- 🔷 Pending list can keep shipping `FileWithHistory` (paths and ids only). The body of the backup does not ride along.
- ℹ️ The show call and the row shape are in **Open a pending file — what it should do**.

---

## LLM notes

- 🚫 Implement the per-hunk `OLLMfilesd-FileHistory.decide` from the superseded plan. `decide` is the menu for every diff item on that history.
- 🚫 A hunk file that stores the full project text.
- 🚫 Client `Differ` on the backup body as the long-term review path.
- ℹ️ Touch points: `liboccoder/SourceView.vala` `show_pending_diff`, `ollmfilesd/File.vala` `read`, `ollmfilesd/FileWithHistory.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`, `libocfiles/Diff/Differ.vala`.
