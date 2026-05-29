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
	 * Loads MCP servers: connect, tools/list, register {@link Tool} instances.
	 *
	 * {@link Registry} creates clients; this type only connects and registers.
	 */
	public class Loader : Object
	{
		private unowned Registry registry;
		private Gee.ArrayList<Client.Base> clients =
			new Gee.ArrayList<Client.Base>();

		public Loader(Registry registry)
		{
			this.registry = registry;
		}

		/**
		 * For each enabled config: connect, list tools, register with manager.
		 *
		 * Failures for one server are logged; other servers still load.
		 *
		 * @param manager receives registered tools
		 * @param configs MCP server entries from mcp.json
		 */
		public async void run(
			OLLMchat.History.Manager manager,
			Gee.ArrayList<Config> configs,
			OLLMfiles.ProjectManager project_manager
		)
		{
			foreach (var config in configs) {
				if (!config.enabled) {
					continue;
				}
				Client.Base client;
				try {
					client = this.registry.create_client(config, project_manager);
				} catch (GLib.Error e) {
					GLib.warning(
						"MCP server '%s': %s",
						config.id,
						e.message
					);
					continue;
				}
				try {
					yield client.connect();
				} catch (GLib.Error e) {
					GLib.warning(
						"MCP server '%s': connect failed: %s",
						config.id,
						e.message
					);
					continue;
				}
				this.clients.add(client);
				try {
					var factories = yield client.tools();
					foreach (var factory in factories) {
						manager.register_tool(
							factory.create_tool(client, config.id)
						);
					}
				} catch (GLib.Error e) {
					GLib.warning(
						"MCP server '%s': tools/list failed: %s",
						config.id,
						e.message
					);
					client.disconnect();
					this.clients.remove(client);
				}
			}
		}

		/**
		 * Disconnect all clients started by the last {@link run}.
		 */
		public void disconnect_all()
		{
			foreach (var client in this.clients) {
				client.disconnect();
			}
			this.clients.clear();
		}
	}
}
