# Folder click leaves the file grid empty

**Status:** ⏳ Root cause confirmed. Daemon restarted onto the binary that has ''Folder.fetch_dir''. File pane still needs the status line.

## Problem

- 🔷 Clicking a folder in the tree does nothing visible. The right grid stays empty.
- 🔷 Unclear whether a loading indicator is missing, or the request never runs.

## Evidence

- ✔️ Journal on the live daemon, three clicks: `RPC dispatch: no handler for 'Folder' (Folder.fetch_dir)` at 11:57:44, 11:57:45, 11:57:46.
- ✔️ `systemctl --user status ollmfilesd` showed pid 645540 started 11:54:33. `/proc/645540/exe` pointed at `/usr/bin/ollmfilesd (deleted)`.
- ✔️ `strings` on that inode had no `fetch_dir`. `/usr/bin/ollmfilesd` on disk, installed 11:57:23, does.
- ✔️ `FileListStore` clears the list, then on failure reports `client.filesd.unreachable` or `Banner.show`. The file pane has no status row. A refused call looks like a dead click.
- 🚫 Not a missing selection signal. The daemon logged the method, so the click ran the request.

## Root cause

- ✔️ The user service was still the process from before `Folder.fetch_dir` was installed. Dispatch replied method-not-found. The grid has no place to show that, so it stays empty.

## Proposed fix

**Why:** The installed binary already has the method. The file pane should use the same status row as the folder spinner, so a wait or a failure is visible.

**Where:** Restart `ollmfilesd.service`. `examples/oc-test-source-diff/FileListStore.vala` load and the file pane.

#### Replace with

```vala
file_label.label = "Loading files";
file_spinner.spinning = true;
file_status.visible = true;
```

On failure, stop the spinner and set the label to the error message, or `File list failed` when that message is empty. On an empty page, the label is `No files`. On rows, hide the status and fill the store.
