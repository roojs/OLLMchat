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
	 * FIFO queue on {@link pending_messages}; {@link send_async} enqueues chat +
	 * summarize pairs and drains the queue inline when idle.
	 */
	public class Agent : OLLMchat.Agent.Base
	{
		public Agent(Factory factory, History.SessionBase session)
		{
			base(factory, session);
		}

		internal Gee.ArrayList<PendingMessage> pending_messages {
			get; private set;
			default = new Gee.ArrayList<PendingMessage>();
		}

		internal bool pending_processing { get; set; default = false; }

		internal bool summarizing { get; set; default = false; }

		/**
		 * Enqueues chat + paired summarize; drains queue when idle; waits until
		 * both steps for this message complete.
		 *
		 * @param message API user message (`user-sent` / `ui` already from Session)
		 * @param cancellable optional cancel token for the main/tool request
		 */
		public override async void send_async(
			Message message,
			GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			var entry = new PendingMessage(
				message, cancellable, true, new Gee.Promise<bool>());
			this.pending_messages.add(entry);
			// Paired summarize row — same done promise; enqueued before drain starts.
			this.pending_messages.add(
				new PendingMessage(null, null, false, entry.done));
			// Another send_async is already draining; wait on this turn's promise.
			if (this.pending_processing) {
				yield entry.done.future.wait_async();
				return;
			}
			this.pending_processing = true;
			while (this.pending_messages.size > 0) {
				var head = this.pending_messages.remove_at(0);
				try {
					yield head.run(this);
				} catch (GLib.Error e) {
					head.done.set_exception(e);
					// Chat failed — skip the paired summarize row already at queue head.
					if (head.is_chat && this.pending_messages.size > 0) {
						this.pending_messages.remove_at(0);
					}
				}
			}
			this.pending_processing = false;
			GLib.debug("queue drain done pending=%d before wait",
				this.pending_messages.size);
			yield entry.done.future.wait_async();
			GLib.debug("queue wait returned is_running=%s",
				this.session.is_running.to_string());
		}
	}
}
