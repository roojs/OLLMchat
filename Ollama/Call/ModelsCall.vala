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

namespace OLLMchat.Ollama
{
	/**
	 * API call to list available models on the Ollama server.
	 * 
	 * Retrieves a list of all models that are available for use.
	 */
	public class ModelsCall : BaseCall
	{
		public ModelsCall(Client client)
		{
			base(client);
			this.url_endpoint = "tags";
			this.http_method = "GET";
		}

		public async Gee.ArrayList<Model> exec_models() throws Error
		{
			return yield this.get_models("models");
		}
	}
}
