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

namespace OLLMmcp
{
	/**
	 * Configuration for a single MCP server (one service).
	 *
	 * Corresponds to one element in the mcp.json array. Used by Registry/Loader
	 * to create a client (via a transport factory) and register tools.
	 */
	public class Config : Object, Json.Serializable
	{
		/** Unique key for this server (tool name prefix, e.g. mcp:id:tool_name). */
		public string id { get; set; default = ""; }

		/** If false, skip this server (no client, no tools). */
		public bool enabled { get; set; default = true; }

		/** Transport: "stdio" or "http". */
		public string transport { get; set; default = "stdio"; }

		/** For stdio: command to run (e.g. "npx"). */
		public string command { get; set; default = ""; }

		/** For stdio: arguments (e.g. ["-y", "@modelcontextprotocol/server-chrome"]). */
		public Gee.ArrayList<string> args { get; set; default = new Gee.ArrayList<string>(); }

		/** For stdio: optional environment variables. */
		public Gee.Map<string, string> env { get; set; default = new Gee.HashMap<string, string>(); }

		/** For http: server URL (e.g. "http://127.0.0.1:3000"). */
		public string url { get; set; default = ""; }

		/** When true, allow network in bwrap sandbox (omit --unshare-net). Default false. */
		public bool network { get; set; default = false; }

		public Config()
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
				case "args":
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
				case "env":
					var obj = new Json.Object();
					var map = (Gee.Map<string, string>) value.get_object();
					if (map != null) {
						foreach (var e in map.entries) {
							obj.set_string_member(e.key, e.value);
						}
					}
					var env_node = new Json.Node(Json.NodeType.OBJECT);
					env_node.set_object(obj);
					return env_node;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "args":
					this.args.clear();
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var arr = property_node.get_array();
						for (var i = 0; i < arr.get_length(); i++) {
							var elem = arr.get_element(i);
							if (elem.get_node_type() == Json.NodeType.VALUE) {
								this.args.add(elem.get_string());
							}
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.args);
					return true;
				case "env":
					this.env.clear();
					if (property_node.get_node_type() == Json.NodeType.OBJECT) {
						var obj = property_node.get_object();
						obj.foreach_member((o, key, node) => {
							if (node.get_node_type() == Json.NodeType.VALUE) {
								this.env.set(key, node.get_string());
							}
						});
					}
					value = Value(typeof(Gee.Map));
					value.set_object(this.env);
					return true;
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}

		/**
		 * Load mcp.json and return an array of Config (one per server entry).
		 * Path is fixed: ~/.config/ollmchat/mcp.json. File root must be a JSON array.
		 * Returns empty list if file missing or invalid.
		 */
		public static Gee.ArrayList<Config> load()
		{
			var list = new Gee.ArrayList<Config>();
			var path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "ollmchat", "mcp.json"
			);
			if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				GLib.debug("mcp.json does not exist: %s", path);
				return list;
			}
			try {
				string contents;
				GLib.FileUtils.get_contents(path, out contents);
				var parser = new Json.Parser();
				parser.load_from_data(contents, -1);
				var root = parser.get_root();
				if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
					GLib.warning("mcp.json root is not a JSON array");
					return list;
				}
				var arr = root.get_array();
				for (var i = 0; i < arr.get_length(); i++) {
					var elem = arr.get_element(i);
					var cfg = Json.gobject_deserialize(typeof(Config), elem) as Config;
					if (cfg != null) {
						list.add(cfg);
					}
				}
				GLib.debug("Loaded %u MCP server(s) from %s", list.size, path);
			} catch (GLib.Error e) {
				GLib.warning("Loading mcp.json: %s", e.message);
			}
			return list;
		}
	}
}
