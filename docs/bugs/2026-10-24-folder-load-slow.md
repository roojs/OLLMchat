# Folder sheet takes minutes to leave "Loading folders"

**Status:** ⏳ Paused. 🔷 Intermittent, not critical. Leave it.

## Problem

- 🔷 Opening a project on the tablet sits on "Loading folders" for an unacceptable time. The same sheet used to come up quickly.
- 🔷 Expected: the folder tree appears as soon as `Folder.fetch_children` returns.
- ℹ️ "Loading folders" is `FileOverlay`'s row bound to `FolderTreeStore.loading`. That flag is true only while `Folder.fetch_children` is in flight and the store is appending the reply.

## Evidence

- ✔️ Daemon `~/.cache/ollmchat/ollmfilesd.debug.log`, project `/home/alan/gitlive/web.MediaOutreach`, pid 28148 (the binary installed 17:40).
  - 17:54:41.565 `opening project`
  - 17:54:44.121 `filesystem scan queued` (2.5s in `load_files_from_db`)
  - 17:54:44.149 root `read_dir` returned, `scanning_active=1`
  - 17:54:44.912 `Folder.fetch_children` id=4
  - 17:54:46.571 `filesystem scan complete`, `scanning_active=21`
  - 17:54:49 about 709 `disk backup requested` lines, then idle
  - 17:54:50.427 `Folder.fetch_dir` id=5
  - 17:54:50.895 `Folder.fetch_files` id=6
  - 18:19:07.999 `Folder.fetch_children` id=7, no later RPC
- ✔️ The folder RPC was answered. The client sent `fetch_dir` 5.5s after `fetch_children`. The daemon was back in `poll` and is still there.
- ✔️ That scan follows folder symlinks. MediaOutreach has 111 folders of its own and the walk reached 21 active scans (linked trees such as `Pman.*`). Journal in that window is 72 lines, all `g_file_info_get_size` / missing-file criticals. Not a multi-minute daemon stall.
- ✔️ Tablet process `org.roojs.ollmchat.sourcediff` pid 7299, GTK thread 7413, after the sheet was on screen:
  - 489s user + 914s system. A later 8s sample did not move those counters.
  - `/proc/7413/io`: `syscr=36424670`, `rchar=4847878`, `read_bytes=1417216`.
  - 36 million `read` syscalls moved 4.8MB, and only 1.4MB of that came from storage. The rest is the socket. Most of those reads returned no byte.
- ✔️ Screenshot after the counters stopped: tree and file grid are painted, opacity is not hidden, so `loading` is false. Linked rows (`Pman.Admin`, `Pman.Mail`, …) are visible. Every file icon is still the same generic document.
- 🚫 Icon-theme directory stat. The built-in hicolor index lists 649 directories. Timing those `stat`s on the device was about 28ms. `files/share/icons/hicolor` is 350 SVGs and no `index.theme`. That is not 36 million reads.
- 🚫 A cycle in the single-child collapse (`FolderTree` `while` on `folder_count == 1 && file_count == 0`). The painted tree and a GTK thread sitting in `ppoll` rule out a live infinite walk. The database parent graph for this project has no such cycle either.
- ✔️ 19:18:51 retap of web.MediaOutreach, project already active, scan skipped. `Folder.fetch_children` at 19:18:52.132. `Folder.fetch_dir` at 19:19:00.035. The sheet showed "Loading folders" through that gap, then the tree. GTK thread 15643 over that sample: one userspace burst of 278 samples (~10s at 29 samples/s). `syscr` 33008 → 38373, `rchar` up 4KB. Not a read storm.
- ℹ️ Same project in the database, following folder links the way `update_from` does: about 710 folders in the reply, 27 of them link rows.

## Root cause

- ✔️ The spinner the user sees is the tablet GTK thread after `Folder.fetch_children` has been received, not a slow directory listing. A fresh open with the project already active (no scan) still sat on "Loading folders".
- 🚫 The TLS read spin. On that open the GTK thread's `read` count rose by about 5,000 and 4KB, not tens of millions. The long burst was userspace (`/proc/.../syscall` printed `running`), about 10 seconds, matching the daemon gap from `fetch_children` to `fetch_dir`.
- 💩 That userspace stretch is the store applying the reply into the auto-expanded tree. A database walk of the same project reaches about 710 folders once link targets are included. The visible sheet only draws the first screen. `FolderTree` builds a filter and a sort for every folder while `loading` is still true.
- ⏳ Split not yet timed: reply parse versus the append loop. Two `GLib.debug` lines in `FolderTreeStore.load` mark those boundaries.

## Ruled out as the fix

- 🚫 Moving or deleting the Humanity SVGs. They are not the read storm.
- 🚫 Another hicolor `index.theme`. That was the startup crash.
- 🚫 Hiding the spinner, skipping the scan, or caching the folder list. The scan is a few seconds and the reply already arrived.

## Attempts

- ✔️ Two `GLib.debug` lines were added in `FolderTreeStore.load` and then removed. The investigation is paused.

## Next

- ⏳ Nothing until this is picked up again.
- ℹ️ Separate, not this stall: `FileAlias.new_from_info` calls `get_size()` on a `GFileInfo` from `get_target_info`, which does not request `STANDARD_SIZE`. That is the journal critical during the scan.
