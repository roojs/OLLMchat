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
	 * Agent Pi session agent.
	 *
	 * FIFO chat queue. Context hygiene (Phase 5): outbound uses messages since
	 * the latest summary boundary; compaction runs on token-threshold via
	 * {@link PendingMessage}, not paired every turn.
	 */
	public class Agent : OLLMchat.Agent.Base
	{
		internal Gee.ArrayList<PendingMessage> pending_messages {
			get; private set;
			default = new Gee.ArrayList<PendingMessage>();
		}

		internal bool pending_processing { get; set; default = false; }

		/**
		 * @param factory Agent Pi factory
		 * @param session session for manager/tools
		 */
		public Agent(Factory factory, OLLMchat.History.SessionBase session)
		{
			base(factory, session);
		}

		/**
		 * Enqueues a chat deliver; drains when idle.
		 *
		 * @param message API user message
		 * @param cancellable optional cancel for the main/tool request
		 */
		public override async void send_async(
			OLLMchat.Message message,
			GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			var af = (Factory) this.factory;
			if (af.project_manager.active_project == null) {
				throw new OLLMchat.OllmError.INVALID_ARGUMENT(
					"No project selected. Please select a project from the dropdown before sending.");
			}
			if (this.session.project_path == "") {
				this.session.project_path = af.project_manager.active_project.path;
			}

			var entry = new PendingMessage(
				message, cancellable, new Gee.Promise<bool>());
			this.pending_messages.add(entry);
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
				}
			}
			this.pending_processing = false;
			yield entry.done.future.wait_async();
		}
	}
}
