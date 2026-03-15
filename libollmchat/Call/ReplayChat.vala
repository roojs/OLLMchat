/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMchat.Call
{
	/**
	 * Chat implementation that returns replayed content instead of calling the LLM.
	 * Takes the raw message list; each send() returns the next relevant message's content,
	 * skipping roles that are not LLM content (e.g. ui, system, project).
	 * Used by tests to drive the real Runner/List flow with session messages.
	 */
	public class ReplayChat : Chat
	{
		private Gee.ArrayList<Message> replay_messages;
		private int replay_index;

		public ReplayChat(
				Settings.Connection connection, 
				string model, 
				Gee.ArrayList<Message> replay_messages)
		{
			base(connection, model);
			this.replay_messages = replay_messages;
			this.replay_index = 0;
			this.stream = false;
		}

		public override async Response.Chat send(Gee.ArrayList<Message> messages, GLib.Cancellable? cancellable = null)
		{
			if (messages.size == 0) {
				GLib.printerr("Chat messages array is empty. Provide messages to send.\n");
				Process.exit(1);
			}
			while (this.replay_index < this.replay_messages.size) {
				var msg = this.replay_messages.get(this.replay_index);
				var idx = this.replay_index;
				this.replay_index++;
				if (msg.role != "content-stream" && msg.role != "content-non-stream"
					&& msg.role != "assistant") {
					continue;
				}
				if (msg.content == "") {
					continue;
				}
				GLib.debug("Replay index %d role=%s content.length=%d",
					idx, msg.role, msg.content.length);
				this.messages = messages;
				var response = new Response.Chat(this.connection, this);
				response.message = new Message("assistant", msg.content);
				response.done = true;
				return response;
			}
			GLib.debug("No more content messages replay_index=%d total=%d",
				this.replay_index, (int) this.replay_messages.size);
			GLib.printerr("Replay: no more content messages.\n");
			Process.exit(1);
		}
	}
}
