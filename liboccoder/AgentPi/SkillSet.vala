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
	 * Scan Pi-format skill directories and format the Agent Pi catalog.
	 *
	 * Order: bundled ''/pi-skills'' gresource, then
	 * ''~/.local/share/ollmchat/pi-skills/'', project ''.pi/skills/'',
	 * project ''.agents/skills/''. Same name later replaces earlier (user/project
	 * override resource). Immediate child directories with ''SKILL.md'' only
	 * (no deep recurse). Used from {@link PendingMessage.run}.
	 */
	public class SkillSet : GLib.Object
	{
		public Gee.ArrayList<Skill> items {
			get;
			private set;
			default = new Gee.ArrayList<Skill>();
		}

		/**
		 * Clear and rescan resource pack + global + project skill roots.
		 *
		 * @param project_path active project path (may be empty)
		 */
		public void scan(string project_path)
		{
			this.items.clear();
			var by_name = new Gee.HashMap<string, Skill>();
			try {
				var children = GLib.resources_enumerate_children(
					"/pi-skills", GLib.ResourceLookupFlags.NONE);
				foreach (var child in children) {
					if (!child.has_suffix("/")) {
						continue;
					}
					var dir_name = child.substring(0, child.length - 1);
					if (dir_name.has_prefix(".")) {
						continue;
					}
					var skill = Skill.load(
						"resource:///pi-skills/" + dir_name + "/SKILL.md");
					if (skill != null) {
						by_name.set(skill.name, skill);
					}
				}
			} catch (GLib.Error e) {
			}
			string[] roots = {};
			var global_root = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", "pi-skills");
			if (GLib.FileUtils.test(global_root, GLib.FileTest.IS_DIR)) {
				roots += global_root;
			}
			var project = project_path.strip();
			if (project != "") {
				var pi_root = GLib.Path.build_filename(project, ".pi", "skills");
				if (GLib.FileUtils.test(pi_root, GLib.FileTest.IS_DIR)) {
					roots += pi_root;
				}
				var agents_root = GLib.Path.build_filename(project, ".agents", "skills");
				if (GLib.FileUtils.test(agents_root, GLib.FileTest.IS_DIR)) {
					roots += agents_root;
				}
			}
			foreach (var root in roots) {
				try {
					var enumerator = GLib.File.new_for_path(root).enumerate_children(
						"standard::name,standard::type",
						GLib.FileQueryInfoFlags.NONE,
						null);
					GLib.FileInfo? info = null;
					while ((info = enumerator.next_file(null)) != null) {
						var name = info.get_name();
						if (name.has_prefix(".")) {
							continue;
						}
						if (info.get_file_type() != GLib.FileType.DIRECTORY) {
							continue;
						}
						var skill_md = GLib.Path.build_filename(root, name, "SKILL.md");
						if (!GLib.FileUtils.test(skill_md, GLib.FileTest.IS_REGULAR)) {
							continue;
						}
						var skill = Skill.load(skill_md);
						if (skill != null) {
							by_name.set(skill.name, skill);
						}
					}
				} catch (GLib.Error e) {
				}
			}
			foreach (var entry in by_name.entries) {
				this.items.add(entry.value);
			}
		}

		/**
		 * Build the system-prompt skills block (empty when nothing visible).
		 *
		 * Only skills whose names appear in ''offered'' are listed (soft
		 * filter — does not block reading other skill paths).
		 *
		 * @param offered offered skill names from {@link OLLMchat.Settings.AgentConfig.skills}
		 * @return markdown + XML catalog, or empty string
		 */
		public string to_prompt(Gee.ArrayList<string> offered)
		{
			string[] blocks = {};
			foreach (var skill in this.items) {
				if (skill.disable_model) {
					continue;
				}
				if (!offered.contains(skill.name)) {
					continue;
				}
				blocks += 
@"  <skill>
    <name>$(skill.name)</name>
    <description>$(skill.description)</description>
    <location>$(skill.path)</location>
  </skill>";
			}
			if (blocks.length == 0) {
				return "";
			}
			return 
@"## Skills

The following skills provide specialized instructions for specific tasks.
Use the read tool to load a skill's file when the task matches its description.
When a skill file references a relative path, resolve it against the skill directory
(parent of SKILL.md) and use that absolute path in tool commands.

<available_skills>
$(string.joinv("\n", blocks))
</available_skills>
";
		}
	}
}
