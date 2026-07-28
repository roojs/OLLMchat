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
	 * Per-agent tool availability for {@link Config2}.
	 *
	 * Stored under the ''agents'' map keyed by factory id (e.g. ''agent-pi'').
	 * ''forbidden'' is user-editable JSON. Required-tool checks live in factory
	 * ''register_config'' (hardcoded), not on this type.
	 *
	 * == Usage Examples ==
	 *
	 * === Code (register_config seed) ===
	 *
	 * {{{
	 * config.agents.set("agent-pi", new AgentConfig() {
	 *     forbid = "write_file,huggingface_hub"
	 * });
	 * }}}
	 *
	 * === JSON (config.2.json) ===
	 *
	 * {{{
	 * "agents": {
	 *   "agent-pi": { "forbidden": [ "write_file", "huggingface_hub" ] }
	 * }
	 * }}}
	 */
	public class AgentConfig : Object, Json.Serializable
	{
		/**
		 * Tool names never included for this agent (JSON array).
		 */
		[Description(nick = "Forbidden", blurb = "Tools never included for this agent")]
		public Gee.ArrayList<string> forbidden { get; set; default = new Gee.ArrayList<string>(); }

		/**
		 * Comma-separated tool names to forbid (fills {@link forbidden}).
		 *
		 * For object initializers; not written to JSON.
		 */
		public string forbid {
			set {
				this.forbidden.clear();
				var parts = value.split(",");
				foreach (var part in parts) {
					var name = part.strip();
					if (name == "") {
						continue;
					}
					this.forbidden.add(name);
				}
			}
		}

		/**
		 * Default constructor.
		 */
		public AgentConfig()
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
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "forbid":
					return null;

				case "forbidden":
					var arr = new Json.Array();
					var list = (Gee.ArrayList<string>) value.get_object();
					if (list != null) {
						foreach (var s in list) {
							arr.add_string_element(s);
						}
					}
					var node = new Json.Node(Json.NodeType.ARRAY);
					node.set_array(arr);
					return node;

				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "forbidden":
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var arr = property_node.get_array();
						for (var i = 0; i < arr.get_length(); i++) {
							var elem = arr.get_element(i);
							if (elem.get_node_type() != Json.NodeType.VALUE) {
								continue;
							}
							this.forbidden.add(elem.get_string());
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.forbidden);
					return true;

				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}
