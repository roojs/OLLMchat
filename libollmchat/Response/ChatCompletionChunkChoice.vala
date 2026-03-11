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
	 * One choice in an SSE chat completion chunk.
	 * index, delta, finish_reason.
	 */
	public class ChatCompletionChunkChoice : Object, Json.Serializable
	{
		public int index { get; set; default = 0; }
		public Response.ChatCompletionDelta delta { get; set; default = new Response.ChatCompletionDelta(); }
		public string finish_reason { get; set; default = ""; }

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			if (property_name == "delta") {
				return Json.gobject_serialize(this.delta);
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name != "delta") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			this.delta = Json.gobject_deserialize(typeof(Response.ChatCompletionDelta), property_node) as Response.ChatCompletionDelta;
			if (this.delta == null) {
				this.delta = new Response.ChatCompletionDelta();
			}
			value = Value(typeof(Response.ChatCompletionDelta));
			value.set_object(this.delta);
			return true;
		}
	}
}
