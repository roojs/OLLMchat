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
 * along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

namespace OLLMmcp
{
	/**
	 * One MCP tool exposed to the agent as {@link OLLMchat.Tool.BaseTool}.
	 *
	 * Tool name is {{{mcp:{server_id}:{tool_name}}}}; execution delegates to
	 * the MCP {@link Client.Base} for this server.
	 */
	public class Tool : OLLMchat.Tool.BaseTool
	{
		public Client.Base client { get; construct; }
		public string server_id { get; construct; default = ""; }
		public Factory factory { get; construct; }

		private string name_bk = "";
		private string ex_call_bk = "";
		private string param_desc_bk = "";

		public Tool(Client.Base client, string server_id, Factory factory)
		{
			Object(
				client: client,
				server_id: server_id,
				factory: factory
			);
		}

		public override string name {
			get {
				this.name_bk = "mcp:%s:%s".printf(this.server_id, this.factory.name);
				return this.name_bk;
			}
		}

		public override string description {
			get {
				return this.factory.description;
			}
		}

		public override string title {
			get {
				return this.factory.name;
			}
		}

		public override string example_call {
			get {
				this.ex_call_bk = "{\"name\": \"%s\", \"arguments\": {}}".printf(this.name);
				return this.ex_call_bk;
			}
		}

		public override string parameter_description {
			get {
				if (!this.factory.inputSchema.has_member("properties")) {
					return "";
				}
				var props = this.factory.inputSchema.get_object_member("properties");

				var required = new Gee.HashSet<string>();
				if (this.factory.inputSchema.has_member("required")) {
					var req_arr = this.factory.inputSchema.get_array_member("required");
					for (var i = 0; i < req_arr.get_length(); i++) {
						required.add(req_arr.get_string_element(i));
					}
				}

				string result = "";
				props.foreach_member((obj, key, prop_node) => {
					var prop = prop_node.get_object();
					result += "@param " + key + " {"
						+ (prop.has_member("type")
							? prop.get_string_member("type")
							: "string")
						+ "} "
						+ (required.contains(key) ? "[required]" : "[optional]")
						+ " "
						+ (prop.has_member("description")
							? prop.get_string_member("description")
							: "")
						+ "\n";
				});
				this.param_desc_bk = result;
				return this.param_desc_bk;
			}
		}

		public override Type config_class()
		{
			return typeof(OLLMchat.Settings.BaseToolConfig);
		}

		public OLLMchat.Tool.BaseTool clone()
		{
			return new Tool(this.client, this.server_id, this.factory);
		}

		protected override OLLMchat.Tool.RequestBase? deserialize(Json.Node parameters_node)
		{
			return new Request(parameters_node.get_object());
		}

	}
}
