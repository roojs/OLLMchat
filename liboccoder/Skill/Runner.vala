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
	 * Agent that runs a single skill. Builds system message (template + available skills + current skill)
	 * and user message (template or pass-through); injects them and sends.
	 */
	public class Runner : OLLMchat.Agent.Base
	{
		public Definition skill { get; private set; }
		public Factory sr_factory {
			get { return (Factory) this.factory; }
		}

		/** True once user has approved running writer (modify) tasks this run. */
		public bool writer_approval { get; set; default = false; }
		/** Used by task list flow (send_async(string)); set from template user_to_document(). */
		public Markdown.Document.Document? user_request { get; set; default = null; }
		/** Parsed task list; set by send_async when parse and validate_skills succeed. */
		public OLLMcoder.Task.List? task_list { get; set; default = null; }

		public Runner(Factory factory, OLLMchat.History.SessionBase session)
		{
			base(factory, session);
		}

		/** Used only in send_async when filling task_creation_initial (before user_request exists). */
		public string env()
		{
			var ret = "- **Date** - `" + new GLib.DateTime.now_local().format("%Y-%m-%d") + "`";
			var os_info = GLib.Environment.get_os_info("PRETTY_NAME");
			ret += "\n- **OS** - `" + (os_info != null && os_info != "" ? os_info : "linux") + "`";
			var shell = GLib.Environment.get_variable("SHELL");
			if (shell != null && shell != "") {
				ret += "\n- **Shell** - `" + shell + "`";
			}
			if (this.sr_factory.project_manager.active_project != null) {
				ret += "\n- **Workspace** - `" +
					 this.sr_factory.project_manager.active_project.path + "`";
			}
			return ret;
		}

		/** Resolve non-file reference content for task refs. #anchor → user_request section or task output; http(s) deferred. */
		public string reference_content(string href)
		{
			var anchor = href.has_prefix("#") ? href.substring(1) : "";
			if (anchor != "" && this.user_request != null && this.user_request.headings.has_key(anchor)) {
				return this.user_request.headings.get(anchor).to_markdown_with_content();
			}
			return "";
		}

		public PromptTemplate task_creation_prompt(
			string user_prompt,
			string previous_proposal,
			string previous_proposal_issues,
			OLLMcoder.Skill.Manager skill_catalog, 
			OLLMfiles.ProjectManager project_manager) throws GLib.Error
		{
			var file = project_manager.active_file;
			if (file != null) {
				project_manager.buffer_provider.create_buffer(file);
			}
			var tpl = PromptTemplate.template("task_creation_initial.md");
			tpl.fill(
				"user_prompt", tpl.header_fenced("User Prompt", user_prompt, "text"),
				"environment", tpl.header_raw("Environment", this.env()),
				"project_description", (project_manager.active_project == null ?
					"" : project_manager.active_project.project_description()),
				"current_file", file == null ? "" : tpl.header_file("Current File - " + file.path, file),
				"previous_proposal", previous_proposal == "" ? "" :
					tpl.header_raw("Previous Proposal", previous_proposal),
				"previous_proposal_issues", previous_proposal_issues == "" ? "" :
					tpl.header_raw("Previous Proposal Issues", previous_proposal_issues),
				"skill_catalog", skill_catalog.to_markdown());
			tpl.system_fill("skill_catalog", skill_catalog.to_markdown());
			return tpl;
		}

		private void fill_tools()
		{
			this.chat_call.tools.clear();
		}
 

		/** Entry point. Sends user request only; when finished calls handle_task_list. Current file and open files come from this.project_manager. */
		public async void send_async(string user_prompt, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			var previous_proposal = "";
			var previous_proposal_issues = "";
			for (var try_count = 0; try_count < 5; try_count++) {
				var tpl = this.task_creation_prompt(
					user_prompt, 
					previous_proposal,
					previous_proposal_issues,
					this.sr_factory.skill_manager, 
					this.sr_factory.project_manager);
				this.user_request = tpl.user_to_document();
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_obj = yield this.chat_call.send(messages, cancellable);
				var response = response_obj != null ? response_obj.message.content : "";
				var parser = new OLLMcoder.Task.ResultParser(this, response);
				parser.parse_task_list();
				if (parser.issues == "") {
					var skill_issues = this.task_list.validate_skills();
					if (skill_issues == "") {
						yield this.handle_task_list();
						return;
					}
					parser.issues = skill_issues;
				}
				previous_proposal = parser.proposal;
				previous_proposal_issues = parser.issues;
			}
			this.add_message(new OLLMchat.Message("ui", "Could not build valid task list after 5 tries."));
		}

		/** Deals with the task list only. Called by send_async when it has a valid task_list. */
		private async void handle_task_list() throws GLib.Error
		{
			this.writer_approval = false;
			var hit_max_rounds = true;
			for (var i = 0; i < 5; i++) {
				if (!this.task_list.has_pending_exec()) {
					hit_max_rounds = false;
					break;
				}
				yield this.task_list.refine();
				yield this.task_list.run_until_user_approval();
				if (this.task_list.has_tasks_requiring_approval() && !this.writer_approval) {
					var approved = yield this.request_writer_approval();
					if (!approved) {
						this.add_message(new OLLMchat.Message("ui", "User declined writer approval."));
						return;
					}
					this.writer_approval = true;
				}
				yield this.task_list.run_all_tasks();
				yield this.run_task_list_iteration();
			}
			if (hit_max_rounds && this.task_list.has_pending_exec()) {
				this.add_message(new OLLMchat.Message("ui", "Max rounds reached."));
			}
		}

		/** Stub: request user approval before running writer tasks. Plan: implement UI. */
		private async bool request_writer_approval()
		{
			return true;
		}

		/** Stub: task list iteration. Plan §8: load task_list_iteration.md, fill, send, parse_task_list(), replace this.task_list. */
		public async void run_task_list_iteration() throws GLib.Error
		{
			if (this.task_list == null) {
				return;
			}
		}
	}
}
