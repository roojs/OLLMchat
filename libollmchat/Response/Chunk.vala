/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, see <http://www.gnu.org/licenses/>.
 */

namespace OLLMchat.Response
{
	/**
	 * One NDJSON line or v1 SSE payload deserialized from the wire.
	 *
	 * Holds chat completion deltas (Ollama and OpenAI-style), create/pull
	 * progress fields, or both; unset fields remain at type defaults.
	 * Chat accumulation uses {@link Response.Chat.addChunk}.
	 *
	 * @see Response.Chat.addChunk
	 */
	public class Chunk : Object, Json.Serializable
	{
		/**
		 * Model name from the chunk JSON (Ollama chat, v1 completions).
		 * Empty when the line omits model (e.g. some pull progress lines).
		 */
		public string model { get; set; default = ""; }

		/**
		 * Assistant message for this line: Ollama top-level message object,
		 * or first v1 choice delta merged by custom deserialize.
		 */
		public Message message { get; set; default = new Message("assistant", ""); }

		/**
		 * True when the server marks the stream or operation finished
		 * (Ollama done, v1 finish_reason present, create/pull complete).
		 */
		public bool done { get; set; default = false; }

		/**
		 * Human-readable progress from create or pull streams
		 * (e.g. pulling manifest, pulling layer digest).
		 * Empty for chat-only lines.
		 */
		public string status { get; set; default = ""; }

		/**
		 * Layer digest string from pull progress lines. Empty when not a
		 * pull chunk or when the line has no digest.
		 */
		public string digest { get; set; default = ""; }

		/**
		 * Bytes transferred so far for the current pull layer.
		 * Zero when the line does not report layer progress.
		 */
		public int64 completed { get; set; default = 0; }

		/**
		 * Total bytes expected for the current pull layer.
		 * Zero when unknown or not a pull progress line.
		 */
		public int64 total { get; set; default = 0; }

		/**
		 * Finish reason from v1 choices or Ollama when present.
		 * Empty while the assistant message is still streaming.
		 */
		public string done_reason { get; set; default = ""; }

		/**
		 * Prompt-side token count: Ollama prompt_eval_count or v1
		 * usage.prompt_tokens when a usage object is deserialized.
		 */
		public int prompt_eval_count { get; set; default = 0; }

		/**
		 * Completion-side token count: Ollama eval_count or v1
		 * usage.completion_tokens from the same usage handling.
		 */
		public int eval_count { get; set; default = 0; }

		/**
		 * v1 streaming: per-choice delta messages built from the choices
		 * array. For chat mapping, the first choice populates
		 * {@link message} when non-empty.
		 */
		public Gee.ArrayList<Message> choices { get; set; default = new Gee.ArrayList<Message>(); }

		/**
		 * Ollama chat: total request time in nanoseconds from the chunk.
		 * Zero for APIs that do not send this field.
		 */
		public int64 total_duration { get; set; default = 0; }

		/**
		 * Ollama chat: model load time in nanoseconds when present.
		 */
		public int64 load_duration { get; set; default = 0; }

		/**
		 * Ollama chat: prompt evaluation duration in nanoseconds when
		 * present.
		 */
		public int64 prompt_eval_duration { get; set; default = 0; }

		/**
		 * Ollama chat: generation duration in nanoseconds when present.
		 */
		public int64 eval_duration { get; set; default = 0; }

		/**
		 * Ollama created_at string, or v1 created unix time as a string
		 * after custom deserialize maps the created field.
		 */
		public string created_at { get; set; default = ""; }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "choices":
				case "usage":
					return null;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
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
				case "choices": {
					var array = property_node.get_array();
					for (var i = 0; i < array.get_length(); i++) {
						var choice_obj = array.get_object_element(i);
						if (choice_obj.has_member("finish_reason")) {
							this.done_reason = choice_obj.get_string_member("finish_reason");
							this.done = this.done_reason != "";
						}
						if (!choice_obj.has_member("delta")) {
							continue;
						}
						var delta_node = choice_obj.get_member("delta");
						var msg = Json.gobject_deserialize(typeof(Message), delta_node) as Message;
						if (msg != null) {
							this.choices.add(msg);
						}
					}
					if (this.choices.size > 0) {
						this.message = this.choices.get(0);
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.choices);
					return true;
				}
				case "created": {
					this.created_at = property_node.get_int().to_string();
					value = Value(typeof(string));
					value.set_string(this.created_at);
					return true;
				}
				default:
					return default_deserialize_property(
						property_name, out value, pspec, property_node);
			}
		}
	}
}
