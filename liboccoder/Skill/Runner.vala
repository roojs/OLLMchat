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
	 * Agent that runs a single skill. Builds system message (template + available
	 * skills + current skill) and user message (template or pass-through);
	 * injects them and sends.
	 */
	public class Runner : OLLMchat.Agent.Base
	{
		public Definition skill { get; private set; }
		public Factory sr_factory {
			get { return (Factory) this.factory; }
		}

		/**
		 * True once user has approved running writer (modify) tasks this run.
		 */
		public bool writer_approval { get; set; default = false; }
		/**
		 * Used by task list flow (send_async(string)); set from template user_to_document().
		 */
		public Markdown.Document.Document? user_request { get; set; default = null; }
		/**
		 * Tasks that have gone through execution (unchanged reference data).
		 */
		public OLLMcoder.Task.List completed { get; private set; }
		/**
		 * Tasks to be run (initial plan or new/revised from iteration). Only this list is ever run.
		 */
		public OLLMcoder.Task.List pending { get; set; }

		public Runner(Factory factory, OLLMchat.History.SessionBase session)
		{
			base(factory, session);
			this.completed = new OLLMcoder.Task.List(this);
			this.pending = new OLLMcoder.Task.List(this);
		}

		/**
		 * Used only in send_async when filling task_creation_initial (before user_request exists).
		 */
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

		/**
		 * Resolve non-file reference content for task refs, document anchor, or http (deferred).
		 * Task scheme: lookup slug in completed then pending; resolve only by fragment
		 * ({{{ task://slug.md#section }}}). Whole-document ref with no hash returns "".
		 * Path empty: use link hash as anchor in user_request.
		 *
		 * @param link the reference link (scheme, path, href, hash already parsed)
		 * @return resolved content for the link, or "" if not found or not applicable
		 */
		public string reference_content(Markdown.Document.Format link)
		{
			if (link.scheme == "task") {
				var slug = link.path.has_suffix(".md") ? 
					link.path.substring(0, link.path.length - 3) : link.path;
				var task = this.completed.slugs.has_key(slug) ? 
					this.completed.slugs.get(slug) : this.pending.slugs.get(slug);
				var run = task.exec_runs.get(0);
				return run.document.headings.get(link.hash).to_markdown_with_content();
			}
			if (link.path == "") {
				var anchor = link.hash;
				if (anchor == "") {
					return "";
				}
				if (this.user_request != null && this.user_request.headings.has_key(anchor)) {
					return this.user_request.headings.get(anchor).to_markdown_with_content();
				}
				return "";
			}
			if (link.scheme == "http" || link.scheme == "https") {
				return "";
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
			skill_catalog.scan();
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
 

		/**
		 * Entry point. Sends user request only; when finished calls handle_task_list.
		 * Current file and open files come from this.project_manager.
		 */
		public override async void send_async(OLLMchat.Message in_message, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			this.session.messages.add(in_message);
			this.session.is_running = true;
			this.session.manager.agent_status_change();
			try {
				var previous_proposal = "";
				var previous_proposal_issues = "";
				for (var try_count = 0; try_count < 5; try_count++) {
					var tpl = this.task_creation_prompt(
						in_message.content,
						previous_proposal,
						previous_proposal_issues,
						this.sr_factory.skill_manager,
						this.sr_factory.project_manager);
					this.user_request = tpl.user_to_document();
					this.fill_tools(); // (clears tools)
					var messages = new Gee.ArrayList<OLLMchat.Message>();
					messages.add(new OLLMchat.Message("system", tpl.filled_system));
					messages.add(new OLLMchat.Message("user", tpl.filled_user));
					var response_obj = yield this.chat_call.send(messages, cancellable);
					var response = response_obj != null ? response_obj.message.content : "";
					var parser = new OLLMcoder.Task.ResultParser(this, response);
					parser.parse_task_list();
					if (parser.issues == "") {
						var skill_issues = this.pending.validate_skills();
						if (skill_issues == "") {
							yield this.handle_task_list(cancellable);
							return;
						}
						parser.issues = skill_issues;
					}
					previous_proposal = parser.proposal;
					previous_proposal_issues = parser.issues;
					if (try_count < 4) {
						this.add_message(new OLLMchat.Message("ui-warning",
							"Task list had issues (retrying):\n\n" + previous_proposal_issues.strip()));
					}
				}
				var fail_msg = "Could not build valid task list after 5 tries.";
				if (previous_proposal_issues != "") {
					fail_msg += "\n\nIssues:\n" + previous_proposal_issues.strip();
				}
				this.add_message(new OLLMchat.Message("ui-warning", fail_msg));
			} finally {
				this.session.is_running = false;
				this.session.manager.agent_status_change();
				GLib.debug("Runner.send_async: is_running=false session %s", this.session.fid);
			}
		}

		/**
		 * Deals with the task list only. Called by send_async when it has a valid pending list.
		 */
		private async void handle_task_list(GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			this.writer_approval = false;
			var hit_max_rounds = true;
			for (var i = 0; i < 20; i++) {
				if (cancellable != null && cancellable.is_cancelled()) {
					this.add_message(new OLLMchat.Message("ui", "User cancelled request"));
					this.session.is_running = false;
					this.session.manager.agent_status_change();
					return;
				}
				if (this.pending.steps.size == 0) {
					hit_max_rounds = false;
					break;
				}
				var model_label = this.session.model_usage.model != "" ? this.session.model_usage.display_name_with_size() : "";
				var model_part = model_label != "" ? " with (%s)".printf(model_label) : "";
				this.add_message(new OLLMchat.Message("ui-waiting", "Refining tasks" + model_part));
				yield this.pending.refine(cancellable);
				yield this.pending.run_step_until_approval();
				if (this.pending.steps.size == 0) {
					hit_max_rounds = false;
					break;
				}
				if (this.pending.has_tasks_requiring_approval() && !this.writer_approval) {
					var approved = yield this.request_writer_approval();
					if (!approved) {
						this.add_message(new OLLMchat.Message("ui", "User declined writer approval."));
						this.session.is_running = false;
						this.session.manager.agent_status_change();
						return;
					}
					this.writer_approval = true;
				}
				yield this.pending.run_step();
				if (this.pending.steps.size == 0) {
					hit_max_rounds = false;
					break;
				}
			}
			if (hit_max_rounds && this.pending.steps.size > 0) {
				this.add_message(new OLLMchat.Message("ui", "Max rounds reached."));
			}
		}

		/**
		 * Stub: request user approval before running writer tasks. Plan: implement UI.
		 */
		private async bool request_writer_approval()
		{
			return true;
		}

		/**
		 * Build the task list iteration prompt (task_list_iteration.md).
		 * Uses completed and existing_proposed (outstanding) and optional previous_proposed_md when retrying.
		 *
		 * @param previous_proposal_issues issues from last iteration parse/validation (empty when not retrying)
		 * @param existing_proposed the current outstanding task list (pending before this iteration)
		 * @param previous_proposed_md raw LLM response from last iteration when retrying; empty string when not
		 */
		public PromptTemplate iteration_prompt(string previous_proposal_issues,
			OLLMcoder.Task.List existing_proposed,
			string previous_proposed_md) throws GLib.Error
		{
			this.sr_factory.skill_manager.scan();
			var tpl = PromptTemplate.template("task_list_iteration.md");
			tpl.system_fill("skill_catalog", this.sr_factory.skill_manager.to_markdown());
			tpl.fill(
				"completed_task_list", this.completed.to_markdown(OLLMcoder.Task.MarkdownPhase.REFINE_COMPLETED),
				"outstanding_task_list", existing_proposed.to_markdown(OLLMcoder.Task.MarkdownPhase.LIST),
				"previous_proposed_task_list", previous_proposed_md == "" ? "" :
					tpl.header_raw("Proposed (your last response — had issues)", previous_proposed_md),
				"environment", tpl.header_raw("Environment", this.env()),
				"project_description", this.sr_factory.project_manager.active_project == null ? "" :
					this.sr_factory.project_manager.active_project.project_description(),
				"previous_proposal_issues", previous_proposal_issues == "" ? "" :
					tpl.header_raw("Issues with the tasks", previous_proposal_issues));
			return tpl;
		}

		/**
		 * Task list iteration: send current list to LLM, parse response into this.pending.
		 * On parse/validation failure restores this.pending = existing_proposed; uses raw
		 * LLM response as previous_proposed_md on retry.
		 */
		public async void run_task_list_iteration() throws GLib.Error
		{
			var existing_proposed = this.pending;
			var response = "";
			var parser = new OLLMcoder.Task.ResultParser(this, "");

			for (var try_count = 0; try_count < 5; try_count++) {
				var tpl = this.iteration_prompt(parser.issues, existing_proposed, response);
				this.fill_tools(); // (clears tools)
				var model_label = this.session.model_usage.model != "" ? this.session.model_usage.display_name_with_size() : "";
				var model_part = model_label != "" ? " with (%s)".printf(model_label) : "";
				this.add_message(new OLLMchat.Message("ui-waiting", "Refining task list" + model_part));
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_obj = yield this.chat_call.send(messages, null);
				response = response_obj != null ? response_obj.message.content : "";

				parser = new OLLMcoder.Task.ResultParser(this, response);
				parser.parse_task_list_iteration();

				if (parser.issues != "") {
					this.pending = existing_proposed;
					this.add_message(new OLLMchat.Message("ui-warning",
						"Task list iteration had issues:\n\n" + parser.issues.strip()));
					continue;
				}
				var skill_issues = this.pending.validate_skills();
				if (skill_issues == "") {
					this.pending.goals_summary_md = existing_proposed.goals_summary_md;
					return;
				}
				parser.issues = skill_issues;
				this.pending = existing_proposed;
				this.add_message(new OLLMchat.Message("ui-warning",
					"Task list iteration had issues:\n\n" + skill_issues.strip()));
				continue;
			}
			var fail_msg = "Task list iteration: could not get valid task list after 5 tries.";
			if (parser.issues != "") {
				fail_msg += "\n\nIssues:\n" + parser.issues.strip();
			}
			this.add_message(new OLLMchat.Message("ui-warning", fail_msg));
		}
	}
}

