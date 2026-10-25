# File size missing from the file grid

**Status:** ✅ User confirmed the Size column. Closed 2026-10-24.

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
- ✔️ `examples/oc-test-source-diff/FileList.vala` — Size column width 88 so `1023 bytes` fits. Later the column was 44.
- ✔️ 24 Oct. `display_size` drops the unit word. The Size label fills the cell and aligns right. Column width is 53.

## Rendering

- 🔷 24 Oct. The scan is fine. The Size column text is wrong.
- 🔷 A count under 1000 is the digits alone. `512`, not `512 bytes`.
- 🔷 Larger counts use `K`, `M`, `G`, `T`, or `P` with no space. `1.5K`, `12M`. No `kB` or `MB`.
- 🔷 The number is right-aligned in the column.
- 🔷 The column is about twenty percent wider than 44, so the text fits.

### `libocfiles/File.vala` — `display_size`

**Why:** `GLib.format_size` writes a space and a unit word. The grid wants the digits, then `K`, `M`, `G`, `T`, or `P`.

**Where:** The `display_size` getter.

#### Replace with

```vala
		/**
		 * Byte count shown in the file grid.
		 *
		 * Under 1000 the digits stand alone. K, M, G, T, and
		 * P follow the number with no space. Under ten of a
		 * unit keeps one decimal. Zero is an empty file.
		 */
		public string display_size {
			owned get {
				if (this.size < 1000) {
					return this.size.to_string();
				}
				string[] marks = { "K", "M", "G", "T", "P" };
				var scaled = (double) this.size / 1000.0;
				var step = 0;
				while (scaled >= 1000.0 && step < marks.length - 1) {
					scaled = scaled / 1000.0;
					step++;
				}
				if (scaled >= 999.5 && step < marks.length - 1) {
					scaled = scaled / 1000.0;
					step++;
				}
				if (scaled < 9.95) {
					return "%.1f".printf(scaled) + marks[step];
				}
				return "%.0f".printf(scaled) + marks[step];
			}
		}
```

### `examples/oc-test-source-diff/FileList.vala` — Size column

**Why:** The label sits in its own text width, so the number starts at the left of the cell. 44 is too narrow for the longer counts.

**Where:** The size factory label, and `fixed_width` on the Size column.

#### Replace with — the size label

```vala
				row.child = new Gtk.Label("") {
					halign = Gtk.Align.END,
					hexpand = true,
					xalign = 1,
					css_classes = { "caption", "dim-label" },
				};
```

#### Replace with — the column width

```vala
				fixed_width = 53,
```

## Next

- ✅ 24 Oct. User closed the Size column. The scan stores the byte count, and the grid shows `512`, `1.5K`, and `12M` on the right.

## Conclusion

- ✅ 🔷 The scan stores the byte size, and the grid shows digits with `K`, `M`, `G`, `T`, or `P` and no unit word. User closed this bug on 2026-10-24.
