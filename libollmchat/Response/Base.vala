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

namespace OLLMchat.Response
{
	/**
	 * Abstract base class for Ollama API responses.
	 *
	 * Provides common functionality for deserializing responses from the Ollama API.
	 * All response types extend this class. Responses are automatically deserialized
	 * from JSON when received from the API.
	 */
	public abstract class Base : OllamaBase
	{
		protected string id = "";
		public Message? message { get; set; default = null; }

		protected Base(Settings.Connection? connection = null)
		{
			base(connection);
		}
	}
}

