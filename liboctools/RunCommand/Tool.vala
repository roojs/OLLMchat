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

namespace OLLMtools.RunCommand
{
	/**
	 * Tool for executing terminal commands in the project root directory.
	 * 
	 * Simple commands (single command or cd <path> && <command> with no bash operators)
	 * use permission caching based on resolved executable realpath.
	 * Complex commands (with bash operators or multiple &&) always require approval.
	 */
	public class Tool : OLLMchat.Tool.BaseTool, OLLMchat.Tool.WrapInterface
	{
		
		// Base description (without directory note)
	 
		
		// Base directory for command execution (project directory if available, otherwise home directory)
		public string base_directory {
			get {
				if (this.project_manager != null && this.project_manager.active_project != null) {
					return this.project_manager.active_project.path;
				}
				return GLib.Environment.get_home_dir();
			}
		}
		
	public override string name { get { return "run_command"; } }
	
	public override Type config_class() { return typeof(OLLMchat.Settings.BaseToolConfig); }
			
		public override string description { 
			get {
				return """
Run a terminal command in the project's root directory (or specified working directory) and return the output.

File System Permissions:
- The Run command tool normally works in the project directory and has read-write access to:
  - The project directory - this is the main location that the user will want you to look at and update
  - $HOME/playground (playground directory for cloning repos or creating scratch files) unless the users explitly says look in the playground - assume the user is talking about the project directory
- Everything else is read-only

Network Access:
- By default, this tool does not have access to the network.
- If you require access to the network, you must set the `network` parameter to `true`.
- For fetching websites or web content, you should use the `web_fetch` tool instead of this tool.

If the command fails, you should handle the error gracefully and provide a helpful error message to the user.
""";
			}
		}
		
		public override string parameter_description { get {
			return """
@param command {string} [required] The terminal command to run.
@param working_dir {string} [optional] The working directory where the command will be executed. Should be an absolute path. Defaults to the project directory.
@param network {boolean} [optional] Whether to allow network access. Defaults to false. For fetching websites or web content, use the `web_fetch` tool instead.""";
		} }
		
		/**
		 * ProjectManager instance for accessing project context.
		 * Optional - set to null if not available.
		 */
		public OLLMfiles.ProjectManager? project_manager { get; set; default = null; }
		
	public Tool(OLLMfiles.ProjectManager? project_manager = null)
	{
		base();
		
		this.project_manager = project_manager;
		this.title = "Run Shell Commands Tool";
		// base_directory is now a computed property that checks active_project dynamically
	}
		
		public OLLMchat.Tool.BaseTool clone()
		{
			return new Tool(this.project_manager);
		}
		
		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return Json.gobject_deserialize(typeof(Request), parameters_node) as OLLMchat.Tool.RequestBase;
		}
		
		/**
		 * Implements WrapInterface.deserialize_wrapped() for wrapped tool execution.
		 * 
		 * Extracts the arguments array from JSON parameters, replaces {arguments}
		 * in the command template with the joined arguments, and creates a
		 * RunCommand.Request with the constructed command.
		 * 
		 * @param parameters_node The parameters as a Json.Node
		 * @param command_template The command template with {arguments} placeholder
		 * @return A Request instance or null if deserialization fails
		 */
		public OLLMchat.Tool.RequestBase? deserialize_wrapped(Json.Node parameters_node, string command_template)
		{
			if (parameters_node.get_node_type() != Json.NodeType.OBJECT) {
				return null;
			}
			
			var parameters_obj = parameters_node.get_object();
			
			// Extract arguments array
			if (!parameters_obj.has_member("arguments")) {
				return null;
			}
			
			var arguments_array = parameters_obj.get_array_member("arguments");
			if (arguments_array == null) {
				return null;
			}
			string[] quoted_args = {};
			
			for (uint i = 0; i < arguments_array.get_length(); i++) {
				quoted_args += GLib.Shell.quote(arguments_array.get_string_element(i));
			}
			
			var joined_args = string.joinv(" ", quoted_args);
			
			// Replace {arguments} in template with joined arguments
			var command = command_template.replace("{arguments}", joined_args);
			
			// Create Request with constructed command
			var request = new Request();
			request.command = command;
			request.working_dir = "";
			request.network = false;
			
			return request;
		}
	}
}

