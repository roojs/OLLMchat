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

namespace OLLMapp.SettingsDialog
{
	/**
	 * Settings tab: Agent Pi skills available vs initially offered.
	 *
	 * Flat rows via {@link Rows.SkillRow}. {@link add_skill} appends once;
	 * {@link load_skills} adds only new names then fills values. Toggle edits
	 * {@link OLLMchat.Settings.AgentConfig.skills} on ''agents["agent-pi"]''.
	 * One shared context menu exports resource skills to the filesystem.
	 */
	public class SkillsPage : SettingsPage
	{
		public MainDialog dialog { get; construct; }

		/**
		 * Agent Pi config entry this page edits (''agents["agent-pi"]'').
		 */
		public OLLMchat.Settings.AgentConfig agent_skills { get; private set; }

		/**
		 * True while {@link load_skills} is writing toggles (ignore notify).
		 */
		public bool filling_skills { get; set; default = false; }

		private Gtk.ScrolledWindow scrolled_window;
		private Adw.PreferencesGroup group;
		private Gtk.Box boxed_list;
		private Gtk.PopoverMenu export_menu;
		private Rows.SkillRow menu_skill;
		private Gee.HashMap<string, Rows.SkillRow> skill_rows {
			get;
			set;
			default = new Gee.HashMap<string, Rows.SkillRow>();
		}

		public SkillsPage(MainDialog dialog)
		{
			Object(
				dialog: dialog,
				page_name: "skills",
				page_title: "Skills",
				page_icon: "application-x-addon-symbolic",
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0
			);

			this.agent_skills = this.dialog.app.config.agents.get("agent-pi");

			this.action_widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				hexpand = true,
				visible = false
			};

			var help = new Gtk.Label(
				"Toggle to include a skill in the Agent Pi initial prompt\n" +
				"Right click to export the skill to the filesystem"
			) {
				wrap = true,
				xalign = 0.5f,
				halign = Gtk.Align.CENTER,
				hexpand = true,
				justify = Gtk.Justification.CENTER,
				margin_bottom = 12,
				css_classes = { "caption", "dim-label" }
			};
			this.group = new Adw.PreferencesGroup();
			this.boxed_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.group.add(this.boxed_list);

			var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			content.append(help);
			content.append(this.group);

			this.scrolled_window = new Gtk.ScrolledWindow() {
				vexpand = true,
				hexpand = true
			};
			this.scrolled_window.set_child(content);
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.append(this.scrolled_window);

			var menu_model = new GLib.Menu();
			menu_model.append("Export to filesystem", "skills.export");
			this.export_menu = new Gtk.PopoverMenu.from_model(menu_model);
			this.export_menu.set_parent(this.boxed_list);

			var export_action = new GLib.SimpleAction("export", null);
			export_action.activate.connect(() => {
				this.menu_skill.export();
			});
			var actions = new GLib.SimpleActionGroup();
			actions.add_action(export_action);
			this.insert_action_group("skills", actions);

			var gesture = new Gtk.GestureClick();
			gesture.set_button(Gdk.BUTTON_SECONDARY);
			gesture.pressed.connect((n_press, x, y) => {
				var widget = this.boxed_list.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (widget != null && !(widget is Adw.ActionRow)) {
					widget = widget.get_parent();
				}
				if (widget == null) {
					return;
				}
				var action_row = (Adw.ActionRow) widget;
				if (!this.skill_rows.has_key(action_row.title)) {
					return;
				}
				var skill_row = this.skill_rows.get(action_row.title);
				if (!skill_row.skill.path.has_prefix("resource://")) {
					return;
				}
				this.menu_skill = skill_row;
				this.export_menu.set_pointing_to(Gdk.Rectangle() {
					x = (int) x,
					y = (int) y,
					width = 1,
					height = 1
				});
				this.export_menu.popup();
			});
			this.boxed_list.add_controller(gesture);
		}

		/**
		 * Create a {@link Rows.SkillRow} once and append it to the list.
		 *
		 * @param skill scanned Agent Pi skill
		 */
		private void add_skill(OLLMcoder.AgentPi.Skill skill)
		{
			var skill_row = new Rows.SkillRow(this, skill);
			this.boxed_list.append(skill_row.row);
			this.skill_rows.set(skill.name, skill_row);
		}

		/**
		 * Scan; add rows for new skill names only; fill toggles and subtitles.
		 */
		public void load_skills()
		{
			var project_path = "";
			var history_manager = (this.dialog.parent as OllmchatWindow).history_manager;
			if (history_manager != null) {
				project_path = history_manager.session.project_path;
			}
			var skill_set = new OLLMcoder.AgentPi.SkillSet();
			skill_set.scan(project_path);
			foreach (var skill in skill_set.items) {
				if (!this.skill_rows.has_key(skill.name)) {
					this.add_skill(skill);
					continue;
				}
				this.skill_rows.get(skill.name).skill = skill;
			}
			this.filling_skills = true;
			foreach (var skill_row in this.skill_rows.values) {
				skill_row.fill(this.agent_skills.skills);
			}
			this.filling_skills = false;
		}
	}
}
