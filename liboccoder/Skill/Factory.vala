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
		/**
		 * Set after {@link #initialize_widget} completes its first run (including
		 * after a caught error) so project/SourceView state loads once per
		 * factory.
		 */
		private bool done_init = false;

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

		/**
		 * Shows the Skills agent UI: progress strip, SourceView tab, and pane
		 * sizing.
		 *
		 * On first activation, binds {@link Task.ProgressView} to
		 * {@link OLLMcoder.Task.ProgressList} on the session runner before
		 * {@link #initialize_widget} runs so session restore can update the
		 * progress model while project state loads asynchronously.
		 *
		 * @param window main window implementing {@link OLLMchat.ChatUserInterface}
		 */
		public override async void activate(GLib.Object window)
		{
			var host = (OLLMchat.ChatUserInterface) window;
			if (this.widget == null) {
				this.progress_view = new OLLMcoder.Task.ProgressView();
				((Gtk.Box) host.above_input_widget()).append(this.progress_view);
				this.widget = new OLLMcoder.SourceView(this.project_manager);
			}
			this.progress_view.set_runner(
				(OLLMcoder.Skill.Runner) host.session_agent());
			this.progress_view.window = host;
			yield this.initialize_widget();
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

		/**
		 * Loads project list and active project state for the SourceView manager.
		 * Only the first completed attempt runs the DB restore; later calls return
		 * immediately.
		 */
		private async void initialize_widget()
		{
			if (this.done_init) {
				return;
			}
			try {
				this.widget.manager.load_projects_from_db();
				yield this.widget.manager.restore_active_state();
				yield this.widget.apply_manager_state();
			} catch (GLib.Error e) {
				GLib.warning("Failed to initialize Skills Agent widget: %s", e.message);
			}
			this.done_init = true;
		}
	}
}
