# Bash spill folders

**Status:** 🚫 CLOSED 2026-11-05. Bash commands run. Cleanup and the date folders are in the tree. Restored rendering stays [`2026-11-05-restore-bash-tool-output.md`](../2026-11-05-restore-bash-tool-output.md). Line wrap stays as it is for now: [`2026-11-05-bash-output-wrap.md`](../2026-11-05-bash-output-wrap.md).

- 💩 A later change may keep a span other than two months. Not this change.

## Problem

- 🔷 Spill files live under `tools/bash`, then a year folder, a month folder, and a day folder.
- 🔷 Cleanup is a class `Cleanup` in the file daemon. The constructor takes the directory.
- 🔷 When the file daemon starts, it calls that class on one line.
- 🔷 Keep the current month and the previous month. Any other month is deleted.
- 🔷 In January the previous month is December of the previous year.
- 🔷 Cleanup uses the month folders. No per-file age scan.

## Proposed fix

- 🔷 File `ollmfilesd/Cleanup.vala`, namespace `OLLMfilesd`, class `Cleanup`. The constructor takes the directory. Two methods: `delete_except` and `delete_dir`. Two months only.
- 🔷 `delete_except` takes a directory and two names. Any child whose name is not one of those two is passed to `delete_dir`. The two names may be the same.
- 🔷 First call is the spill root, with this year and the previous year. In October both names are `2026`.
- 🔷 Next call is this year directory, with the two month names. In October that is `root/2026` with `10` and `09`.
- 🔷 The year comparison is after that call. When the years are the same, return. Those months are already deleted.
- 🔷 When the years differ, one more `delete_except` runs on the previous year and keeps only the previous month. In January that is `root/2026` with `12` and `12`, after `root/2027` was called with `01` and `12`.
- 🔷 `delete_dir` recurses down and deletes that directory.
- 🚫 `years`, `months`, or a `switch` on folder depth.
- 🔷 One spill is `{root}/tools/bash/YYYY/MM/DD/run_command-{session_id}-{realtime}.log`, mode `600`.
- 🔷 `YYYY`, `MM`, and `DD` are zero-padded, the same shape as history `to_path()` (`2026/11/05`).
- 🔷 The day directory is created EXISTS-tolerant in `ollmfilesd/Sandbox/Bubble.vala` `run()`. It stays until a later cleanup deletes that month.
- 🔷 `ollmfilesd` calls `new Cleanup(...)` at the start of `Application.initialize()`, passing `{user_cache_dir}/ollmchat/tools/bash`.
- 🚫 A symlink, and any copy of this class under `liboctools`.
- 💩 `{root}` is `{user_cache_dir}/ollmchat` (`~/.cache/ollmchat/tools/bash/...`). `--ro-bind / /` lets a later bash open it. `/tmp` and `XDG_RUNTIME_DIR` stay hidden by the sandbox.
- 🚫 Deleting a year only because it looks empty. `delete_except` on the root deletes it because the name is not one of the two years.
- 🚫 Calling cleanup from the application (`Registry.fill_tools` or `OllmchatWindow`).
- 🚫 Calling cleanup from `Registry.setup_config_defaults`. That constructs a tool only to fill config.
- 🚫 Deleting days inside the two months that are kept.
- 🚫 Cleaning up on every bash call.

**Where:** `ollmfilesd/meson.build`, `ollmfilesd_src`, next to `Sandbox/Bubble.vala`.

#### Add

```meson
  'Cleanup.vala',
```

**Where:** new file `ollmfilesd/Cleanup.vala`.

