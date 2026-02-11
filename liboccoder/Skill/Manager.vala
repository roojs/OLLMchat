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

namespace OLLMcoder.Skill
{
	/**
	 * Holds an array of skills directories and two maps: path → Definition and name → Definition.
	 * One scan populates both; each Definition stores its own mtime.
	 */
	public class Manager : Object
	{
		public Gee.ArrayList<string> skills_directories { get; private set; default = new Gee.ArrayList<string>(); }
		public Gee.HashMap<string, Definition> by_path { get; set; default = new Gee.HashMap<string, Definition>(); }
		public Gee.HashMap<string, Definition> by_name { get; set; default = new Gee.HashMap<string, Definition>(); }

		public Manager(Gee.ArrayList<string> skills_directories)
		{
			this.skills_directories = skills_directories;
		}

		public void scan() throws GLib.Error
		{
			var keys_before = new Gee.ArrayList<string>();
			keys_before.add_all(this.by_path.keys);
			foreach (var skills_base_path in this.skills_directories) {
				var dir = GLib.File.new_for_path(skills_base_path);
				if (!dir.query_exists()) {
					continue;
				}
				var enumerator = dir.enumerate_children(
					"standard::name,standard::type,time::modified",
					GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				GLib.FileInfo? info;
				while ((info = enumerator.next_file(null)) != null) {
					var name = info.get_name();
					if (!name.has_suffix(".md")) {
						continue;
					}
					if (name == "skill.template.md") {
						continue;
					}
					var skill_path = GLib.Path.build_filename(skills_base_path, name);
					int64 file_mtime = (int64) info.get_modification_time().tv_sec;
					if (this.by_path.has_key(skill_path)
						&& file_mtime == this.by_path.get(skill_path).mtime) {
						keys_before.remove(skill_path);
						continue;
					}
					var skill = new Definition(skill_path);
					try {
						skill.load();
						this.by_path.set(skill_path, skill);
						this.by_name.set(skill.header.get("name"), skill);
						keys_before.remove(skill_path);
					} catch (GLib.Error e) {
						GLib.warning("skip %s: %s", name, e.message);
					}
				}
			}
			foreach (var path in keys_before) {
				var skill = this.by_path.get(path);
				this.by_path.unset(path);
				this.by_name.unset(skill.header.get("name"));
			}
		}
	}
}
