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

namespace OLLMchat.Settings
{
	/**
	 * Outbound remote file-server connection (client side).
	 *
	 * JSON key ''filesd_client'' on {@link Config2}. At most one row in the
	 * Connections tab; empty ''url'' means not configured.
	 */
	public class FilesdClient : Object, Json.Serializable
	{
		/**
		 * Remote ''ollmfilesd'' HTTPS base URL (e.g. [[https://host:8443]]).
		 */
		public string url { get; set; default = ""; }

		/**
		 * Connection state. JSON is the ordinal.
		 *
		 * 0 requested, 1 disabled, 2 enabled, 3 live, 4 unreachable,
		 * 5 socket.
		 */
		public enum State {
			REQUESTED,
			DISABLED,
			ENABLED,
			LIVE,
			UNREACHABLE,
			SOCKET
		}

		public State state { get; set; default = State.REQUESTED; }

		public FilesdClient()
		{
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			var val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(
			string property_name, Value value, ParamSpec pspec)
		{
			if (property_name == "state") {
				var node = new Json.Node(Json.NodeType.VALUE);
				node.set_int((int) this.state);
				return node;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec,
			Json.Node property_node)
		{
			if (property_name == "state") {
				value = Value(typeof(State));
				value.set_enum((int) property_node.get_int());
				return true;
			}
			return default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
	}
}