#### Add

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd
{
	/**
	 * Keep this month and the previous month in a year/month/day tree.
	 *
	 * ''path'' holds the year folders. In January the previous month is
	 * December of the previous year. A later change may keep a different
	 * span. This one keeps two months.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new OLLMfilesd.Cleanup(GLib.Path.build_filename(
	 *     GLib.Environment.get_user_cache_dir(),
	 *     "ollmchat", "tools", "bash"));
	 * }}}
	 */
	public class Cleanup : GLib.Object
	{
		/**
		 * Keep two years, then the two months inside those years.
		 *
		 * @param path directory whose children are year folders
		 */
		public Cleanup(string path)
		{
			if (!GLib.FileUtils.test(path, GLib.FileTest.IS_DIR)) {
				return;
			}
			var now = new GLib.DateTime.now_local();
			var keep_year = now.get_year();
			var keep_month = now.get_month();
			var prev_year = keep_year;
			var prev_month = keep_month - 1;
			if (prev_month < 1) {
				prev_month = 12;
				prev_year = keep_year - 1;
			}
			var year_now = "%04d".printf(keep_year);
			var year_prev = "%04d".printf(prev_year);
			var month_now = "%02d".printf(keep_month);
			var month_prev = "%02d".printf(prev_month);
			this.delete_except(path, year_now, year_prev);
			this.delete_except(
				GLib.Path.build_filename(path, year_now),
				month_now, month_prev);
			if (year_now == year_prev) {
				return;
			}
			this.delete_except(
				GLib.Path.build_filename(path, year_prev),
				month_prev, month_prev);
		}

		/**
		 * Delete every child of a directory except two names.
		 *
		 * The two names may be the same. A kept name is left untouched.
		 *
		 * @param path directory to clean
		 * @param keep_a first name to leave
		 * @param keep_b second name to leave
		 */
		private void delete_except(
			string path,
			string keep_a,
			string keep_b
		) {
			GLib.FileEnumerator children;
			try {
				children = GLib.File.new_for_path(path).enumerate_children(
					"standard::name,standard::type",
					GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			while (true) {
				GLib.FileInfo info;
				try {
					info = children.next_file(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return;
				}
				if (info == null) {
					return;
				}
				var name = info.get_name();
				if (name == keep_a || name == keep_b) {
					continue;
				}
				this.delete_dir(GLib.Path.build_filename(path, name));
			}
		}

		/**
		 * Delete a directory and everything inside it.
		 *
		 * @param path directory or file
		 */
		private void delete_dir(string path)
		{
			try {
				var children = GLib.File.new_for_path(path).enumerate_children(
					"standard::name,standard::type",
					GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				while (true) {
					var info = children.next_file(null);
					if (info == null) {
						break;
					}
					var child = GLib.Path.build_filename(path, info.get_name());
					if (info.get_file_type() != GLib.FileType.DIRECTORY) {
						GLib.File.new_for_path(child).delete(null);
						continue;
					}
					this.delete_dir(child);
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				GLib.File.new_for_path(path).delete(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}
	}
}
```

**Where:** `ollmfilesd/Application.vala` `initialize()`.

#### Remove

```vala
		private async void initialize() throws GLib.Error
		{
			this.ensure_data_dir();
```

#### Replace with

```vala
		private async void initialize() throws GLib.Error
		{
			new Cleanup(GLib.Path.build_filename(
				GLib.Environment.get_user_cache_dir(),
				"ollmchat", "tools", "bash"));
			this.ensure_data_dir();
```

**Where:** `ollmfilesd/Sandbox/Bubble.vala` `run()`, the `spill_dir` assignment.

#### Replace with

```vala
			var spill_now = new GLib.DateTime.now_local();
			var spill_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_cache_dir(),
				"ollmchat", "tools", "bash",
				spill_now.format("%Y"),
				spill_now.format("%m"),
				spill_now.format("%d"));
```

The EXISTS-tolerant mkdir that follows `spill_dir` stays. It creates the day folder.

## Attempts / changelog

- ✔️ 2026-11-05 — cleanup class, call sites, and date folders written here. No product change.
- ✔️ 2026-11-05 — applied `Cleanup`, the two call sites, and the day directory under `{user_cache_dir}/ollmchat/tools/bash`.
- ✔️ 2026-11-05 — moved that call to `ollmfilesd` `initialize()`. The application no longer constructs `Cleanup`.
- ✔️ 2026-11-05 — `Cleanup` now lives in `ollmfilesd/Cleanup.vala` and takes the directory. Removed from `liboctools` and dropped the symlink.
- 🚫 2026-11-05 — closed. A bash command returns its listing.

## Next

- 🚫 2026-11-05 — closed. Rendering and wrap are the two logs in the status line.
