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

namespace OLLMcoder.AgentPi
{
	/**
	 * One queued chat deliver for {@link Agent}.
	 *
	 * Builds outbound context from ''initial.md'' (AGENTS / Skill / optional
	 * conversation checkpoint) and messages since the latest summary boundary.
	 * After a successful chat turn, may run {@link OLLMchat.Agent.Summarizer}
	 * with ''pi-prompts/compact.md'' when estimated context exceeds the model
	 * window minus a reserve (Pi-style threshold; not every turn).
	 */
	public class PendingMessage : GLib.Object
	{
		public OLLMchat.Message message { get; construct; }
		public GLib.Cancellable? cancellable { get; construct; }
		public Gee.Promise<bool> done { get; construct; }

		/**
		 * @param message user message to append and send
		 * @param cancellable cancel token for the chat request
		 * @param done completion promise for this queue entry
		 */
		public PendingMessage(
			OLLMchat.Message message,
			GLib.Cancellable? cancellable,
			Gee.Promise<bool> done)
		{
			Object(
				message: message,
				cancellable: cancellable,
				done: done
			);
		}

		/**
		 * Append the user message and send context with initial.md.
		 *
		 * @param agent Agent Pi instance for this session
		 */
		public async void run(Agent agent) throws GLib.Error
		{
			agent.session.is_running = true;
			agent.session.manager.agent_status_change();
			agent.session.messages.add(this.message);

			var since_summary = agent.create_summary();
			var summary_text = "";
			if (since_summary.size > 0 && since_summary.get(0).role == "summary") {
				summary_text =
@"## Conversation checkpoint

$(since_summary.get(0).content)

Markdown links such as [#user-1](#user-1) or [#tool-6](#tool-6) refer to stored messages — call session_fetch with that tag (or index) when you need the exact text.

";
				since_summary.remove_at(0);
			}

			var factory = (Factory) agent.session.manager.agent_factories.get(
				agent.session.agent_name);
			var outbound = new Gee.ArrayList<OLLMchat.Message>();
			var tpl = factory.load_prompt("initial.md");
			var project_path = agent.session.project_path.strip();
			if (project_path == "" && factory.project_manager.active_project != null) {
				project_path = factory.project_manager.active_project.path;
			}
			if (project_path == "") {
				project_path = GLib.Environment.get_home_dir();
			}
			var skill_set = new SkillSet();
			skill_set.scan(project_path);
			outbound.add(new OLLMchat.Message("system", tpl.system_fill(
				"environment", factory.build_environment(),
				"cwd", project_path,
				"agents_md", factory.build_agents_md(project_path),
				"skills_md", skill_set.to_prompt(),
				"conversation_summary", summary_text)));

			foreach (var msg in since_summary) {
				outbound.add(msg);
			}

			try {
				yield agent.fill_model();
				yield agent.chat().send(outbound, this.cancellable);
				this.done.set_value(true);

				var ctx = agent.session.model_usage.options.num_ctx;
				if (ctx <= 0 && agent.session.model_usage.model_obj != null) {
					ctx = agent.session.model_usage.model_obj.context_length;
				}
				var estimated = 0;
				foreach (var msg in agent.create_summary()) {
					estimated += msg.content.length / 4;
				}
				if (ctx > 0 && estimated > ctx - 16384) {
					yield (new OLLMchat.Agent.Summarizer(agent) {
						prompt_base_dir = "pi-prompts",
						prompt_filename = "compact.md"
					}).run(new GLib.Cancellable());
				}
			} finally {
				agent.session.is_running = false;
				agent.session.manager.agent_status_change();
			}
		}
	}
}
