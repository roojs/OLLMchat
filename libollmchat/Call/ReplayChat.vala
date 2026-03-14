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

		public ReplayChat(Settings.Connection connection, string model, Gee.ArrayList<Message> replay_messages)
		{
			base(connection, model);
			this.replay_messages = replay_messages;
			this.replay_index = 0;
			this.stream = false;
		}

		public override async Response.Chat send(Gee.ArrayList<Message> messages, GLib.Cancellable? cancellable = null) throws Error
		{
			if (messages.size == 0) {
				throw new OllmError.INVALID_ARGUMENT("Chat messages array is empty. Provide messages to send.");
			}
			while (this.replay_index < this.replay_messages.size) {
				var msg = this.replay_messages.get(this.replay_index);
				this.replay_index++;
				if ((msg.role != "content-stream" && msg.role != "content-non-stream" && msg.role != "assistant") || msg.content == "") {
					continue;
				}
				this.messages = messages;
				this.streaming_response.message = new Message("assistant", msg.content);
				this.streaming_response.done = true;
				return (Response.Chat) this.streaming_response;
			}
			throw new OllmError.FAILED("Replay: no more content messages.");
		}
	}
}
