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

namespace OLLMtools.Tool
{
	/**
	 * Tool-specific configuration for Google search tool.
	 *
	 * This configuration class extends BaseToolConfig and adds API credentials
	 * for Google Custom Search API: api_key and engine_id (CSID).
	 *
	 * All properties must be GObject properties with proper metadata for
	 * Phase 2 UI generation via property introspection.
	 *
	 * @since 1.0
	 */
	public class GoogleSearchToolConfig : OLLMchat.Settings.BaseToolConfig
	{
		/**
		 * Google Custom Search API key.
		 */
		[Description(nick = "API Key", blurb = "Google Custom Search API key")]
		public string api_key { get; set; default = ""; }
		
		/**
		 * Google Custom Search Engine ID (CSID).
		 */
		[Description(nick = "Engine ID", blurb = "Google Custom Search Engine ID (CSID)")]
		public string engine_id { get; set; default = ""; }

		/**
		 * Default constructor.
		 */
		public GoogleSearchToolConfig()
		{
		}
	}
}

