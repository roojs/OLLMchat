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

namespace OLLMcoder.AgentPi
{
	/**
	 * One Pi-format soft skill (Agent Skills ''SKILL.md'' entry).
	 *
	 * Catalog-only for Agent Pi: name/description/path go in the system prompt;
	 * the model loads the body with the ''read'' tool. Not an
	 * {@link OLLMcoder.Skill.Definition}.
	 */
	public class Skill : GLib.Object
	{
		public string name { get; set; default = ""; }
		public string description { get; set; default = ""; }
		public string path { get; set; default = ""; }
		public string base_dir { get; set; default = ""; }
		public bool disable_model { get; set; default = false; }

		/**
		 * Load a skill from an absolute ''SKILL.md'' path.
		 *
		 * @param skill_md_path absolute path to ''SKILL.md''
		 * @return skill, or null when description is missing
		 */
		public static Skill? load(string skill_md_path)
		{
			uint8[] raw;
			var etag = "";
			try {
				var file = skill_md_path.has_prefix("resource://")
					? GLib.File.new_for_uri(skill_md_path)
					: GLib.File.new_for_path(skill_md_path);
				file.load_contents(null, out raw, out etag);
			} catch (GLib.Error e) {
				return null;
			}
			var name = "";
			var description = "";
			var disable_model = false;
			var in_frontmatter = false;
			var found_first = false;
			foreach (var line in ((string) raw).split("\n")) {
				var stripped = line.strip();
				if (stripped == "---") {
					if (!found_first) {
						found_first = true;
						in_frontmatter = true;
						continue;
					}
					break;
				}
				if (!in_frontmatter) {
					continue;
				}
				if (stripped == "" || stripped.has_prefix("#")) {
					continue;
				}
				var colon = stripped.index_of(":");
				if (colon < 0) {
					continue;
				}
				var key = stripped.substring(0, colon).strip();
				var value = stripped.substring(colon + 1).strip();
				switch (key) {
					case "name":
						name = value;
						break;
					case "description":
						description = value;
						break;
					case "disable-model-invocation":
						disable_model = (value == "true");
						break;
				}
			}
			if (description.strip() == "") {
				return null;
			}
			var base_dir = "";
			if (skill_md_path.has_prefix("resource://")) {
				var slash = skill_md_path.last_index_of_char('/');
				base_dir = skill_md_path.substring(0, slash);
			} else {
				base_dir = GLib.Path.get_dirname(skill_md_path);
			}
			if (name == "") {
				var slash = base_dir.last_index_of_char('/');
				if (slash >= 0) {
					name = base_dir.substring(slash + 1);
				} else {
					name = base_dir;
				}
			}
			return new Skill() {
				name = name,
				description = description,
				path = skill_md_path,
				base_dir = base_dir,
				disable_model = disable_model
			};
		}
	}
}
