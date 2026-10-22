# Project load disconnects the file client

**Status:** ✅ User closed this. The client accepts `size` and project load stays connected.

## Problem

- 🔷 Starting the tablet source-diff app shows the window, then the process dies.
- 🔷 The desktop app dies the same way when it loads projects.
- 🔷 Expected: both stay connected to `ollmfilesd` and show the project list.

## Evidence

- ℹ️ Tablet `emulator-5554`, 2026-10-21 22:23. `GTK Runtime: main() returned with 0` after stderr `Error: Client: disconnected`. HWUI then aborts on a destroyed mutex while the process is already exiting.
- ℹ️ `~/.cache/ollmchat/ollmchat.debug.log` 22:25: `unknown bin property 'size'` while reading `ProjectManager.rpc_load_projects_from_db`, then `disconnect abort` for that call.
- ℹ️ `~/.cache/ollmchat/ollmfilesd.debug.log`: the daemon receives `rpc_load_projects_from_db`, then `Unexpected early end-of-stream` and `Broken pipe`. The daemon process stays up.
- ℹ️ Daemon `FileBase` has `size` and writes every property except `manager` and `parent`. Client `Folder` extends `FileBase`, which did not have `size`. Client `File` had its own `size`, so file rows worked and project rows did not.
- 🚫 Do not catch the disconnect and keep going. The reply is rejected before the project list exists.

## Root cause

- ✔️ The daemon sends `size` on every file row, including projects. The client project type has no `size` property, so bin read throws, the socket is dropped, and the in-flight load fails with `Client: disconnected`.

## Proposed fix

- 🔷 Declare `size` on client `FileBase`, the same place the daemon declares it. Remove the copy on client `File`.

### `libocfiles/FileBase.vala` — `size` on every row

**Why:** Project rows are `Folder` objects. They inherit `FileBase` and must accept `size`.
**Where:** After `last_modified`.
**Depends on:** none.

#### Add

After `last_modified`.

```vala
		/**
		 * Size in bytes. The directory scan stores it on the file
		 * row. Folders stay at zero. The daemon sends it on every
		 * row, including projects.
		 */
		public int64 size { get; set; default = 0; }
```

### `libocfiles/File.vala` — drop the file-only `size`

**Why:** `File` extends `FileBase`. A second `size` does not cover folders.
**Where:** The property directly above `display_size`.
**Depends on:** the `FileBase` property.

#### Remove

```vala
		/**
		 * Size in bytes from the stored file row. The directory scan
		 * writes it. A folder listing copies that stored value.
		 */
		public int64 size { get; set; default = 0; }
```

## Attempts / changelog

- ✔️ Moved `size` from `libocfiles/File.vala` to `libocfiles/FileBase.vala`.
- ✔️ `build/ollmapp/ollmchat-cli` loaded and activated `/home/alan/gitlive/OLLMchat` with no `Client: disconnected`.
- ✔️ Rebuilt `.pixiewood/oc-test-source-diff-arm64-v8a-debug.apk`, installed it on `emulator-5554`. Process stayed up past project load. No second end-of-stream after `rpc_load_projects_from_db`.
- ℹ️ `sudo` needs a password, so `/lib/x86_64-linux-gnu/libocfiles.so` and `/usr/bin/ollmchat` are still the 21:51 build.

## Conclusion

- ✅ 🔷 Project load no longer drops the file client. User closed this on 2026-10-21.
- ℹ️ The menu copies `/lib/x86_64-linux-gnu/libocfiles.so` and `/usr/bin/ollmchat` were still the 21:51 build when this was closed. `sudo` needs a password, so those were not replaced from this tree.
