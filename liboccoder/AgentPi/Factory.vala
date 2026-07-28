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
	 * Factory for Agent Pi (id ''agent-pi'').
	 *
	 * Project-aware like other liboccoder factories. Loads templates from the
	 * ''pi-prompts'' gresource; environment and SourceView follow coding-agent
	 * weight. {@link Agent} uses a chat-only FIFO (no summarize until Phase 5).
	 */
	public class Factory : OLLMchat.Agent.Factory
	{
		public override string name { get; protected set; default = "agent-pi"; }
		public override string title { get; protected set; default = "Agent Pi"; }
		public override string long_title {
			get; protected set;
			default = "implementation of the Pi agent harness";
		}

		public OLLMfiles.ProjectManager project_manager { get; private set; }

		private OLLMcoder.SourceView? widget = null;

		/**
		 * @param project_manager shared project/file manager for workspace UI
		 */
		public Factory(OLLMfiles.ProjectManager project_manager)
		{
			this.project_manager = project_manager;
			var env_shell = GLib.Environment.get_variable("SHELL");
			this.shell = env_shell != null && env_shell != "" ? env_shell : "/usr/bin/bash";
		}

		/**
		 * Seed agent config if missing; assert required tools are registered.
		 *
		 * @param config application config
		 * @param tools manager tool map (after fill_tools)
		 */
		public override void register_config(
			OLLMchat.Settings.Config2 config,
			Gee.Map<string, OLLMchat.Tool.BaseTool> tools
		)
		{
			if (!config.agents.has_key(this.name)) {
				config.agents.set(this.name, new OLLMchat.Settings.AgentConfig() {
					forbid = "write_file,huggingface_hub"
				});
			}
			if (!tools.has_key("write")) {
				GLib.error("agent %s: required tool missing: write", this.name);
			}
			if (!tools.has_key("read")) {
				GLib.error("agent %s: required tool missing: read", this.name);
			}
		}

		public override string get_working_directory()
		{
			if (this.project_manager.active_project != null) {
				return this.project_manager.active_project.path;
			}
			return GLib.Environment.get_home_dir();
		}

		public override string get_workspace_path()
		{
			if (this.project_manager.active_project != null) {
				return this.project_manager.active_project.path;
			}
			return "";
		}

		public override OLLMchat.Agent.Base create_agent(OLLMchat.History.SessionBase session)
		{
			return new Agent(this, session);
		}

		/**
		 * Loads a pi-prompts template.
		 *
		 * @param filename template file name (e.g. initial.md)
		 * @return loaded template
		 */
		public OLLMchat.Prompt.Template load_prompt(string filename) throws GLib.Error
		{
			var tpl = new OLLMchat.Prompt.Template(filename) {
				source = "resource:///",
				base_dir = "pi-prompts"
			};
			tpl.load();
			return tpl;
		}

		/**
		 * Loads AGENTS.md / CLAUDE.md for the system prompt (uncapped).
		 *
		 * Order: ''~/.local/share/ollmchat/AGENTS.md'', then parent dirs from
		 * outermost under ''$HOME'' to project root. Empty string when nothing
		 * found.
		 *
		 * @param project_path active project path (may be empty)
		 * @return markdown block for ''{agents_md}'', or empty
		 */
		public string build_agents_md(string project_path)
		{
			var paths = new Gee.ArrayList<string>();
			var home = GLib.Environment.get_home_dir();
			var project = project_path.strip();
			if (project != "") {
				this.collect_agents(project, home, paths);
			}

			var global_path = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", "AGENTS.md");
			if (GLib.FileUtils.test(global_path, GLib.FileTest.EXISTS)) {
				paths.insert(0, global_path);
			}

			string[] blocks = {};
			foreach (var path in paths) {
				try {
					uint8[] raw;
					string etag;
					GLib.File.new_for_path(path).load_contents(null, out raw, out etag);
					blocks += "<project_instructions path=\"" + path + "\">\n"
						+ (string) raw + "\n</project_instructions>";
				} catch (GLib.Error e) {
				}
			}
			if (blocks.length == 0) {
				return "";
			}
			return "## Project instructions\n\n" + string.joinv("\n\n", blocks) + "\n";
		}

		/**
		 * Recursively collect context-file paths from ''dir'' up toward ''home''.
		 *
		 * Prefers ''AGENTS.md'', else ''CLAUDE.md''. Inserts at the front
		 * (outer-to-inner). Recurses only while the parent is ''home'' or under
		 * ''home''.
		 *
		 * @param dir directory to scan
		 * @param home do not walk to a parent outside this directory
		 * @param paths collected absolute file paths
		 */
		private void collect_agents(string dir, string home, Gee.ArrayList<string> paths)
		{
			var bare = dir;
			if (bare.has_suffix(GLib.Path.DIR_SEPARATOR_S)) {
				bare = bare.substring(0, bare.length - GLib.Path.DIR_SEPARATOR_S.length);
			}
			var prefix = bare + GLib.Path.DIR_SEPARATOR_S;
			if (GLib.FileUtils.test(prefix + "AGENTS.md", GLib.FileTest.EXISTS)) {
				paths.insert(0, prefix + "AGENTS.md");
			} else if (GLib.FileUtils.test(prefix + "CLAUDE.md", GLib.FileTest.EXISTS)) {
				paths.insert(0, prefix + "CLAUDE.md");
			}
			var parent = GLib.Path.get_dirname(bare);
			if (parent == bare) {
				return;
			}
			if (parent != home && !parent.has_prefix(home + GLib.Path.DIR_SEPARATOR_S)) {
				return;
			}
			this.collect_agents(parent, home, paths);
		}

		/**
		 * Environment block for system prompts (date, OS, shell, workspace).
		 *
		 * @param session session supplying project_path when set
		 * @return markdown bullet list
		 */
		public string build_environment(OLLMchat.History.SessionBase session)
		{
			var ret = "- **Date** - `" + new GLib.DateTime.now_local().format("%Y-%m-%d") + "`";
			var os_info = GLib.Environment.get_os_info("PRETTY_NAME");
			ret += "\n- **OS** - `" + (os_info != null && os_info != "" ? os_info : this.get_os_version()) + "`";
			var shell = this.shell != "" ? this.shell : GLib.Environment.get_variable("SHELL");
			if (shell != null && shell != "") {
				ret += "\n- **Shell** - `" + shell + "`";
			}
			if (session.project_path.strip() != "") {
				ret += "\n- **Workspace** - `" + session.project_path.strip() + "`";
				return ret;
			}
			if (this.project_manager.active_project != null) {
				ret += "\n- **Workspace** - `" + this.project_manager.active_project.path + "`";
			}
			return ret;
		}

		public override async void activate(GLib.Object window)
		{
			var host = (OLLMchat.ChatDesktopInterface) window;
			if (this.widget == null) {
				this.widget = new OLLMcoder.SourceView(this.project_manager);
				host.notification(new OLLMrpc.Notification() {
					method = "client.project.load_start",
				});
				try {
					yield this.widget.manager.load_projects_from_db();
					yield this.widget.manager.restore_active_state();
					yield this.widget.apply_manager_state();
				} catch (GLib.Error e) {
					GLib.warning("Failed to initialize Agent Pi widget: %s", e.message);
				} finally {
					host.notification(new OLLMrpc.Notification() {
						method = "client.project.load_end",
					});
				}
			}
			var widget_id = this.name + "-widget";
			this.widget.name = widget_id;
			var tabs = (Adw.ViewStack) host.tab_view();
			if (tabs.get_child_by_name(widget_id) == null) {
				tabs.add_named(this.widget, widget_id);
			}
			this.widget.visible = true;
			tabs.set_visible_child_name(widget_id);
			host.schedule_pane_update(true);
		}

		public override async void deactivate(GLib.Object window)
		{
			var host = (OLLMchat.ChatDesktopInterface) window;
			host.schedule_pane_update(false);
		}
	}
}
