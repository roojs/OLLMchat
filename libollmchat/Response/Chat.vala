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

namespace OLLMchat.Response
{
	/**
	 * Response from a chat API call.
	 *
	 * Contains the assistant's message, tool calls (if any), and metadata.
	 * Handles streaming responses and tool call detection for automatic execution.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var response = yield client.chat("Hello!");
	 *
	 * // Access message content
	 * print(response.message.content);
	 *
	 * // Check for tool calls
	 * if (response.tool_calls.size > 0) {
	 *     // Tools were requested by the model
	 * }
	 *
	 * // Access performance metrics
	 * print(@"Total duration: $(response.total_duration)ns");
	 * }}}
	 */
	public class Chat : Base, ChatContentInterface
	{
		/** Dummy message when no chunk received yet; never null. */
		public Message message { get; set; }
		/** v1 non-streaming: choice messages (first mirrors {@link message}). */
		public Gee.ArrayList<Message> choices { get; set; default = new Gee.ArrayList<Message>(); }
		/** Owning chat call (Ollama or v1); always set for live responses. */
		public Call.ChatInterface call { get; set; }
		
		public new string chat_content {
			get { return this.message.content; }
			set {   }
		}
		
		public string model { get; set; default = ""; }
		public string created_at { get; set; default = ""; }
		public string thinking { get; set; default = ""; }
		public bool is_thinking { get; set; default = false; }
		public string done_reason { get; set; default = ""; }
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }
		public int64 prompt_eval_duration { get; set; default = 0; }
		public int eval_count { get; set; default = 0; }
		public int64 eval_duration { get; set; default = 0; }
		public string new_content { get; set; default = ""; }
		public string new_thinking { get; set; default = ""; }

		/** Newest streaming delta at index 0; used by {@link check_back_token}. Max 100 entries. Not serialized to JSON. */
		public Gee.ArrayList<string> back_tokens { get; set; default = new Gee.ArrayList<string>(); }

		// Computed properties (hidden from serialization/deserialization)
		public double total_duration_s {
			get { return (double)this.total_duration / 1e9; }
		}

		public double eval_duration_s {
			get { return (double)this.eval_duration / 1e9; }
		}

		public double tokens_per_second {
			get {
				if (this.eval_duration_s > 0) {
					return (double)this.eval_count / this.eval_duration_s;
				}
				return 0.0;
			}
		}

		/**
		 * Generates a summary string with performance metrics.
		 *
		 * @return Summary string in format "Total Duration: X.XXs | Tokens In: X Out: X | X.XX t/s".
		 *         Session.finalize_streaming appends " | " plus display_name_with_size(), or "Unknown model" if model name is empty.
		 *         Returns "Response completed (metrics not available)" if eval_duration is 0 (no metrics available)
		 */
		public string get_summary()
		{
			if (this.eval_duration <= 0) {
				// Return meaningful message when metrics aren't available
				// This ensures users always see feedback that the response completed
				return "Response completed (metrics not available)";
			}
			return "Total Duration: %.2fs | Tokens In: %d Out: %d | %.2f t/s".printf(
				this.total_duration_s,
				this.prompt_eval_count,
				this.eval_count,
				this.tokens_per_second
			);
		}

		construct
		{
			if (this.message == null)
				this.message = new Message("assistant", "");
		}

		public Chat(Settings.Connection? connection, Call.ChatInterface call)
		{
			base(connection);
			this.call = call;
			this.message = new Message("assistant", "");
		}

