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
	 * Parsed tool call (refinement) and/or one execution run.
	 *
	 * Refinement: run_id == ""; stored in task.tools. Use parse(), validate(), to_instructions().
	 * Execution run: run_id set; references and optionally tool_call. run() runs the tool (if any)
	 * then the LLM executor; result in summary and document.
	 *
	 * @see Details
	 */
	public class Tool : OLLMchat.Agent.Base
	{
		/** The task (Details) this tool belongs to. */
		public weak Details parent { get; set; }
		/** Execution run id (e.g. "tool-0", "ref-1", "exec"). Empty for refinement-only. */
		public string id { get; set; default = ""; }
		/** Result summary from executor (Result summary section). Set by ResultParser.exec_extract(). */
		public string summary { get; set; default = ""; }
		/** Executor output document. Set by ResultParser.exec_extract() on success. */
		public Markdown.Document.Document? document { get; set; default = null; }
		/** References for this run (one or more). Used by reference_contents() to build executor input. */
		public Gee.ArrayList<Markdown.Document.Format> references { get; set; default = new Gee.ArrayList<Markdown.Document.Format>(); }
		/** Tool execution result from this run. Set in run() when this run has a tool_call. */
		public string tool_run_result { get; set; default = ""; }
		/** Tool name from parsed JSON (e.g. "write_file"). */
		public string name { get; set; default = ""; }
		/** Parsed "arguments" object, or null if absent. Set by parse(). */
		public Json.Object? arguments { get; set; default = null; }
		/** Validation or parse error messages; appended by parse() and validate(). */
		public string issues { get; set; default = ""; }
		/** ToolCall built from name and arguments; set by parse(), used in run() when this run has a tool. */
		public OLLMchat.Response.ToolCall? tool_call { get; set; default = null; }

		/**
		 * Creates a tool for refinement (run_id == "") or an execution run (run_id set).
		 *
		 * @param factory agent factory for this run
		 * @param session session for this run
		 * @param parent the task (Details) this tool belongs to
		 * @param run_id execution run id, or "" for refinement-only
		 */
		public Tool(OLLMchat.Agent.Factory factory, OLLMchat.History.SessionBase session, Details parent, string run_id = "")
		{
			base(factory, session);
			this.parent = parent;
			this.id = run_id;
		}

		/** Reference contents for this run (from this.references). Can be empty. */
		private string reference_contents()
		{
			if (this.references.size == 0) {
				return "";
			}
			string[] parts = {};
			foreach (var link in this.references) {
				var block = this.parent.link_content(link);
				if (block != "") {
					parts += block;
				}
			}
			if (parts.length == 0) {
				return "";
			}
			return "## Reference Contents\n\n" + string.joinv("", parts);
		}

		/** Tool call details for this run: tool call + result. Uses this.tool_run_result; build with parent.header_fenced/header_raw. Empty when no tool_call. */
		private string tool_call_details()
		{
			if (this.tool_call == null) {
				return "";
			}
			var json = Json.gobject_to_data(this.tool_call, null);
			var block = (json != "") ? this.parent.header_fenced("### Tool call " + this.name, json, "json") : "";
			if (this.tool_run_result != "") {
				block += this.parent.header_raw("Tool call " + this.name + " Result", this.tool_run_result);
			}
			return block;
		}

		/**
		 * Run the tool (if any), build reference content + tool output, combine for executor input,
		 * send executor prompt, parse into summary and document. Up to 5 attempts; on failure
		 * appends to parent.issues and throws.
		 */
		public async void run() throws GLib.Error
		{
			this.chat_call.tools.clear();
			var tool_output = "";
			if (this.tool_call != null) {
				var tool_impl = this.parent.runner.session.manager.tools.get(
						this.tool_call.function.name) as OLLMchat.Tool.BaseTool;
				this.tool_run_result = yield tool_impl.execute(this.parent.chat(), this.tool_call, true);
				tool_output = this.tool_call_details();
			}
			var reference_content = this.reference_contents();
			var executor_input = tool_output + reference_content;

			var last_issues = "";
			for (var try_count = 0; try_count < 5; try_count++) {
				var tpl = this.executor_prompt(executor_input, last_issues);
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_text = "";
				try {
					var response = yield this.chat_call.send(messages, null);
					response_text = (response != null) ? response.message.content : "";
				} catch (GLib.Error e) {
					last_issues = e.message;
					if (try_count < 4) {
						this.add_message(new OLLMchat.Message("ui-warning",
							"Executor try %d failed: %s".printf(try_count + 1, last_issues)));
						continue;
					}
					this.parent.issues += "\n" + "Executor failed after 5 tries: " + last_issues;
					throw e;
				}
				var parser = new ResultParser(this.parent.runner, response_text);
				if (parser.exec_extract(this)) {
					return;
				}
				last_issues = parser.issues.strip();
				if (try_count < 4) {
					this.add_message(new OLLMchat.Message("ui-warning", "Executor try %d: %s".printf(try_count + 1, last_issues)));
				}
			}
			this.parent.issues += "\n" + "Executor failed after 5 tries: " + last_issues;
			throw new GLib.IOError.INVALID_ARGUMENT("Task executor: " + last_issues);
		}

		/**
		 * Build executor prompt from task_execution.md.
		 *
		 * What the prompt gets (template placeholders and what we fill):
		 *
		 *   ## What is needed
		 *   {what_is_needed}     <- task_data "What is needed"
		 *
		 *   ## Skill definition
		 *   {skill_definition}   <- this task's skill body
		 *
		 *   ## Project Description
		 *   {project_description} <- active project description (can be empty)
		 *
		 *   ## Tool Output and/or Reference information
		 *   {executor_input}     <- tool_output + reference_content
		 *                            (tool output: this run's or task's; reference content: resolved refs for this run; either can be empty)
		 *
		 *   ## Retry feedback (please address if non-empty)
		 *   {executor_retry_issues} <- previous parse/send issues on retry; empty on first attempt
		 *
		 * The executor interprets the Tool Output and/or Reference information (and other sections) and produces Result summary + body sections.
		 *
		 * @param executor_input combined tool output + reference content for the template
		 * @param previous_issues parse/send issues from last attempt for retry; empty on first attempt
		 */
		private OLLMcoder.Skill.PromptTemplate executor_prompt(string executor_input, string previous_issues = "") throws GLib.Error
		{
			var definition = this.parent.skill_manager.fetch(this.parent);
			var project = this.parent.runner.sr_factory.project_manager.active_project;
			var project_description = (project == null) ? "" : project.project_description();
			var tpl = OLLMcoder.Skill.PromptTemplate.template("task_execution.md");
			tpl.system_fill();
			tpl.fill(
				"what_is_needed", this.parent.task_data.get("What is needed").to_markdown(),
				"skill_definition", definition.body,
				"project_description", project_description,
				"executor_input", executor_input,
				"executor_retry_issues", previous_issues);
			return tpl;
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
			if (!this.parent.runner.session.manager.tools.has_key(this.name)) {
				this.issues += "\n" + "Tool Calls: unknown tool \"" + this.name + "\".";
				return false;
			}
			var original = this.parent.runner.session.manager.tools.get(this.name);
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
			var original = this.parent.runner.session.manager.tools.get(this.name);
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
	}
}
