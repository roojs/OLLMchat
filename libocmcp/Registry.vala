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
	 * Loads mcp.json, creates clients per enabled {@link Config}, and registers
	 * tools via {@link Loader}.
	 */
	public class Registry : Object
	{
		public Loader loader { get; private set; }

		public Registry()
		{
			this.loader = new Loader(this);
		}

		public void init_config()
		{
			// No MCP tool config types in Config2 yet
		}

		public void setup_config_defaults(OLLMchat.Settings.Config2 config)
		{
			// No defaults to inject for MCP in main config yet
		}

		/**
		 * Create a transport client for one MCP server entry.
		 *
		 * @param config one element from mcp.json
		 */
		public Client.Base create_client(
			Config config,
			OLLMfiles.ProjectManager project_manager
		) throws GLib.Error
		{
			switch (config.transport) {
				case "stdio":
					return new Client.Stdio(config, project_manager);
				case "http":
					return new Client.Http(config, project_manager);
				default:
					throw new GLib.IOError.NOT_SUPPORTED(
						"Unknown MCP transport '" + config.transport + "'"
					);
			}
		}

		/**
		 * Load MCP config, connect servers, register MCP tools on manager.
		 */
		public void fill_tools(
			OLLMchat.History.Manager manager,
			OLLMfiles.ProjectManager project_manager
		)
		{
			var configs = OLLMmcp.Config.load();
			if (configs.size == 0) {
				GLib.debug("No MCP servers in config");
				return;
			}
			this.loader.disconnect_all();
			var loop = new GLib.MainLoop();
			this.loader.run.begin(
				manager,
				configs,
				project_manager,
				(obj, res) => {
					try {
						this.loader.run.end(res);
					} catch (GLib.Error e) {
						GLib.warning("MCP loader failed: %s", e.message);
					}
					loop.quit();
				}
			);
			loop.run();
		}
	}
}
