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

namespace OLLMchat.Call
{
	/**
	 * Shared chat call surface: state, signals, and tool recursion helpers.
	 * Subclasses implement {@link send} for protocol-specific request paths.
	 */
	public abstract class ChatBase : Base
	{
		public abstract string model { get; set; }
		public abstract Call.Options options { get; set; }
		/** Ollama uses JSON `think`; ChatCompletions maps this to `reasoning_effort`. */
		public virtual bool think { get; set; default = false; }

		protected ChatBase(Settings.Connection? connection = null)
		{
			base(connection);
		}

		public Gee.ArrayList<Message> messages { get; set; default = new Gee.ArrayList<Message>(); }
		public bool stream { get; set; default = true; }
		public Gee.HashMap<string, Tool.BaseTool>? tools { get; set; default = new Gee.HashMap<string, Tool.BaseTool>(); }
		public OLLMchat.Agent.Base? agent { get; set; default = null; }

		public signal void stream_chunk(string new_text, bool is_thinking, Response.Chat response);
		public signal void stream_start();
		public signal void tool_message(Message message);
		public signal void tool_call_requested(Response.ToolCall tool_call, Gee.ArrayList<Message> return_messages);

		public void add_tool(Tool.BaseTool tool)
		{
			if (this.tools == null) {
				this.tools = new Gee.HashMap<string, Tool.BaseTool>();
			}
			this.tools.set(tool.name, tool);
		}

		public abstract async Response.Chat send(
			Gee.ArrayList<Message> messages,
			GLib.Cancellable? cancellable = null) throws Error;

		public async Response.Chat send_append(
			Gee.ArrayList<Message> new_messages,
			GLib.Cancellable? cancellable = null) throws Error
		{
			foreach (var msg in new_messages) {
				this.messages.add(msg);
			}
			return yield this.send(this.messages,
				cancellable != null ? cancellable : this.cancellable);
		}

		public async Response.Chat toolsReply(Response.Chat response) throws Error
		{
			if (!response.done || response.message.tool_calls.size == 0) {
				return response;
			}

			if (this.agent != null) {

				var history_msg = new Message(
					response.message.role, response.message.content);
				foreach (var tool_call in response.message.tool_calls) {
					history_msg.tool_calls.add(tool_call);
				}
				this.agent.add_message(history_msg);
				var tool_reply_messages = yield this.agent.execute_tools(response.message.tool_calls);
				var messages_to_send = new Gee.ArrayList<Message>();
				messages_to_send.add(response.message);
				foreach (var reply_msg in tool_reply_messages) {
					this.agent.add_message(reply_msg);
					messages_to_send.add(reply_msg);
				}
				this.agent.session.manager.message_added(
					new Message(
						"ui-waiting",
						"waiting for "
						+ (this.agent.session.model_usage.model != ""
							? this.agent.session.model_usage.display_name_with_size()
							: "Unknown model")
						+ " to reply"),
					this.agent.session);
				var next_response = yield this.send_append(messages_to_send);
				if (next_response.done &&
					next_response.message.tool_calls.size > 0) {
					return yield this.toolsReply(next_response);
				}
				return next_response;
			}

			var messages_to_send_na = new Gee.ArrayList<Message>();
			messages_to_send_na.add(response.message);
			foreach (var tool_call in response.message.tool_calls) {
				this.tool_call_requested(tool_call, messages_to_send_na);
			}
			var next_response_na = yield this.send_append(messages_to_send_na);
			if (next_response_na.done &&
				next_response_na.message.tool_calls.size > 0) {
				return yield this.toolsReply(next_response_na);
			}
			return next_response_na;
		}
	}
}
