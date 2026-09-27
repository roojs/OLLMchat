# 4.2.3.5.4 — Diff wire and cache model

**Status:** **⏳** proposed — understanding only, no Vala yet

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Blocks:** [`CODER-4.2.3.5.3-source-view-diff-part-rows.md`](CODER-4.2.3.5.3-source-view-diff-part-rows.md) — part-row fences stay unsigned until this wire model is settled

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 [`4.2.3.5.3`](CODER-4.2.3.5.3-source-view-diff-part-rows.md) is not ready. The hole is the data model, worked backwards from approval.
- 🔷 Two sides: `ollmfilesd` holds the texts. The desktop paints. Start from what crosses the wire.
- 🔷 The client computes the diff today. That is the wrong side.
- 🔷 The daemon already has the backup in the cache. Review data should come from that cache.
- 🔷 Approval must not ship large bodies back. The server already holds the rows and the texts.
- 🔷 `show_pending_diff` does not read the backup. That call runs `Differ` on the daemon, creates one diff-item row per hunk, and returns the array of those rows.
- 💩 No new RPC and no `decide` fences in this plan. Sign the objects first, then rewrite [`4.2.3.5.3`](CODER-4.2.3.5.3-source-view-diff-part-rows.md).

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

Same open. `show_pending_diff` does not read the backup. The daemon diffs, writes one row per hunk, and returns that array.

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
                                    Differ(cache backup, project file)
                                    create one diff-item row per hunk
                                ←  array of those rows
  paint bands and colours from the array
  backup file stays on the daemon      (no wire)
```

- 🔷 `show_pending_diff` is an RPC. It does not call `RPC-File.read` on `backup_path`.
- 🔷 `Differ` runs on `ollmfilesd`. Inputs are the cache backup and the project file. Both are already there.
- 🔷 That call creates the diff items. One database row per hunk.
- 🔷 The reply is an array of those rows. The desktop paints from the array.
- ℹ️ `file_diff_part` today is only `id`, `file_history_id`, `part_index`, `accepted`, `decided_at`. No hunk text. Rows are unused. `ollmfilesd/FileDiffPart.vala`.
- 💩 Those rows are `file_diff_part`. Each one has to carry the hunk the client paints (line ranges and the changed lines). Columns are not chosen yet.
- 💩 Once every hunk has a row, `accepted` `0` / `1` cannot also mean "not decided yet". Pending needs its own state on the row.
- 💩 The call's argument is the pending `file_history` id (`FileWithHistory.approve_id`). The method name is not chosen.

---

## Approval call — what 4.2.3.5.3 would add

Not built. This is the planned direction that sends too much, and re-reads what the cache already holds.

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
- 🔷 The daemon already ran `Differ` on show and stored the rows. `decide` should use those rows. It should not diff again, and it should not send a `File` row back.

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

- 🚫 Implement `OLLMfilesd-FileHistory.decide` from [`4.2.3.5.3`](CODER-4.2.3.5.3-source-view-diff-part-rows.md) before this model is signed off.
- 🚫 A hunk file that stores the full project text.
- 🚫 Client `Differ` on the backup body as the long-term review path.
- ℹ️ Touch points: `liboccoder/SourceView.vala` `show_pending_diff`, `ollmfilesd/File.vala` `read`, `ollmfilesd/FileWithHistory.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`, `libocfiles/Diff/Differ.vala`.
