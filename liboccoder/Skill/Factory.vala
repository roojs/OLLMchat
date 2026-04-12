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
	 * Lightweight factory: creates Manager and Runner only. Message building lives in Runner.
	 */
	public class Factory : OLLMchat.Agent.Factory
	{
		public OLLMfiles.ProjectManager project_manager { get; private set; }
		public Manager skill_manager { get; private set; }
		public string skill_name { get; private set; }

		private OLLMcoder.SourceView? widget = null;
		private OLLMcoder.Task.ProgressView? progress_view = null;

		public Factory(OLLMfiles.ProjectManager project_manager,
			 Gee.ArrayList<string> skills_directories, string skill_name = "")
		{
			this.name = "skill-runner";
			this.title = "Skills Agent";
			this.project_manager = project_manager;
			this.skill_manager = new Manager(skills_directories);
			this.skill_name = skill_name != "" ? skill_name : "task_creator";
		}

		/** Returns active file; ensures buffer exists so caller can call contents(). */
		public OLLMfiles.File? current_file()
		{
			var file = this.project_manager.active_file;
			if (file == null) {
				return null;
			}
			this.project_manager.buffer_provider.create_buffer(file);
			return file;
		}

		public override OLLMchat.Agent.Base create_agent(OLLMchat.History.SessionBase session)
		{
			return new Runner(this, session);
		}

		public override async void activate(GLib.Object window)
		{
			var host = (OLLMchat.ChatUserInterface) window;
			var runner = (OLLMcoder.Skill.Runner) host.session_agent();
			if (this.widget == null) {
				this.progress_view = new OLLMcoder.Task.ProgressView();
				((Gtk.Box) host.above_input_widget()).append(this.progress_view);
				this.widget = new OLLMcoder.SourceView(this.project_manager);
				yield this.initialize_widget();
			}
			this.progress_view.set_runner(runner);
			var widget_id = this.name + "-widget";
			this.widget.name = widget_id;
			var tabs = (Adw.ViewStack) host.tab_view();
			if (tabs.get_child_by_name(widget_id) == null) {
				tabs.add_named(this.widget, widget_id);
			}
			this.widget.visible = true;
			tabs.set_visible_child_name(widget_id);
			host.schedule_pane_update(true);
			this.progress_view.visible = true;
		}

		public override async void deactivate(GLib.Object window)
		{
			var host = (OLLMchat.ChatUserInterface) window;
			this.progress_view.visible = false;
			host.schedule_pane_update(false);
		}

		private async void initialize_widget()
		{
			try {
				this.widget.manager.load_projects_from_db();
				yield this.widget.manager.restore_active_state();
				yield this.widget.apply_manager_state();
			} catch (GLib.Error e) {
				GLib.warning("Failed to initialize Skills Agent widget: %s", e.message);
			}
		}
	}
}
