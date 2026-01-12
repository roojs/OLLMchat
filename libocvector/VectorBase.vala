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

namespace OLLMvector
{
	/**
	 * Base class for vector operations that need tool config access.
	 * 
	 * Provides shared functionality for getting and validating connections
	 * from codebase search tool configuration.
	 */
	public abstract class VectorBase : Object
	{
		/**
		 * Configuration for accessing tool config and connections.
		 */
		protected OLLMchat.Settings.Config2 config;
		
		/**
		 * Constructor.
		 * 
		 * @param config The Config2 instance containing tool configuration
		 */
		protected VectorBase(OLLMchat.Settings.Config2 config)
		{
			this.config = config;
		}
		
		/**
		 * Gets a connection from validated tool config.
		 * 
		 * Gets tool config from this.config, optionally validates the specified ModelUsage,
		 * and returns the connection.
		 * 
		 * @param usage_type The usage type: "embed" or "analysis"
		 * @param verify If true, verify the model is available before returning connection (default: false)
		 * @return The Connection for the specified usage type
		 * @throws GLib.Error if tool config is not properly configured
		 */
		public async OLLMchat.Settings.Connection connection(string usage_type, bool verify = false) throws GLib.Error
		{
			// Get tool config from this.config
			if (!this.config.tools.has_key("codebase_search")) {
				throw new GLib.IOError.FAILED("Codebase search tool config not found");
			}
			
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			if (!tool_config.enabled) {
				throw new GLib.IOError.FAILED("Codebase search tool is disabled");
			}
			
			// Get the appropriate ModelUsage
			OLLMchat.Settings.ModelUsage usage;
			switch (usage_type) {
				case "embed":
					usage = tool_config.embed;
					break;
				case "analysis":
					usage = tool_config.analysis;
					break;
				default:
					throw new GLib.IOError.INVALID_ARGUMENT("Invalid usage_type: %s (must be 'embed' or 'analysis')".printf(usage_type));
			}
			
			// Validate ModelUsage only if verify is true
			if (verify) {
				if (!(yield usage.verify_model(this.config))) {
					throw new GLib.IOError.FAILED("Codebase search tool %s model verification failed".printf(usage_type));
				}
			}
			
			// Get connection
			var connection = this.config.connections.get(usage.connection);
			if (connection == null) {
				throw new GLib.IOError.FAILED("%s connection not found in config".printf(usage_type));
			}
			
			return connection;
		}
	}
}

