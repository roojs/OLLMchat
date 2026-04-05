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
	 * Agent that runs a single skill. Builds system message (template +
	 * available skills + current skill) and user message (template or
	 * pass-through); injects them and sends.
	 *
	 * @see OLLMchat.Agent.Base
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
		 * Used by task list flow (send_async); set from template
		 * user_to_document().
		 */
		public Markdown.Document.Document? user_request { get; set; default = null; }
		/**
		 * Tasks that have gone through execution (unchanged reference data).
		 */
		public OLLMcoder.Task.List completed { get; private set; }
		/**
		 * Tasks to be run (initial plan or new/revised from iteration).
		 * Only this list is ever run.
		 */
		public OLLMcoder.Task.List pending { get; set; }

		/**
		 * True when running from a replay session. When set, Details and Tool use
		 * the runner's chat_call (ReplayChat) instead of their own.
		 */
		public bool in_replay { get; set; default = false; }

		// Filled by ResolveLink.preload_http; read by ResolveLink.resolve (http). Dedupe skips refetch (no clear).
		internal Gee.HashMap<string, string> http_cache
			 { get; default = new Gee.HashMap<string, string>(); }

		/**
		 * Emitted during replay before each logical step. Arguments: step name and
		 * content (e.g. raw text being parsed; empty string when none). Listeners
		 * can show content and wait for user (e.g. Enter) before returning.
		 */
		public signal void replay_step(string step, string content);

		public Runner(Factory factory, OLLMchat.History.SessionBase session)
		{
			base(factory, session);
			this.completed = new OLLMcoder.Task.List(this);
			this.pending = new OLLMcoder.Task.List(this);
		}

		/**
		 * Used only in send_async when filling task_creation_initial
		 * (before user_request exists).
		 *
		 * @return environment section text (date, OS, shell, workspace)
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
		 * Build the task creation prompt (task_creation_initial.md).
		 * Used by send_async before user_request exists.
		 *
		 * @param user_prompt raw user message content
		 * @param previous_proposal previous LLM output when retrying
		 * @param previous_proposal_issues parse/validation issues when
		 *        retrying
		 * @param skill_catalog manager for skill list
		 * @param project_manager for env, project description, current
		 *        file
		 * @return filled template
		 */
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
			tpl.fill(7,
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
			tpl.system_fill(1, "skill_catalog", skill_catalog.to_markdown());
			return tpl;
		}

		/**
		 * Clear chat_call.tools so task creation and iteration requests
		 * are sent as plain chat (no tool definitions).
		 */
		private void fill_tools()
		{
			this.chat_call.tools.clear();
		}
 

		/**
		 * Entry point. Sends user request only; when finished calls
		 * handle_task_list. Current file and open files come from
		 * this.project_manager.
		 *
		 * @param in_message user message to send
		 * @param cancellable optional cancellable
		 */
		public override async void send_async(OLLMchat.Message in_message, GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			if (this.sr_factory.project_manager.active_project == null) {
				throw new OLLMchat.OllmError.INVALID_ARGUMENT(
					"No project selected. Please select a project from the dropdown before sending.");
			}
			if (this.session.project_path == "" && this.sr_factory.project_manager.active_project != null) {
				this.session.project_path = this.sr_factory.project_manager.active_project.path;
			}
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
					this.session.messages.add(new OLLMchat.Message("system", tpl.filled_system));
					this.session.messages.add(new OLLMchat.Message("user", tpl.filled_user));
					var messages = new Gee.ArrayList<OLLMchat.Message>();
					messages.add(new OLLMchat.Message("system", tpl.filled_system));
					messages.add(new OLLMchat.Message("user", tpl.filled_user));
					// Same wording as Session.send; always emit so retries still show wait after UI frames clear it.
					this.add_message(new OLLMchat.Message("ui-waiting",
						"waiting for " + (this.session.model_usage.model != "" ?
						this.session.model_usage.display_name_with_size() : "Unknown model") + " to reply"));
					var response_obj = yield this.chat_call.send(messages, cancellable);
					var response = response_obj != null ? response_obj.message.content : "";
					this.replay_step("task_list_parse", response);
					this.pending = new OLLMcoder.Task.List(this);
					var parser = new OLLMcoder.Task.ResultParser(this, response);
					parser.parse_task_list();
					if (this.in_replay) {
						((OLLMchat.Call.ReplayChat) this.chat_call).report_replay_outcome(parser.issues);
					}
					if (parser.issues == "") {
						this.pending.write("task_list.md", response);
						yield this.handle_task_list(cancellable);
						return;
					}
					previous_proposal = parser.proposal;
					var try_label = "[try %d] ".printf(try_count + 1);
					previous_proposal_issues = try_label + parser.issues.strip();
					this.replay_step("task_list_parse_issues",
						response + "\n\nParse issues:\n" + parser.issues);
					if (try_count < 4) {
						this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
							"text.oc-frame-warning.collapsed Task list had issues (retrying)",
							previous_proposal_issues)));
					}
				}
				if (cancellable != null) {
					cancellable.cancel();
				}
				this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
					"text.oc-frame-danger.collapsed Could not build valid task list after 5 tries",
					previous_proposal_issues != "" ? previous_proposal_issues.strip() : "")));
			} finally {
				this.session.is_running = false;
				this.session.manager.agent_status_change();
				GLib.debug("Runner.send_async: is_running=false session %s", this.session.fid);
			}
		}

		/**
		 * Replay the task-list flow using the session's raw message list.
		 * Swaps in ReplayChat and calls send_async so the same code path runs
		 * (task creation retry loop, parse, handle_task_list). ReplayChat returns
		 * the next session content message on each send().
		 *
		 * @param messages session message list (ui, system, project, etc. are skipped by ReplayChat)
		 */
		public async void replay(Gee.ArrayList<OLLMchat.Message> messages)
		{
			this.in_replay = true;
			var replay_chat = new OLLMchat.Call.ReplayChat(
				this.chat_call.connection,
				this.session.model_usage.model,
				messages);
			replay_chat.agent = this;
			replay_chat.tools = this.chat_call.tools;
			this.replace_chat(replay_chat);
			try {
				yield this.send_async(new OLLMchat.Message("user-sent", ""), null);
			} catch (GLib.Error e) {
				GLib.printerr("Replay failed: %s\n", e.message);
				Process.exit(1);
			}
		}

		/**
		 * Deals with the task list only. Called by send_async when it has
		 * a valid pending list.
		 *
		 * @param cancellable optional cancellable
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
					this.add_message(new OLLMchat.Message("ui", "Task list complete (no more steps)."));
					break;
				}
				this.add_message(new OLLMchat.Message("ui-waiting",
					"waiting for " + (this.session.model_usage.model != "" ?
					this.session.model_usage.display_name_with_size() : "Unknown model") + " to reply"));
				yield this.pending.refine(cancellable);
				var step_done = yield this.pending.run_step_until_approval();
				if (step_done) {
					yield this.run_task_list_iteration(cancellable);
				}
				if (this.pending.steps.size == 0) {
					hit_max_rounds = false;
					this.add_message(new OLLMchat.Message("ui", "Task list complete (no more steps)."));
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
				// Refine the (new) first step before run_step; after run_task_list_iteration the list was replaced and the new first step was not refined yet.
				this.add_message(new OLLMchat.Message("ui-waiting",
					"waiting for " + (this.session.model_usage.model != "" ?
					this.session.model_usage.display_name_with_size() : "Unknown model") + " to reply"));
				yield this.pending.refine(cancellable);
				step_done = yield this.pending.run_step();
				if (step_done) {
					yield this.run_task_list_iteration(cancellable);
				}
				if (this.pending.steps.size == 0) {
					hit_max_rounds = false;
					this.add_message(new OLLMchat.Message("ui", "Task list complete (no more steps)."));
					break;
				}
				/* Next iteration: refine and run this.pending (the new list)'s first step. */
			}
			if (hit_max_rounds && this.pending.steps.size > 0) {
				this.add_message(new OLLMchat.Message("ui", "Max rounds reached."));
			}
		}

		/**
		 * Stub: request user approval before running writer tasks.
		 * TODO: wire approval UI.
		 *
		 * @return true if approved (currently always true)
		 */
		private async bool request_writer_approval()
		{
			return true;
		}

		/**
		 * Build the task list iteration prompt (task_list_iteration.md).
		 * Uses completed and existing_proposed (outstanding) and optional
		 * previous_proposed_md when retrying.
		 *
		 * @param previous_proposal_issues issues from last iteration
		 *        parse/validation (empty when not retrying)
		 * @param existing_proposed the current outstanding task list
		 *        (pending before this iteration)
		 * @param previous_proposed_md raw LLM response from last
		 *        iteration when retrying; empty string when not
		 * @return filled template
		 */
		public PromptTemplate iteration_prompt(string previous_proposal_issues,
			OLLMcoder.Task.List existing_proposed,
			string previous_proposed_md) throws GLib.Error
		{
			this.sr_factory.skill_manager.scan();
			var tpl = PromptTemplate.template("task_list_iteration.md");
			tpl.system_fill(1, "skill_catalog", this.sr_factory.skill_manager.to_markdown());
			tpl.fill(6,
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
		 * Task list iteration: send current list to LLM, parse response
		 * into this.pending. On parse/validation failure restores
		 * this.pending = existing_proposed; uses raw LLM response as
		 * previous_proposed for next retry.
		 * On failure after 5 tries, cancels the given cancellable so the
		 * whole request stops (no way to carry on).
		 *
		 * @param cancellable optional; cancelled on unrecoverable failure
		 */
		public async void run_task_list_iteration(GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			var existing_proposed = this.pending;
			var response = "";
			var parser = new OLLMcoder.Task.ResultParser(this, "");

			for (var try_count = 0; try_count < 5; try_count++) {
				var tpl = this.iteration_prompt(parser.issues, existing_proposed, response);
				this.fill_tools(); // (clears tools)
				if (try_count > 0) {
					this.add_message(new OLLMchat.Message("ui",
						"Trying again (attempt %d/5). Sending revised task list to LLM with issues feedback.".printf(try_count + 1)));
				}
				var model_label = this.session.model_usage.model != "" ?
					this.session.model_usage.display_name_with_size() : "Unknown model";
				// Show user message only in UI (same as Task.Tool executor); system prompt must not appear in chat.
				this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
					"markdown.oc-frame-info.collapsed " + (try_count > 0 ?
					"Sending revised task list to LLM" : "Reviewing and updating task list") + " with " + model_label,
					tpl.filled_user)));
				this.session.messages.add(new OLLMchat.Message("system", tpl.filled_system));
				this.session.messages.add(new OLLMchat.Message("user", tpl.filled_user));
				this.add_message(new OLLMchat.Message("ui-waiting",
					"waiting for " + model_label + " to reply"));
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_obj = yield this.chat_call.send(messages, null);
				response = response_obj != null ? response_obj.message.content : "";

				this.pending = new OLLMcoder.Task.List(this);
				parser = new OLLMcoder.Task.ResultParser(this, response);
				parser.parse_task_list_iteration();

				if (parser.issues != "") {
					this.replay_step("iteration_parse_issues",
						response + "\n\nParse issues:\n" + parser.issues);
					this.pending = existing_proposed;
					this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
						"text.oc-frame-warning.collapsed Task list iteration had issues",
						parser.issues.strip())));
					continue;
				}
				this.pending.goals_summary_md = existing_proposed.goals_summary_md;
				this.pending.write("task_list_latest.md", response);
				this.pending.write("task_list_completed.md",
					this.completed.to_markdown(OLLMcoder.Task.MarkdownPhase.LIST));
				return;
			}
			if (cancellable != null) {
				cancellable.cancel();
			}
			this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
				"text.oc-frame-danger.collapsed Task list iteration: could not get valid task list after 5 tries",
				parser.issues != "" ? parser.issues.strip() : "")));
		}
	}
}

