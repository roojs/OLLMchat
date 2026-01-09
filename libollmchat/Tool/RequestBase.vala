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

namespace OLLMchat.Tool
{
	/**
	 * Abstract base class for tool request execution.
	 *
	 * Request objects handle all execution concerns: reading parameters,
	 * building permission questions, requesting permissions, and executing
	 * the actual work. Tools are stateless and create Request objects when
	 * execute() is called.
	 *
	 * Request objects are deserialized from the function call parameters JSON,
	 * so parameter properties should match the parameter names from the tool's
	 * function definition.
	 */
	public abstract class RequestBase : Object, Json.Serializable
	{
		/**
		* Reference to the tool that created this request.
		*/
		public BaseTool tool { get; set; }
		
		/**
		* Reference to the agent handler for this tool request.
		* Tools use this to communicate with the UI via the agent.
		* Tools access chat_call via agent.chat.
		*/
		public Prompt.AgentHandler? agent { get; set; }
		
		/**
		 * Permission question text.
		 */
		public string permission_question { get; protected set; default = ""; }
		
		/**
		 * Target path/resource for permission checking.
		 */
		public string permission_target_path { get; protected set; default = ""; }
		
		/**
		 * Operation type for permission checking.
		 */
		public OLLMchat.ChatPermission.Operation permission_operation { get; protected set; default = OLLMchat.ChatPermission.Operation.READ; }
		
		/**
		 * Default constructor.
		 * Request objects are created via Json.gobject_deserialize from parameters JSON.
		 * Tool and agent are set after deserialization.
		 */
		protected RequestBase()
		{
		}
		
		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public virtual bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			// Exclude tool and agent from deserialization (they're set after deserialization)
			switch (property_name) {
				case "tool":
				case "agent":
					value = Value(pspec.value_type);
					return true;
				
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
		
		/**
		 * Normalizes a file path using the permission provider's normalization logic.
		 *
		 * @param path The path to normalize
		 * @return The normalized path
		 */
		protected string normalize_file_path(string in_path)
		{
			var path = in_path;
			// Get permission provider from Manager (shared across all sessions)
			// Permission provider always exists (defaults to Dummy provider)
			var permission_provider = this.agent.session.manager.permission_provider;
			
			// Use permission provider's normalize_path if accessible, otherwise do basic normalization
			if (!GLib.Path.is_absolute(path) && permission_provider.relative_path != "") {
				path = GLib.Path.build_filename(permission_provider.relative_path, path);
			}
			// if it's still absolute - return it we might have to fail at this point..
			// llm should send valid paths, we should not try and solve it.
			 
			return path;
		}
		
		/**
		 * Send a UI message in standardized codeblock format.
		 *
		 * @param type The codeblock type (e.g., "txt", "markdown")
		 * @param title The title/header for the message (e.g., "Read file Response")
		 * @param body The message body content
		 */
		protected void send_ui(string type, string title, string body)
		{
			// Escape code blocks in body to prevent breaking the outer codeblock
			var escaped_body = body.replace("\n```", "\n\\`\\`\\`");
			var message = "```" + type + " " + title + "\n" + escaped_body + "\n```";
			var ui_msg = new OLLMchat.Message(this.agent.chat, "ui", message);
			
			// Add message to session via agent (Chat → Agent → Session)
			this.agent.session.add_message(ui_msg);
		}
		
		/**
		 * Abstract method for requests to build permission information.
		 *
		 * Requests implement this method to build permission information
		 * from their specific parameters. Sets permission_question, permission_target_path,
		 * and permission_operation properties.
		 *
		 * @return true if permission needs to be asked, false if permission check can be skipped
		 */
		protected abstract bool build_perm_question();
		
		/**
		 * Public method that handles permission checking before execution.
		 *
		 * Calls read_params() to read parameters, then build_perm_question() to populate permission properties,
		 * checks permission if needed, and finally calls execute_request() to perform the actual operation.
		 *
		 * @return String result or error message (prefixed with "ERROR: " for errors)
		 */
		public virtual async string execute()
		{
			// Parameters are already deserialized in constructor
			// Check permission if needed
			if (this.build_perm_question()) {
				GLib.debug("RequestBase.execute: Tool '%s' requires permission: '%s'", this.tool.name, this.permission_question);
				
			// Get permission provider from Manager (shared across all sessions)
			var permission_provider = this.agent.session.manager.permission_provider;
			GLib.debug("RequestBase.execute: Tool '%s' using permission_provider=%p (%s) from Manager", 
				this.tool.name, permission_provider, permission_provider.get_type().name());
				
				if (!(yield permission_provider.request(this))) {
					GLib.debug("RequestBase.execute: Permission denied for tool '%s'", this.tool.name);
					return "ERROR: Permission denied: " + this.permission_question;
				}
				GLib.debug("RequestBase.execute: Permission granted for tool '%s'", this.tool.name);
			} else {
				GLib.debug("RequestBase.execute: Tool '%s' does not require permission", this.tool.name);
			}
			
			// Execute the request
			try {
				var result = yield this.execute_request();
				GLib.debug("RequestBase.execute: Tool '%s' executed successfully, result length: %zu", this.tool.name, result.length);
				return result;
			} catch (Error e) {
				GLib.debug("RequestBase.execute: Tool '%s' threw error: %s", this.tool.name, e.message);
				return "ERROR: " + e.message;
			}
		}
		
		/**
		 * Abstract method for requests to implement their actual execution logic.
		 *
		 * This method contains the request-specific implementation that performs
		 * the actual operation after permission has been granted.
		 *
		 * @return String content result (will be wrapped in JSON by execute())
		 */
		protected abstract async string execute_request() throws Error;
	}
}
