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
	 * One choice in an OpenAI chat completion response.
	 * index, message, finish_reason.
	 */
	public class ChatCompletionChoice : Object, Json.Serializable
	{
		public int index { get; set; default = 0; }
		public Response.ChatCompletionMessage message { get; set;
			default = new Response.ChatCompletionMessage(); }
		public string finish_reason { get; set; default = ""; }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "message":
					return Json.gobject_serialize(this.message);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "message") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			this.message = Json.gobject_deserialize(
				typeof(Response.ChatCompletionMessage), property_node) as Response.ChatCompletionMessage;
			if (this.message == null) {
				this.message = new Response.ChatCompletionMessage();
			}
			value = Value(typeof(Response.ChatCompletionMessage));
			value.set_object(this.message);
			return true;
		}
	}
}
