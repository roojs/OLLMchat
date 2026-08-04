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

namespace OLLMapp.SettingsDialog.Rows
{
	/**
	 * One Agent Pi skill settings row: ActionRow, offered Switch, and Skill.
	 *
	 * Construction builds widgets and wires the offered toggle to
	 * {@link SkillsPage.agent_skills}. Resource skills have no subtitle;
	 * filesystem skills show their path. Export uses the page context menu.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var skill_row = new Rows.SkillRow(page, skill);
	 * skill_row.fill(page.agent_skills.skills);
	 * }}}
	 */
	public class SkillRow : Object
	{
		/**
		 * Parent skills page (offered list and fill guard).
		 */
		public SkillsPage page { get; construct; }

		/**
		 * Scanned skill this row represents (path may change after export).
		 */
		public OLLMcoder.AgentPi.Skill skill { get; set; }

		/**
		 * Preferences ActionRow shown in the skills list.
		 */
		public Adw.ActionRow row { get; private set; }

		/**
		 * Toggle for initially offered (AgentConfig.skills).
		 */
		public Gtk.Switch toggle { get; private set; }

		/**
		 * Build row + toggle and connect the offered switch.
		 *
		 * @param page skills settings page that owns the offered list
		 * @param skill scanned Agent Pi skill
		 */
		public SkillRow(SkillsPage page, OLLMcoder.AgentPi.Skill skill)
		{
			Object(page: page);
			this.skill = skill;
			this.row = new Adw.ActionRow() {
				title = skill.name,
				subtitle = skill.path.has_prefix("resource://") ? "" : skill.path,
				activatable = false
			};
			this.toggle = new Gtk.Switch() {
				valign = Gtk.Align.CENTER
			};
			this.toggle.notify["active"].connect(() => {
				if (this.page.filling_skills) {
					return;
				}
				if (this.toggle.active) {
					if (!this.page.agent_skills.skills.contains(this.skill.name)) {
						this.page.agent_skills.skills.add(this.skill.name);
					}
					return;
				}
				this.page.agent_skills.skills.remove(this.skill.name);
			});
			this.row.add_suffix(this.toggle);
		}

		/**
		 * Refresh offered toggle and path subtitle from current skill.
		 *
		 * @param offered AgentConfig.skills names currently offered
		 */
		public void fill(Gee.ArrayList<string> offered)
		{
			this.toggle.active = offered.contains(this.skill.name);
			this.row.subtitle = "";
			if (this.skill.path.has_prefix("resource://")) {
				return;
			}
			this.row.subtitle = this.skill.path;
		}

		/**
		 * Copy this resource skill into the user Pi-skills dir; update the row.
		 */
		public void export()
		{
			var user_root = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", "pi-skills");
			var dest_dir = GLib.Path.build_filename(user_root, this.skill.name);
			try {
				GLib.File.new_for_path(dest_dir).make_directory_with_parents(null);
			} catch (GLib.IOError e) {
				if (e.code != GLib.IOError.EXISTS) {
					GLib.warning("Failed to create %s: %s", dest_dir, e.message);
					return;
				}
			}
			var resource_dir = "/pi-skills/" + this.skill.name;
			var children = GLib.resources_enumerate_children(
				resource_dir, GLib.ResourceLookupFlags.NONE);
			foreach (var child in children) {
				if (child.has_suffix("/")) {
					continue;
				}
				var bytes = GLib.resources_lookup_data(
					resource_dir + "/" + child, GLib.ResourceLookupFlags.NONE);
				var dest = GLib.File.new_for_path(
					GLib.Path.build_filename(dest_dir, child));
				dest.replace_contents(
					bytes.get_data(), null, false,
					GLib.FileCreateFlags.REPLACE_DESTINATION, null, null);
			}
			var skill_md = GLib.Path.build_filename(dest_dir, "SKILL.md");
			this.skill.path = skill_md;
			this.row.subtitle = skill_md;
		}
	}
}
