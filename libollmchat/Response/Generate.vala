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
	 * Represents the response from the generate API.
	 *
	 * Contains the model name, generated response text, thinking output,
	 * and timing information.
	 */
	public class Generate : Base
	{
		public string model { get; set; default = ""; }
		public string created_at { get; set; default = ""; }
		public string response { get; set; default = ""; }
		public string thinking { get; set; default = ""; }
		public bool done { get; set; default = false; }
		public string? done_reason { get; set; default = ""; }
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }
		public int64 prompt_eval_duration { get; set; default = 0; }
		public int eval_count { get; set; default = 0; }
		public int64 eval_duration { get; set; default = 0; }
		public Gee.ArrayList<string> choices { get; set; default = new Gee.ArrayList<string>(); }

		public Generate(Settings.Connection? connection = null)
		{
			base(connection);
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "client":
					return null;
				case "done-reason":
					// Only serialize if set
					if (this.done_reason == null || this.done_reason == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				case "choices":
					if (this.choices.size == 0) {
						return null;
					}
					var arr = new Json.Array();
					foreach (var s in this.choices) {
						arr.add_string_element(s);
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.init_array(arr);
					return node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "choices": {
					// v1: array of { "text", "index", "finish_reason" } — we only use text; ignore finish_reason for now
					var array = property_node.get_array();
					for (var i = 0; i < array.get_length(); i++) {
						var choice_obj = array.get_object_element(i);
						if (choice_obj.has_member("text")) {
							var t = choice_obj.get_string_member("text");
							this.choices.add(t != null ? t : "");
						}
					}
					this.response = this.choices.size > 0 ? this.choices[0] : "";
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.choices);
					return true;
				}
				case "usage": {
					// v1: reuse prompt_eval_count / eval_count (same as tokens)
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
					// v1: unix timestamp (int) → created_at string
					this.created_at = property_node.get_int().to_string();
					value = Value(typeof(string));
					value.set_string(this.created_at);
					return true;
				}
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}