		public bool check_back_token()
		{
			if (this.back_tokens.size < 10) {
				return true;
			}

			var t0 = this.back_tokens.get(0);
			this.back_tokens.set(0, "");

			int[] matches = { 0 };

			for (int i = 0; i < 4; i++) {
				int pos = this.back_tokens.index_of(t0);

				if (pos < 0 || pos + 5 > this.back_tokens.size) {
					foreach (int m in matches) {
						this.back_tokens.set(m, t0);
					}
					return true;
				}

				matches += pos;

				if (matches.length > 2) {
					int n = matches.length;
					int dist = matches[n - 1] - matches[n - 2];
					if (dist != matches[n - 2] - matches[n - 3] || dist <= 5) {
						matches.resize(matches.length - 1);
						continue;
					}
				}
			}

			foreach (int m in matches) {
				this.back_tokens.set(m, t0);
			}

			var str = this.back_tokens.to_array();

			foreach (int match in matches) {
				if (match == 0) {
					continue;
				}
				if (string.joinv(" ", str[match:match + 5]) != string.joinv(" ", str[0:5])) {
					return true;
				}
			}

			return false;
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "total_duration_s":
				case "eval_duration_s":
				case "tokens_per_second":
				case "call":
				case "back-tokens":
					// Exclude computed properties, call (circular), streaming loop state
					return null;
				case "choices":
					if (this.choices.size == 0) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "message": {
					var m = Json.gobject_deserialize(typeof(Message), property_node) as Message;
					this.message = m == null ? new Message("assistant", "") : m;
					value = Value(typeof(string));
					value.set_string("");
					return true;
				}
				case "choices": {
					this.choices.clear();
					var array = property_node.get_array();
					for (var i = 0; i < array.get_length(); i++) {
						var choice_obj = array.get_object_element(i);
						if (choice_obj.has_member("message")) {
							var msg_node = choice_obj.get_member("message");
							var m = Json.gobject_deserialize(typeof(Message), msg_node) as Message;
							this.choices.add(m != null ? m : new Message("assistant", ""));
						}
					}
					this.message = this.choices.size > 0 ? this.choices.get(0) : new Message("assistant", "");
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.choices);
					return true;
				}
				case "usage": {
					var usage = property_node.get_object();
					if (usage.has_member("prompt_tokens")) {
						this.prompt_eval_count = (int)usage.get_int_member("prompt_tokens");
					}
					if (usage.has_member("completion_tokens")) {
						this.eval_count = (int)usage.get_int_member("completion_tokens");
					}
					value = Value(typeof(int));
					value.set_int(0);
					return true;
				}
				case "created": {
					this.created_at = property_node.get_int().to_string();
					value = Value(typeof(string));
					value.set_string(this.created_at);
					return true;
				}
				case "total_duration_s":
				case "eval_duration_s":
				case "tokens_per_second":
					// Exclude computed properties from deserialization
					value = Value(pspec.value_type);
					return true;
				
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}

		public override string addChunk(Response.Chunk chunk)
		{
			this.new_content = "";
			this.new_thinking = "";
			this.is_thinking = false;

			this.total_duration = chunk.total_duration;
			this.load_duration = chunk.load_duration;
			this.prompt_eval_duration = chunk.prompt_eval_duration;
			this.eval_duration = chunk.eval_duration;
			this.prompt_eval_count = chunk.prompt_eval_count;
			this.eval_count = chunk.eval_count;
			this.done = chunk.done;
			this.done_reason = chunk.done_reason;
			this.model = chunk.model;
			this.created_at = chunk.created_at;

			if (this.message == null) {
				this.message = chunk.message;
				this.new_content = chunk.message.content;
				this.new_thinking = chunk.message.thinking;
				this.thinking = chunk.message.thinking;
				this.is_thinking = chunk.message.thinking != "";
				foreach (Response.ToolCall tool_call in chunk.message.tool_calls) {
					this.message.tool_calls.add(tool_call);
				}
			} else {
				if (chunk.message.content != "") {
					this.new_content = chunk.message.content;
					this.message.content += this.new_content;
				}
				if (chunk.message.thinking != "") {
					this.new_thinking = chunk.message.thinking;
					this.message.thinking += this.new_thinking;
					this.thinking += this.new_thinking;
					this.is_thinking = true;
				}
				this.message.role = chunk.message.role;
				foreach (Response.ToolCall tool_call in chunk.message.tool_calls) {
					this.message.tool_calls.add(tool_call);
				}
			}

			return this.new_thinking.length > 0 ? this.new_thinking : this.new_content;
		}
		
		/**
		 * Creates a reply Chat with conversation history and executes it.
		 * Adds the previous assistant response and new user message to the messages array, then sends it.
		 *
		 * @param text The new user message text
		 * @return The Chat from executing the reply call
		 */
		public async Chat reply(string text) throws Error
		{
			if (this.call == null) {
				throw new OllmError.INVALID_ARGUMENT("Reply not available when call is null (v1 path)");
			}
			// Build messages array: previous assistant response + new user message
			var messages_to_send = new Gee.ArrayList<OLLMchat.Message>();
			
			// Add the assistant's response from the previous call
			messages_to_send.add(this.message);
			
			// Add the new user message
			messages_to_send.add(new OLLMchat.Message("user", text));
			
			// Append messages and send
			return yield this.call.send_append(messages_to_send);
		}
	}
}
