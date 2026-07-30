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
	 * FIFO chat queue when idle. Mid-run {@link send_async} appends to
	 * {@link message_queue} as follow-up (role '''user'''); callers escalate with
	 * ''role = "urgent"''. Urgent drains in {@link execute_tools} via
	 * FilterListModel; at stop {@link PendingMessage.run} drains the whole queue.
	 */
	public class Agent : OLLMchat.Agent.Base
	{
		internal Gee.ArrayList<PendingMessage> pending_messages {
			get; private set;
			default = new Gee.ArrayList<PendingMessage>();
		}

		internal bool pending_processing { get; set; default = false; }

		/**
		 * Mid-run follow-up / urgent queue (ListModel over session.queued_messages).
		 */
		public OLLMchat.MessageQueue message_queue {
			get; private set;
		}

		/**
		 * @param factory Agent Pi factory
		 * @param session session for manager/tools
		 */
		public Agent(Factory factory, OLLMchat.History.SessionBase session)
		{
			base(factory, session);
			this.message_queue = new OLLMchat.MessageQueue(session.queued_messages);
		}

		/**
		 * Run tools, then append any queued urgent messages for the next model call.
		 *
		 * Shared ''ChatBase.toolsReply'' adds every returned message to the session
		 * and ''send_append'' payload — no core-library change required.
		 *
		 * @param tool_calls tool calls from the assistant response
		 * @return tool reply messages, then any drained urgent messages
		 */
		public override async Gee.ArrayList<OLLMchat.Message> execute_tools(
			Gee.ArrayList<OLLMchat.Response.ToolCall> tool_calls)
		{
			var reply_messages = yield base.execute_tools(tool_calls);
			var urgent = new Gtk.FilterListModel(this.message_queue, new Gtk.CustomFilter((item) => {
				return ((OLLMchat.Message) item).role == "urgent";
			}));
			while (urgent.get_n_items() > 0) {
				var msg = (OLLMchat.Message) urgent.get_item(urgent.get_n_items() - 1);
				this.message_queue.remove(msg);
				msg.role = "user";
				reply_messages.add(msg);
			}
			return reply_messages;
		}

		/**
		 * Idle: enqueue a full chat turn. Running: queue as follow-up (default).
		 *
		 * Mid-run UI may escalate by setting ''message.role = "urgent"''.
		 *
		 * @param message API user message
		 * @param cancellable optional cancel for the main/tool request (idle path)
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

			if (this.session.is_running) {
				message.role = "user";
				this.message_queue.append(message);
				return;
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
