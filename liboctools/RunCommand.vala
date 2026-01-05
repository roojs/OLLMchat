/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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

namespace OLLMtools
{
	/**
	 * Tool for executing terminal commands in the project root directory.
	 * 
	 * Simple commands (single command or cd <path> && <command> with no bash operators)
	 * use permission caching based on resolved executable realpath.
	 * Complex commands (with bash operators or multiple &&) always require approval.
	 */
	public class RunCommand : OLLMchat.Tool.BaseTool
	{
		/**
		 * Sets up the run_command tool configuration with default values.
		 */
		public static void setup_tool_config(OLLMchat.Settings.Config2 config)
		{
			var tool_config = new OLLMchat.Settings.BaseToolConfig();
			try {
				tool_config.title = new RunCommand(
					new OLLMchat.Client(
						new OLLMchat.Settings.Connection() { url = "http://localhost" }
					),
					GLib.Environment.get_home_dir()
				).description.strip().split("\n")[0];
			} catch (GLib.Error e) {
				tool_config.title = "Run a terminal command in the project's root directory and return the output.";
			}
			config.tools.set("run_command", tool_config);
		}
		
		// Base description (without directory note)
		private const string BASE_DESCRIPTION = """
Run a terminal command in the project's root directory and return the output.

You should only run commands that are safe and do not modify the user's system in unexpected ways.

If you are unsure about the safety of a command, ask the user for confirmation before running it.

If the command fails, you should handle the error gracefully and provide a helpful error message to the user.
""";
		
		// Base directory for command execution (hardcoded to home directory)
		public string base_directory { get; private set; }
		
		public override string name { get { return "run_command"; } }
		
		private string _description = "";
		
		public override string description { 
			get {
				if (this._description == "") {
					this._description = BASE_DESCRIPTION + 
					"\n\nCommands are executed in the directory: " +
						 this.base_directory + " unless 'cd' is prefixed to the command.";
				}
				return this._description;
			}
		}
		
		public override string parameter_description { get {
			return """
@param command {string} [required] The terminal command to run.""";
		} }
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
		public RunCommand(OLLMchat.Client? client = null, OLLMfiles.ProjectManager? project_manager = null)
		{
			base(client);
			
			// Hardcode base_directory to home directory
			this.base_directory = GLib.Environment.get_home_dir();
			
			this.project_manager = project_manager;
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(RequestRunCommand), parameters_node) as OLLMchat.Tool.RequestBase;
		}
	}
}

