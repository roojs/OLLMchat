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
	 * Chatter agent.
	 *
	 * Builds summarized outbound history via summary-reset scan and
	 * triggers background summarization after each completed turn.
	 */
	public class Agent : OLLMchat.Agent.Base
	{
		public Agent(Factory factory, History.SessionBase session)
		{
			base(factory, session);
		}

		/**
		 * Sends the user message with Chatter history assembly, then
		 * starts background summarization for the completed turn.
		 *
		 * @param message API user message to append and send
		 * @param cancellable optional cancel token for the main request
		 */
		public override async void send_async(
			Message message,
			GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			this.session.is_running = true;
			this.session.manager.agent_status_change();

			this.session.messages.add(message);

			var since_summary = this.create_summary();
			Message? active_summary = null;
			if (since_summary.size > 0 && since_summary.get(0).role == "summary") {
				active_summary = since_summary.get(0);
				since_summary.remove_at(0);
			}

			var factory = (Factory) this.factory;
			var outbound = new Gee.ArrayList<Message>();

			if (active_summary != null) {
				var tpl = factory.load_prompt("chatter_followup.md");
				outbound.add(new Message("system", tpl.system_fill(
					"conversation_summary", active_summary.content,
					"environment", factory.build_environment(this.session)
				)));
			} else {
				var tpl = factory.load_prompt("chatter_initial.md");
				outbound.add(new Message("system", tpl.system_fill(
					"environment", factory.build_environment(this.session)
				)));
			}

			foreach (var msg in since_summary) {
				outbound.add(msg);
			}

			try {
				yield this.fill_model();
				yield this.chat_call.send(outbound, cancellable);
			} finally {
				this.session.is_running = false;
				this.session.manager.agent_status_change();
			}

			(new OLLMchat.Agent.Summarizer(this)).run.begin(cancellable);
		}
	}
}
