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

		/**
		 * Replay cursor: which PhaseEnum the transcript is driving for on_replay.
		 * NONE only until the first wire agent-stage message is applied.
		 */
		private OLLMcoder.Task.PhaseEnum replay_phase { get; set; default = OLLMcoder.Task.PhaseEnum.NONE; }

		/**
		 * When false (default): hydrate task graph from the transcript; rely on
		 * existing task_dir files on disk.
		 * When true: also mirror task-list markdown writes during replay (behaviour
		 * TBC — see on_replay sketch agent-issues placeholders).
		 */
		public bool replay_as_new { get; set; default = false; }

		/**
		 * Index into pending.steps for the step being refined / executed / post_exec'd
		 * in transcript order. Invariant: 0 <= replay_step_pos < pending.steps.size
		 * whenever pending.steps is non-empty. Reset to 0 when a step moves to
		 * completed, or when iteration replaces pending (parse_task_list_iteration).
		 * Initial task-list parse replay does not need explicit reset (defaults are 0).
		 */
		private int replay_step_pos { get; set; default = 0; }

		/**
		 * Index into pending.steps[replay_step_pos].children (each Details) for
		 * REFINEMENT, EXECUTION, EXEC_VALIDATE, POST_EXEC. Invariant:
		 * 0 <= replay_details_pos < current_step.children.size. Advance only while
		 * below children.size - 1 on successful refinement issues; after a step or
		 * list change, clamp or reset using the new children.size.
		 */
		private int replay_details_pos { get; set; default = 0; }

		/**
		 * Index into exec_runs on pending.steps[replay_step_pos].children[replay_details_pos]
		 * during EXECUTION / EXEC_VALIDATE. Invariant:
		 * 0 <= replay_tool_pos < current_details.exec_runs.size. Advance within
		 * that bound on validate success; when past the last run for this Details,
		 * coordinate replay_details_pos / replay_tool_pos with live run_exec using
		 * children.size and exec_runs.size.
		 */
		private int replay_tool_pos { get; set; default = 0; }

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
			if (!this.in_replay) {
				this.session.messages.add(in_message);
			}
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
					if (!this.in_replay) {
						this.session.messages.add(new OLLMchat.Message("system", tpl.filled_system));
						this.session.messages.add(new OLLMchat.Message("user", tpl.filled_user));
					}
					var messages = new Gee.ArrayList<OLLMchat.Message>();
					messages.add(new OLLMchat.Message("system", tpl.filled_system));
					messages.add(new OLLMchat.Message("user", tpl.filled_user));
					// Same wording as Session.send; always emit so retries still show wait after UI frames clear it.
					this.add_message(new OLLMchat.Message("ui-waiting",
						"waiting for " + (this.session.model_usage.model != "" ?
						this.session.model_usage.display_name_with_size() : "Unknown model")
						 + " to reply"));
					this.add_message(new OLLMchat.Message("agent-stage", "task_list_parse"));
					var response_obj = yield this.chat_call.send(messages, cancellable);
					var response = response_obj != null ? response_obj.message.content : "";
					this.replay_step("task_list_parse", response);
					this.pending = new OLLMcoder.Task.List(this);
					var parser = new OLLMcoder.Task.ResultParser(this, response);
					parser.parse_task_list();
					this.add_message(new OLLMchat.Message("agent-issues", parser.issues));
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
			if (!this.session.can_replay) {
				return;
			}
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
			this.in_replay = false;
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
				"completed_task_list", this.completed.to_markdown(OLLMcoder.Task.PhaseEnum.REFINE_COMPLETED),
				"outstanding_task_list", existing_proposed.to_markdown(OLLMcoder.Task.PhaseEnum.LIST),
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
				if (!this.in_replay) {
					this.session.messages.add(new OLLMchat.Message("system", tpl.filled_system));
					this.session.messages.add(new OLLMchat.Message("user", tpl.filled_user));
				}
				this.add_message(new OLLMchat.Message("ui-waiting",
					"waiting for " + model_label + " to reply"));
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				this.add_message(new OLLMchat.Message("agent-stage", "task_list_iteration"));
				var response_obj = yield this.chat_call.send(messages, null);
				response = response_obj != null ? response_obj.message.content : "";

				this.pending = new OLLMcoder.Task.List(this);
				parser = new OLLMcoder.Task.ResultParser(this, response);
				parser.parse_task_list_iteration();
				this.add_message(new OLLMchat.Message("agent-issues", parser.issues));

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
					this.completed.to_markdown(OLLMcoder.Task.PhaseEnum.LIST));
				return;
			}
			if (cancellable != null) {
				cancellable.cancel();
			}
			this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
				"text.oc-frame-danger.collapsed Task list iteration: could not get valid task list after 5 tries",
				parser.issues != "" ? parser.issues.strip() : "")));
		}

		/**
		 * Apply one stored transcript message during GTK session restore. Dispatches on
		 * replay_phase and message role; uses ResultParser on content-stream where live
		 * code would have used the LLM response string.
		 */
		public override void on_replay(OLLMchat.Message m)
		{
			if (!this.session.can_replay) {
				return;
			}

			GLib.debug("session %s phase=%d role=%s step=%d detail=%d tool=%d steps=%u content_len=%u",
				this.session.fid, (int) this.replay_phase, m.role,
				this.replay_step_pos, this.replay_details_pos, this.replay_tool_pos,
				this.pending.steps.size, m.content.length);

			switch (this.replay_phase) {
			case OLLMcoder.Task.PhaseEnum.NONE:
				switch (m.role) {
				case "user-sent":
					try {
						var tpl = this.task_creation_prompt(
							m.content,
							"",
							"",
							this.sr_factory.skill_manager,
							this.sr_factory.project_manager);
						this.user_request = tpl.user_to_document();
					} catch (GLib.Error e) {
						GLib.error("%s", e.message);
					}
					break;
				case "agent-stage":
					// Bootstrap: first wire stages only. Iteration step move is under EXEC_VALIDATE.
					this.replay_phase = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					break;
				default:
					break;
				}
				break;

			case OLLMcoder.Task.PhaseEnum.LIST:
				switch (m.role) {
				case "content-stream":
					this.pending = new OLLMcoder.Task.List(this);
					var p0 = new OLLMcoder.Task.ResultParser(this, m.content);
					p0.parse_task_list();
					GLib.debug("session %s initial_plan steps=%u issues_empty=%s",
						this.session.fid, this.pending.steps.size, (p0.issues == "").to_string());
					break;
				case "agent-stage":
					this.replay_phase = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					break;
				case "agent-issues":
					// this.pending.write("task_list.md", TBC);
					break;
				default:
					break;
				}
				break;

			case OLLMcoder.Task.PhaseEnum.TASK_LIST_ITERATION:
				switch (m.role) {
				case "content-stream":
					this.pending = new OLLMcoder.Task.List(this);
					var p1 = new OLLMcoder.Task.ResultParser(this, m.content);
					p1.parse_task_list_iteration();
					GLib.debug("session %s revised_plan steps=%u issues_empty=%s",
						this.session.fid, this.pending.steps.size, (p1.issues == "").to_string());
					this.replay_step_pos = 0;
					this.replay_details_pos = 0;
					this.replay_tool_pos = 0;
					break;
				case "agent-stage":
					this.replay_phase = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					break;
				case "agent-issues":
					// this.pending.write("task_list_latest.md", TBC);
					// this.pending.write("task_list_completed.md", TBC);
					break;
				default:
					break;
				}
				break;

			case OLLMcoder.Task.PhaseEnum.REFINEMENT:
				switch (m.role) {
				case "content-stream":
					var pr = new OLLMcoder.Task.ResultParser(this, m.content);
					var st_r = this.pending.steps.get(this.replay_step_pos);
					pr.extract_refinement(st_r.children.get(this.replay_details_pos));
					break;
				case "agent-stage":
					var new_ref = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					// Live runs each Details from index 0 after all refinements (List.run_child foreach);
					// refinement replay advances replay_details_pos to the last refined child — reset
					// before the first exec transcript for this step.
					if (new_ref == OLLMcoder.Task.PhaseEnum.EXECUTION) {
						this.replay_details_pos = 0;
						this.replay_tool_pos = 0;
					}
					this.replay_phase = new_ref;
					break;
				case "agent-issues":
					if (m.content != "") {
						break;
					}
					var st_ri = this.pending.steps.get(this.replay_step_pos);
					if (this.replay_details_pos >= st_ri.children.size - 1) {
						break;
					}
					this.replay_details_pos++;
					break;
				default:
					break;
				}
				break;

			case OLLMcoder.Task.PhaseEnum.POST_EXEC:
				switch (m.role) {
				case "content-stream":
					var pp = new OLLMcoder.Task.ResultParser(this, m.content);
					var st_p = this.pending.steps.get(this.replay_step_pos);
					pp.exec_post_extract(st_p.children.get(this.replay_details_pos));
					break;
				case "agent-stage":
					this.replay_phase = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					break;
				case "agent-issues":
					// Align with Details.run_post_exec when issues are empty (live).
					break;
				default:
					break;
				}
				break;

			case OLLMcoder.Task.PhaseEnum.EXECUTION:
				switch (m.role) {
				case "content-stream":
					var st_e = this.pending.steps.get(this.replay_step_pos);
					var d_exec = st_e.children.get(this.replay_details_pos);
					if (d_exec.exec_runs.size == 0) {
						d_exec.build_exec_runs();
					}
					GLib.debug("session %s replay_exec children=%u detail=%d tool=%d exec_runs=%u",
						this.session.fid, st_e.children.size, this.replay_details_pos,
						this.replay_tool_pos, d_exec.exec_runs.size);
					var px = new OLLMcoder.Task.ResultParser(this, m.content);
					px.exec_extract(d_exec.exec_runs.get(this.replay_tool_pos));
					break;
				case "agent-stage":
					this.replay_phase = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					// from_string: exec → EXECUTION, exec_validate → EXEC_VALIDATE.
					break;
				case "agent-issues":
					// Outcome only; next replay_phase comes from the next agent-stage.
					break;
				default:
					break;
				}
				break;

			case OLLMcoder.Task.PhaseEnum.EXEC_VALIDATE:
				switch (m.role) {
				case "agent-stage":
					var new_phase = OLLMcoder.Task.PhaseEnum.from_string(m.content);
					if (new_phase != OLLMcoder.Task.PhaseEnum.TASK_LIST_ITERATION || this.pending.steps.size == 0) {
						this.replay_phase = new_phase;
						break;
					}
					// Same pending → completed move as List.run_step* (List.vala ~218–223).
					var step = this.pending.steps.get(this.replay_step_pos);
					this.completed.steps.add(step);
					step.list = this.completed;
					foreach (var t in step.children) {
						this.completed.slugs.set(t.slug(), t);
					}
					this.pending.steps.remove_at(this.replay_step_pos);
					this.replay_step_pos = 0;
					this.replay_details_pos = 0;
					this.replay_tool_pos = 0;
					this.replay_phase = new_phase;
					break;
				case "agent-issues":
					if (m.content != "") {
						break;
					}
					var st_v = this.pending.steps.get(this.replay_step_pos);
					var det_v = st_v.children.get(this.replay_details_pos);
					if (this.replay_tool_pos < det_v.exec_runs.size - 1) {
						this.replay_tool_pos++;
						break;
					}
					this.replay_tool_pos = 0;
					if (this.replay_details_pos < st_v.children.size - 1) {
						this.replay_details_pos++;
					}
					// Else: finished last run of last task in step — transcript's next agent-stage matches live.
					// Stay on EXEC_VALIDATE until the next agent-stage; do not set NONE here.
					break;
				default:
					break;
				}
				break;
			default:
				break;
			}
		}
	}
}

