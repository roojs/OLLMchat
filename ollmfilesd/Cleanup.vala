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
