# Sandbox git status truncates the live git index

**Status:** ⏳ root cause confirmed; index rebuilt from HEAD — fix proposed, not applied

Agent Pi was asked to fold `FileConnectionAdd` into `examples/oc-test-source-diff.vala`. It ran `git status` inside the bash sandbox. The overlay scan then copied `.git/index` back onto the live repo as a text string. The live index became the four bytes `DIRC`. `git status` in the IDE then failed with `index file smaller than expected`.

## Problem

- 🔷 Expected: a sandbox `git status` reads the repo. It does not replace `.git/index` on the live tree.
- 🔷 Actual: at 08:29:06 the live `.git/index` was a new 4-byte file containing `DIRC`. `git status` and `git diff` stopped working. Commits, refs, and objects were still there.
- 🔷 The same run was also told to merge the phone connection dialog into the source-diff example so that file is self-contained.

## What the agent ran

- ℹ️ User text, 08:19: "this file connection add file is not really needed. It should be merged into the OC test source diff… okay to bundle the class at the end of that file."
- ✔️ 08:23:49 `rm -rf examples/oc-test-source-diff` inside the overlay. The daemon logged a whiteout and did not delete the live directory, because that path is not in the file index. The directory is still there, with `FileConnectionAdd.vala` → `../../ollmapp/android/FileConnectionAdd.vala`.
- ✔️ 08:26 onward: `cat >>`, `sed -i`, `perl -i`, and `awk` + `mv` on `examples/oc-test-source-diff.vala`. Those are text, so the scan published them. The live file gained 211 lines: `namespace OLLMapp.SettingsDialog` / `class FileConnectionAdd` appended at the end.
- ✔️ 08:29:06 the command that hit git:

```
git stash list; git status --short | head; echo "=== diff stat ==="; git diff --stat examples/oc-test-source-diff.vala
```

- ✔️ 08:29:33 a later `git diff examples/oc-test-source-diff.vala | head -100` ran after the index was already 4 bytes.
- ℹ️ Daemon log: `/home/alan/.cache/ollmchat/ollmfilesd.debug.log`. Chat log: `/home/alan/.cache/ollmchat/ollmchat.debug.log`.

## Evidence

- ✔️ Live index before repair: size 4, birth and mtime `2026-10-28 08:29:06`, bytes `44 49 52 43` (`DIRC`). No `.git/index.lock`.
- ✔️ That mtime sits between sandbox `wait` (`08:29:06.503`) and the following sqlite "disk backup" log (`08:29:06.583`). The backup log is the file-index database, not a copy of `.git`.
- ✔️ `HEAD` was still `63b5641f` (`refs/heads/main`). `git cat-file -t HEAD` worked while `git status` did not. Object dirs were last written at the 08:17 pull, not at 08:29.
- ✔️ A git index starts with the 4-byte signature `DIRC`, then a big-endian version. Version 2 is the bytes `00 00 00 02`. The first NUL is byte 5.
- ✔️ `ollmfilesd/FileVerification.created` and `modified` load the overlay file and pass it as a string:

```vala
var bytes = GLib.File.new_for_path(overlay_path).load_bytes(null);
yield file.realize((string) bytes.get_data(), unix_mode);
```

- ✔️ `File.realize` takes a `string`. `FileBuffer.write_to_disk` does `uint8[] data = contents.data` and `replace_async` on the live path. A Vala string ends at the first NUL, so the write is `DIRC` and the rest of the index is dropped.
- ✔️ `Scan.scan_dir` publishes an upper-layer file even when `has_file` returns `UNKNOWN`. `.git/index` is not a project file. `created` still builds a `File` and calls `realize`.
- ✔️ `Bubble.can_write` returns true for every path under the project root, including `.git`. The seccomp notify answers `USER_NOTIF_FLAG_CONTINUE`, so the git write is not stopped. It lands in the overlay upper, and the scan copies it out.

## Root cause

- ✔️ `git status` rewrote a normal index in the overlay upper. A version-2 index is `DIRC` plus `00 00 00 02` plus the entries. The scan then published that file with `(string) bytes.get_data()`. A Vala string ends at the first zero, so `replace_async` wrote four bytes over the live `.git/index`. Git did not leave a 4-byte index. An interrupted header write would be 12 bytes (the header struct), not 4.
- 🚫 Skipping `.git` in the scan is the wrong fix. A sandbox `git status` or `git commit` is allowed to publish `.git`. The copy has to keep every byte.

## Repair already done

