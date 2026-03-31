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
	 * Loads built-in skills from gresources and optional user overrides under
	 * ``~/.local/share/ollmchat/skills/``.
	 *
	 * **by_name** — Key is the skill catalog name (YAML ``name``, or ``override`` target).
	 * Used to validate tasks and resolve which definition to run.
	 */
	public class Manager : Object
	{
		public Gee.ArrayList<string> skills_directories { 
			get; private set; default = new Gee.ArrayList<string>(); }
		/** YAML catalog name (``name`` / ``override`` target) → definition. */
		public Gee.HashMap<string, Definition> by_name { 
			get; set; default = new Gee.HashMap<string, Definition>(); }

		public Manager(Gee.ArrayList<string> skills_directories)
		{
			this.skills_directories = skills_directories;
		}

		/** Returns true if task's skill exists in by_name; false otherwise. Caller generates error message. */
		public bool validate(OLLMcoder.Task.Details task)
		{
			var skill_name = task.task_data.get("skill").to_markdown().strip();
			return skill_name != "" && this.by_name.has_key(skill_name);
		}

		/** Skill name from task; call only after validate(task). */
		public Definition fetch(OLLMcoder.Task.Details task)
		{
			var skill_name = task.task_data.get("skill").to_markdown().strip();
			var definition = this.by_name.get(skill_name);
			if (definition == null) {
				GLib.critical("skill_manager.fetch: no definition for skill_name='%s' (by_name has %u skills)", skill_name, this.by_name.size);
			}
			return definition;
		}

		/**
		 * One line per skill: "**Skillname** - description". Template already has the heading; caller passes this as the placeholder body only.
		 */
		public string to_markdown()
		{
			var ret = "";
			foreach (var e in this.by_name.entries) {
				ret += "- **" + e.key + "** - " + e.value.header.get("description") + "\n";
			}
			return ret;
		}

		public void scan() throws GLib.Error
		{
			this.by_name.clear();
			// 1) Built-ins from gresources (/skills/*.md)
			try {
				var children = GLib.resources_enumerate_children(
					"/skills", GLib.ResourceLookupFlags.NONE);
				foreach (var name in children) {
					if (!name.has_suffix(".md")) {
						continue;
					}
					var resource_path = "/skills/" + name;
					try {
						var skill = new Definition("resource://" + resource_path);
						skill.load();
						this.by_name.set(skill.header.get("name"), skill);
					} catch (GLib.Error e) {
						GLib.warning("skip builtin skill %s: %s", resource_path, e.message);
					}
				}
			} catch (GLib.Error e) {
				GLib.warning("Cannot enumerate resource directory /skills: %s", e.message);
			}

			// 2) User files: ~/.local/share/ollmchat/skills/*.md
			this.scan_dir(GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", "skills"));
		}

		/**
		 * Load every ``*.md`` in ``dir_path`` if the directory exists.
		 * Files with YAML ``override: skill_name`` replace that catalog entry.
		 * Other files register only if the name is new; duplicates require ``override``.
		 */
		private void scan_dir(string dir_path)
		{
			var dir = GLib.File.new_for_path(dir_path);
			if (!dir.query_exists()) {
				return;
			}
			GLib.FileEnumerator enumerator;
			try {
				enumerator = dir.enumerate_children(
					"standard::name,standard::type,time::modified",
					GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
			} catch (GLib.Error e) {
				GLib.warning("Cannot open skills directory %s: %s", dir_path, e.message);
				return;
			}
			try {
				GLib.FileInfo? info;
				while ((info = enumerator.next_file(null)) != null) {
					var fname = info.get_name();
					if (!fname.has_suffix(".md")) {
						continue;
					}
					var skill_path = GLib.Path.build_filename(dir_path, fname);
					var skill = new Definition(skill_path);
					try {
						skill.load();
					} catch (GLib.Error e) {
						GLib.warning("skip skill %s: %s", skill_path, e.message);
						continue;
					}
					var catalog_name = skill.header.get("name");
					bool is_override = skill.header.has_key("override")
						&& skill.header.get("override").strip() != "";
					if (is_override) {
						if (!this.by_name.has_key(catalog_name)) {
							GLib.critical(
								"Skill override %s: no built-in skill '%s' to replace — skipping",
								skill_path, catalog_name);
							continue;
						}
						this.by_name.set(catalog_name, skill);
						contine;
					} 
					if (this.by_name.has_key(catalog_name)) {
						GLib.critical(
							"Skill %s: catalog name '%s' already loaded — use 'override: %s' in YAML to replace the built-in",
							skill_path, catalog_name, catalog_name);
						continue;
					}
					this.by_name.set(catalog_name, skill);
					
				}
			} catch (GLib.Error e) {
				GLib.warning("Cannot enumerate skills directory %s: %s", dir_path, e.message);
			}
		}
	}
}
