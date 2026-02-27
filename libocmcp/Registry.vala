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
	 * Registry for MCP tools.
	 *
	 * Loads the MCP config file (array of Config), and in fill_tools() will
	 * create a client per enabled Config (via transport factories) and register
	 * ToolWrappers. Phase 2.11.1: init_config/setup_config_defaults/fill_tools
	 * are present; fill_tools is a stub (no factories yet).
	 */
	public class Registry : Object
	{
		public void init_config()
		{
			// No MCP tool config types in Config2 yet
			GLib.debug("OLLMmcp.Registry.init_config: (no tool config types to register)");
		}

		public void setup_config_defaults(OLLMchat.Settings.Config2 config)
		{
			// No defaults to inject for MCP in main config yet
			GLib.debug("OLLMmcp.Registry.setup_config_defaults: (no MCP section in config)");
		}

		/**
		 * Load MCP config and register tools for each enabled server.
		 * Stub for 2.11.1: no client factories yet, so does nothing (or only loads config).
		 * Later: load file → array of Config → for each enabled Config create Client via factory → register tools.
		 */
		public void fill_tools(
			OLLMchat.History.Manager manager,
			OLLMfiles.ProjectManager? project_manager = null
		)
		{
			var configs = OLLMmcp.Config.load();
			if (configs.size == 0) {
				GLib.debug("OLLMmcp.Registry.fill_tools: no MCP servers in config");
				return;
			}
			// Stub: no factories yet, so we do not create clients or register tools
			GLib.debug("OLLMmcp.Registry.fill_tools: loaded %u server(s), no transport factories yet (stub)", configs.size);
		}
	}
}
