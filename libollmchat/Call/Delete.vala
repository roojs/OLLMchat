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

namespace OLLMchat.Call
{
	/**
	 * API call to delete a model from the Ollama server.
	 *
	 * Deletes a model by name using the Ollama delete API endpoint.
	 * This permanently removes the model from the server.
	 */
	public class Delete : Base
	{
		public string name { get; set; default = ""; }

		public Delete(Settings.Connection connection, string model_name)
		{
			base(connection);
			if (model_name == "") {
				throw new OllmError.INVALID_ARGUMENT("Model name cannot be empty");
			}
			this.name = model_name;
			this.url_endpoint = "delete";
			this.http_method = "DELETE";
		}

		/**
		 * Executes the delete API call.
		 *
		 * @throws Error if the request fails or response is invalid
		 */
		public async void exec_delete() throws Error
		{
			yield this.send_request(true);
		}
	}
}
