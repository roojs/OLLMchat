# File size missing from the file grid

**Status:** ⏳ scan stores size; needs a filesd restart and a project scan to show on an existing database

## Problem

- 🔷 The file grid Size column stays empty of a real size.
- 🔷 Expected: each file row shows the byte size from the last directory scan.
- 🔷 Actual: every row is zero, because nothing ever recorded a size.

## Evidence

- ℹ️ `filebase` had `last_modified` and no size column. `File.size` defaulted to 0.
- ℹ️ `enumerate_directory_contents` asked for name, type, symlink, content type, and mtime. It did not ask for `STANDARD_SIZE`. `File.new_from_info` never called `get_size()`.
- ℹ️ `SQ.Query` maps columns onto `FileBase` properties only. A size property on `File` alone would not be saved.
- ℹ️ `Folder.fetch_dir` copies the stored row, including `size`. The wire value was 0.
- ℹ️ The grid binds `display_size`. That formats whatever `size` is. Modified time shows, because that column is stored.
- 🚫 Not an RPC drop. The encoder writes every GObject property.

## Root cause

- ✔️ The scan never stored a size. The listing and the grid were showing that zero.

## Proposed fix

- 🔷 Add `size` on `FileBase`, with a `filebase.size` column and the same duplicate-column migration as the other columns.
- 🔷 Ask for `STANDARD_SIZE` while enumerating. Set `size` from that info on a file and on a file alias.
- 🔷 On a rescan of the same row, keep the scanned size and copy it onto the live object, the same way language is kept.
- 🔷 Bind `INT64` columns as `int64`. The old bind went through `getInt`, which casts to `int` and wraps past 2GB.

## Attempts / changelog

- ✔️ `ollmfilesd/FileBase.vala` — `size` property, create-table column, migrate.
- ✔️ `ollmfilesd/File.vala` — set size in `new_from_info`. Property moved to `FileBase`.
- ✔️ `ollmfilesd/FileAlias.vala` — set size from the enumerated info.
- ✔️ `ollmfilesd/Folder.vala` — request `STANDARD_SIZE`; keep scanned size on update.
- ✔️ `libocsqlite/Query.vala` — `INT64` binds use the `int64` property value.
- ✔️ `libocfiles/File.vala` — comment now says the row stores the size.
- ✔️ `examples/oc-test-source-diff/FileList.vala` — Size column width 88 so `1023 bytes` fits.

## Next

- ⏳ Restart `ollmfilesd` so the next project scan writes `filebase.size`, then open a folder in the file grid.
