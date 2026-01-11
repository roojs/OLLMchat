/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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
	 * API call to get detailed information about a specific model.
	 *
	 * Retrieves model details including size, digest, capabilities, and other metadata.
	 * Can optionally include verbose information.
	 */
	public class ShowModel : Base
	{
		public string model { get; set; default = ""; }
		public bool verbose { get; set; default = false; }

		public ShowModel(Settings.Connection connection, string model_name) throws OllmError
		{
			base(connection);
			if (model_name == "") {
				throw new OllmError.FAILED("Model name cannot be empty");
			}
			this.model = model_name;
			this.url_endpoint = "show";
			this.http_method = "POST";
		}

		public async Response.Model exec_show() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllmError.FAILED("Invalid JSON response");
			}

			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var model_obj = Json.gobject_from_data(typeof(Response.Model), json_str, -1) as Response.Model;
			if (model_obj == null) {
				throw new OllmError.FAILED("Failed to deserialize model");
			}
			// Set the name from the request parameter (API response may not include it)
			if (model_obj.name == "") {
				model_obj.name = this.model;
			}
			GLib.debug("show_model '%s' - parameters: '%s'", this.model, model_obj.parameters ?? "(null)");
			// Note: client no longer set on response objects
			return model_obj;
		}
	}
}

