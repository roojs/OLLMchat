/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMcoder.Task
{
	/**
	 * One tool call parsed from a ## Tool Calls fenced block during refinement.
	 * Holds name, arguments, and the ToolCall for execution. Validation and
	 * execution use the manager's tool registry; the task agent never attaches
	 * tools to chat_call.
	 *
	 * @see Details
	 * @see ResultParser
	 */
	public class Tool : Object
	{
		/**
		 * The task that owns this tool call.
		 */
		public weak Details task { get; construct; }
		/**
		 * Tool name from the parsed JSON (e.g. "write_file").
		 */
		public string name { get; set; default = ""; }
		/**
		 * Parsed "arguments" object, or null if absent.
		 */
		public Json.Object? arguments { get; private set; default = null; }
		/**
		 * Validation or parse error messages; appended by parse() and validate().
		 */
		public string issues { get; set; default = ""; }
		/**
		 * ToolCall built from name and arguments; set by parse(), used by execute().
		 */
		public OLLMchat.Response.ToolCall? tool_call { get; private set; default = null; }

		/**
		 * Creates a tool call for the given task. Call parse() to fill name,
		 * arguments, and tool_call from a fenced block.
		 *
		 * @param task The task this tool call belongs to
		 */
		public Tool(Details task)
		{
			Object(task: task);
		}

		/**
		 * Parses a fenced block: expects JSON with "name" and optional "arguments".
		 * Sets this.name, this.arguments, and this.tool_call (uid is assigned by
		 * caller via assign_id). Appends to this.issues on parse failures.
		 *
		 * @param block The code block containing the tool call JSON
		 * @return true if parsing succeeded
		 */
		public bool parse(Markdown.Document.Block block)
		{
			this.issues = "";
			var body = block.code_text.strip();
			Json.Parser p = new Json.Parser();
			try {
				p.load_from_data(body);
			} catch (GLib.Error e) {
				this.issues += "\n" + "Tool Calls: invalid JSON in block: " + e.message;
				return false;
			}
			var root = p.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				this.issues += "\n" + "Tool Calls: each block must be a JSON object with name and optional arguments.";
				return false;
			}
			var obj = root.get_object();
			this.name = obj.has_member("name") ? obj.get_string_member("name") : "";
			if (this.name == "") {
				this.issues += "\n" + "Tool Calls: each block must have non-empty \"name\".";
				return false;
			}
			if (obj.has_member("arguments") && obj.get_member("arguments").get_node_type() == Json.NodeType.OBJECT) {
				this.arguments = obj.get_object_member("arguments");
			}
			var func = new OLLMchat.Response.CallFunction.with_values(this.name,
				this.arguments == null ? new Json.Object() : this.arguments);
			this.tool_call = new OLLMchat.Response.ToolCall.with_values("", func);
			return true;
		}

		/**
		 * Validates that tool_call is set, the tool is registered on the manager,
		 * and required arguments are present. Appends to this.issues for refine
		 * feedback.
		 *
		 * @return false if validation failed
		 */
		public bool validate()
		{
			this.issues = "";
			if (this.tool_call == null) {
				this.issues += "\n" + "Tool Calls: block did not parse as a valid tool call (invalid JSON or missing name).";
				return false;
			}
			if (!this.task.runner.session.manager.tools.has_key(this.name)) {
				this.issues += "\n" + "Tool Calls: unknown tool \"" + this.name + "\".";
				return false;
			}
			var original = this.task.runner.session.manager.tools.get(this.name);
			if (!(original is OLLMchat.Tool.BaseTool)) {
				return true;
			}
			var base_tool = (OLLMchat.Tool.BaseTool) original;
			var params = base_tool.function.parameters;
			if (params == null) {
				return true;
			}
			foreach (var param in params.properties) {
				if (!param.required) {
					continue;
				}
				if (this.arguments != null && this.arguments.has_member(param.name)) {
					continue;
				}
				this.issues += "\n" + "Tool Calls: tool \"" + this.name + "\" requires argument \"" + param.name + "\".";
				return false;
			}
			return true;
		}

		/**
		 * Returns instructions for the refine stage: tool name, description, and
		 * parameters. Uses this.name to look up the tool from the manager. Call
		 * after constructing the Tool with name set.
		 *
		 * @return JSON schema string for the tool (name, description, parameters)
		 */
		public string to_instructions()
		{
			var original = this.task.runner.session.manager.tools.get(this.name);
			var base_tool = (OLLMchat.Tool.BaseTool) original;
			var schema = new Json.Object();
			schema.set_string_member("name", base_tool.function.name);
			schema.set_string_member("description", base_tool.function.description);
			var param_node = Json.gobject_serialize(base_tool.function.parameters);
			param_node.get_object().set_string_member("type", base_tool.function.parameters.x_type);
			schema.set_object_member("parameters", param_node.get_object());
			var root = new Json.Node(Json.NodeType.OBJECT);
			root.set_object(schema);
			var gen = new Json.Generator();
			gen.set_root(root);
			var ret = gen.to_data(null);
			if (base_tool.example_call != "") {
				ret += "\nExample: " + base_tool.example_call;
			}
			return ret;
		}

		/**
		 * Executes the tool call: looks up the tool from the manager (the agent
		 * never uses chat_call.tools), runs it with this call's arguments, and
		 * stores the result on the task.
		 */
		public async void execute() throws GLib.Error
		{
			var tool_impl = this.task.runner.session.manager.tools.get(this.tool_call.function.name) as OLLMchat.Tool.BaseTool;
			var result = yield tool_impl.execute(this.task.chat(), this.tool_call, true);
			this.task.tool_outputs.set(this.tool_call.id, result);
			this.task.tool_calls.set(this.tool_call.id, this.tool_call);
		}
	}
}
