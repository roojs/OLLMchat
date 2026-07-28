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
 * Phase 0 is chat-only (full transcript). Context hygiene is deferred —
 * see study plan Phase 5 Option C. Phase 1 injects AGENTS.md via
 * {@link Factory.build_agents_md}.
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
		 * Append the user message and send full session context with initial.md.
		 *
		 * @param agent Agent Pi instance for this session
		 */
		public async void run(Agent agent) throws GLib.Error
		{
			agent.session.is_running = true;
			agent.session.manager.agent_status_change();
			agent.session.messages.add(this.message);

			var factory = (Factory) agent.session.manager.agent_factories.get(
				agent.session.agent_name);
			var outbound = new Gee.ArrayList<OLLMchat.Message>();
			var tpl = factory.load_prompt("initial.md");
			var project_path = agent.session.project_path.strip();
			if (project_path == "" && factory.project_manager.active_project != null) {
				project_path = factory.project_manager.active_project.path;
			}
			outbound.add(new OLLMchat.Message("system", tpl.system_fill(
				"environment", factory.build_environment(agent.session),
				"agents_md", factory.build_agents_md(project_path))));

			foreach (var msg in agent.create_summary()) {
				if (msg.role == "summary") {
					continue;
				}
				outbound.add(msg);
			}

			try {
				yield agent.fill_model();
				yield agent.chat().send(outbound, this.cancellable);
				this.done.set_value(true);
			} finally {
				agent.session.is_running = false;
				agent.session.manager.agent_status_change();
			}
		}
	}
}