- ✔️ Moved the 4-byte file to `.git/index.broken-20261028`.
- ✔️ `git read-tree HEAD` rebuilt the index (223160 bytes). Worktree files were not checked out and not reverted.
- ✔️ `git fsck --no-dangling` is clean. `HEAD` is still `63b5641f`.
- ✔️ Anything that existed only in the old index (a partial stage) is gone. The worktree copy is what `git status` shows now.
- ✔️ `git status --short` after the rebuild:

```
 M docs/bugs/2026-10-27-agent-pi-tool-calls-failed.md
 M examples/oc-test-source-diff.vala
 M libollmchat/Call/ChatCompletions.vala
 M resources/style.css
```

- ℹ️ The vala file is the Agent Pi append (211 lines). The other three are the Cursor session from this morning (sending frame, black shell, that bug log). They are not part of this sandbox run.

## Proposed fix

- 🔷 The overlay publish writes the loaded bytes at their real length. `git status` may replace the live index with the index it just wrote. That file stays a valid index.
- 🚫 Do not skip `.git` in the scan. Commits from the sandbox have to be able to update `.git`.
- ℹ️ Supervision and rollback for those commits is separate. This bug is only the 4-byte write.

### `ollmfilesd/FileBuffer.vala` — `write_to_disk`: write the array length

**Why:** `contents.data` on a `string` stops at the first zero. The index version word is that zero.

**Where:** `write_to_disk`, the parameter and the `write_all_async` call. `write_real(string)` passes `contents.data` into it.

**Depends on:** none.

#### Remove

```vala
		protected async void write_to_disk(string contents) throws Error
		{
```

```vala
			uint8[] data = contents.data;
			size_t bytes_written;
			yield output_stream.write_all_async(data, GLib.Priority.DEFAULT, null, out bytes_written);
```

#### Replace with

```vala
		protected async void write_to_disk(uint8[] contents) throws Error
		{
```

```vala
			size_t bytes_written;
			yield output_stream.write_all_async(contents, GLib.Priority.DEFAULT, null, out bytes_written);
```

### `ollmfilesd/FileBuffer.vala` — `write_real`: take the bytes

**Why:** Text callers still have a string. They pass `contents.data`. The index passes `Bytes.get_data()`, whose length is the whole file.

**Where:** `write_real`, the signature and the `write_to_disk` call.

**Depends on:** the `write_to_disk` signature above.

#### Remove

```vala
		public async void write_real(string contents) throws Error
		{
			yield this.write_to_disk(contents);
```

#### Replace with

```vala
		public async void write_real(uint8[] contents) throws Error
		{
			yield this.write_to_disk(contents);
```

`DummyFileBuffer` calls `this.write_real(contents.data)` and `this.write_real(new_content.data)`.

### `ollmfilesd/File.vala` — `realize`: take the bytes

**Why:** The overlay file is a byte array. `realize(string)` cannot hold the index.

**Where:** `realize`, the signature and the `write_real` call. The RPC writer in the same file passes `content.data`.

**Depends on:** `write_real(uint8[])` above.

#### Remove

```vala
		public async void realize(string content, uint unix_mode) throws Error
		{
			if (this.buffer == null) {
				this.manager.buffer_provider.create_buffer(this);
			}
			yield this.buffer.write_real(content);
```

```vala
						yield file.realize(content, unix_mode);
```

#### Replace with

```vala
		public async void realize(uint8[] content, uint unix_mode) throws Error
		{
			if (this.buffer == null) {
				this.manager.buffer_provider.create_buffer(this);
			}
			yield this.buffer.write_real(content);
```

```vala
						yield file.realize(content.data, unix_mode);
```

### `ollmfilesd/FileVerification.vala` — `created` and `modified`: do not cast to string

**Why:** `Bytes.get_data()` is the full index, length included. The cast drops everything after `DIRC`.

**Where:** both `file.realize` calls.

**Depends on:** `realize(uint8[])`.

#### Remove

```vala
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(null);
						yield file.realize((string) bytes.get_data(), unix_mode);
```

#### Replace with

```vala
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(null);
						yield file.realize(bytes.get_data(), unix_mode);
```

## Attempts / changelog

- ✔️ 2026-10-28 — confirmed the 4-byte index, rebuilt it with `git read-tree HEAD`, left the worktree in place.
- 🚫 2026-10-28 — skipping `.git` in `Scan.scan_dir`. A sandbox commit has to publish `.git`.
- ⏳ Apply the byte-length write. Rebuild `ollmfilesd`. A sandbox `git status` must leave `.git/index` starting with `DIRC` and larger than 4 bytes.
