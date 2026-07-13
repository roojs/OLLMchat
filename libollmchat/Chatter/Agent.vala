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
	 * Builds summarized outbound history via summary-reset scan. User messages
	 * are FIFO-queued on {@link pending_messages}; {@link PendingMessage.run}
	 * delivers main chat, all tool rounds, then background summarization before
	 * the next message starts.
	 */
	public class Agent : OLLMchat.Agent.Base
	{
		internal Gee.ArrayList<PendingMessage> pending_messages {
			get; private set;
			default = new Gee.ArrayList<PendingMessage>();
		}

		internal bool pending_processing { get; set; default = false; }

		public Agent(Factory factory, History.SessionBase session)
		{
			base(factory, session);
		}

		/**
		 * Enqueues the user message and waits until main chat, all tool rounds,
		 * and background summarization for this message complete.
		 *
		 * @param message API user message (`user-sent` / `ui` already from Session)
		 * @param cancellable optional cancel token for the main/tool request
		 */
		public override async void send_async(
			Message message,
			GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			var entry = new PendingMessage(message, cancellable);
			this.pending_messages.add(entry);
			if (!this.pending_processing) {
				this.pending_processing = true;
				var head = this.pending_messages.remove_at(0);
				head.run.begin(this);
			}
			if (this.pending_messages.size > 0) {
				this.session.manager.message_added(
					new Message("ui-waiting",
						"queued — waiting for previous turn"),
					this.session);
			}
			yield entry.done.future.wait_async();
		}
	}
}
