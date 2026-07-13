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

namespace OLLMchat.Chatter
{
	/**
	 * One queued chat or summarize step. {@link run} relays by {@link is_chat};
	 * queue drain lives on {@link Agent.send_async}.
	 */
	public class PendingMessage : GLib.Object
	{
		public bool is_chat { get; construct; default = true; }
		public Message? message { get; construct; }
		public GLib.Cancellable? cancellable { get; construct; }
		public Gee.Promise<bool> done { get; construct; }

		public PendingMessage(
			Message? message,
			GLib.Cancellable? cancellable,
			bool is_chat,
			Gee.Promise<bool>? done)
		{
			Object(
				message: message,
				cancellable: cancellable,
				is_chat: is_chat,
				done: done != null ? done : new Gee.Promise<bool>()
			);
		}

		/**
		 * Relay entry: chat deliver when is_chat, else run_summarize.
		 * Sets ''is_running'' / ''summarizing'' on the agent for the active phase.
		 *
		 * @param agent the Chatter agent supplying session and chat call
		 */
		public async void run(Agent agent) throws GLib.Error
		{
			// Summarize row: no message/cancellable; relay to run_summarize.
			if (!this.is_chat) {
				agent.summarizing = true;
				try {
					yield this.run_summarize(agent);
				} finally {
					agent.summarizing = false;
				}
				return;
			}

			agent.session.is_running = true;
			agent.session.manager.agent_status_change();
			agent.session.messages.add(this.message);

			var since_summary = agent.create_summary();
			Message? active_summary = null;
			if (since_summary.size > 0
				&& since_summary.get(0).role == "summary") {
				active_summary = since_summary.get(0);
				since_summary.remove_at(0);
			}

			var factory = (Factory) agent.session.manager.agent_factories.get(
				agent.session.agent_name);
			var outbound = new Gee.ArrayList<Message>();
			var tpl = factory.load_prompt(
				active_summary != null ? "chatter_followup.md" : "chatter_initial.md");
			outbound.add(new Message("system", tpl.system_fill(
				"conversation_summary",
				active_summary != null ? active_summary.content : "",
				"environment", factory.build_environment(agent.session))));

			foreach (var msg in since_summary) {
				outbound.add(msg);
			}

			try {
				yield agent.fill_model();
				yield agent.chat().send(outbound, this.cancellable);
			} finally {
				agent.session.is_running = false;
				agent.session.manager.agent_status_change();
			}
		}

		/**
		 * Summarize the completed chat turn (own cancellable — not main-turn token).
		 *
		 * @param agent the Chatter agent for this session
		 */
		public async void run_summarize(Agent agent) throws GLib.Error
		{
			// Own cancellable — Stop on main chat must not abort background summary.
			yield (new OLLMchat.Agent.Summarizer(agent)).run(
				new GLib.Cancellable());
			// Turn complete — chat + summarize share this done promise.
			this.done.set_value(true);
		}
	}
}
