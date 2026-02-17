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
	public class Tool : Object
	{
		public weak Details task { get; construct; }
		public string name { get; set; default = ""; }
		public Json.Object? arguments { get; private set; default = null; }
		public string issues { get; set; default = ""; }
		public OLLMchat.Response.ToolCall? tool_call { get; private set; default = null; }

		public Tool(Details task)
		{
			Object(task: task);
		}

		/** Parse block: JSON → name, arguments (uid is assigned by caller via assign_id). Set this.issues on parse failures. */
		public bool parse(Markdown.Document.Block block)
		{
			this.issues = "";
			var body = block.to_markdown().strip();
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
				this.arguments  == null ?  new Json.Object() : this.arguments);
			this.tool_call = new OLLMchat.Response.ToolCall.with_values("", func);
			return true;
		}

		/** Validate: tool_call set, tool registered, required arguments. Append to this.issues for refine feedback. */
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

		/** Instructions for refine stage: name, description, parameters (uses this.name). Call after new Tool(task) { name = tool_name }. */
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

		/** Execute: look up the tool by name, run it with this call's arguments, store the result on the task. */
		public async void execute() throws GLib.Error
		{
			var tool_impl = this.task.chat().tools.get(this.tool_call.function.name);
			var result = yield tool_impl.execute(this.task.chat(), this.tool_call);
			this.task.tool_outputs.set(this.tool_call.id, result);
			this.task.tool_calls.set(this.tool_call.id, this.tool_call);
		}
	}
}
