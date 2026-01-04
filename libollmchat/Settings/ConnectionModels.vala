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

namespace OLLMchat.Settings
{
	/**
	 * Manages the list of available models from all configured connections.
	 * 
	 * Provides a ListModel interface for use in dropdowns and configuration dialogs.
	 * Loads models directly from configured connections (unlike AvailableModels which
	 * loads from cache/JSON file). Implements progressive refresh logic that only
	 * processes working connections and adds/removes models incrementally.
	 * 
	 * @since 1.0
	 */
	public class ConnectionModels : Object, GLib.ListModel
	{
		/**
		 * Config2 instance (set via constructor).
		 */
		public Config2 config { get; construct; }
		
		/**
		 * Backing store: ArrayList containing ModelUsage objects.
		 * Direct access to items (no need for Traversable/Iterable).
		 */
		public Gee.ArrayList<ModelUsage> items { get; private set;
			default = new Gee.ArrayList<ModelUsage>((a, b) => {
				return a.connection == b.connection && a.model == b.model;
			});
		}
		
		/**
		 * Storage: HashMap of connection URL to HashMap of model name to ModelUsage.
		 * Used for efficient O(1) lookup by both connection and model name.
		 */
		public Gee.HashMap<string, Gee.HashMap<string, ModelUsage>> connection_map { get; private set;
			default = new Gee.HashMap<string, Gee.HashMap<string, ModelUsage>>(); }
		
		/**
		 * Constructor.
		 * 
		 * @param config The Config2 instance containing connection configurations
		 */
		public ConnectionModels(Config2 config)
		{
			Object(config: config);
		}
		
		/**
		 * Refresh models from all working connections (progressive update - adds/removes missing models).
		 * Only processes connections where is_working = true.
		 * 
		 * When refreshing:
		 * - Only processes connections where connection.is_working = true
		 * - Skips connections that are not working (don't attempt to fetch models from them)
		 * - Compares fetched models with existing models in the store
		 * - Adds new models that don't exist
		 * - Removes models from connections that are no longer working or available
		 * - Don't clear and reload everything
		 */
		public async void refresh()
		{
			// Get existing connections and copy them
			var connections_to_remove = new Gee.ArrayList<string>();
			connections_to_remove.add_all(this.connection_map.keys);
			
			// Process each working connection
			foreach (var connection_url in this.config.connections.keys) {
				var connection = this.config.connections.get(connection_url);
				
				// Remove from connections_to_remove as we process (connection still exists)
				
				// Remove models from non-working connections
				if (!connection.is_working) {
					continue;
				}
				
				
				try {
					yield this.refresh_connection(connection);
					connections_to_remove.remove(connection_url);
				} catch (GLib.Error e) {
					GLib.warning("Failed to fetch models from connection %s: %s", connection.name, e.message);
				}
			}
			
			// Remove models from connections that are still in connections_to_remove
			foreach (var connection_url in connections_to_remove) {
				this.remove_connection(connection_url);
			}
		}
		
		/**
		 * Refreshes models for a single connection.
		 * 
		 * @param connection The connection to refresh models for
		 * @return true if models were successfully refreshed, false otherwise
		 */
		private async bool refresh_connection(Connection connection) throws GLib.Error
		{
			var client = new OLLMchat.Client(connection) {
				config = this.config
			};
			var models_list = yield client.models();
			
			// Get existing models for this connection and copy them
			var models_to_remove = new Gee.ArrayList<ModelUsage>();
			if (this.connection_map.has_key(connection.url)) {
				models_to_remove.add_all(this.connection_map.get(connection.url).values);
			}
			
			// Process each model from this connection
			foreach (var model in models_list) {
				// Find and remove from models_to_remove if it exists (model still exists)
				var existing_model_usage = this.find_model(connection.url, model.name);
				if (existing_model_usage != null) {
					models_to_remove.remove(existing_model_usage);
					continue;
				}
				
				// New model - create ModelUsage and add to store
				this.append(new ModelUsage() {
					connection = connection.url,
					model = model.name,
					model_obj = model
				});
			}
			
			// Remove models that are still in models_to_remove (they no longer exist)
			foreach (var model_usage in models_to_remove) {
				this.remove(model_usage);
			}
			
			return true;
		}
		
		/**
		 * Removes all models for a given connection URL.
		 * 
		 * @param connection_url The connection URL to remove models for
		 */
		public void remove_connection(string connection_url)
		{
			var connection_models = this.connection_map.get(connection_url);
			if (connection_models == null) {
				return;
			}
			
			var items_to_remove = new Gee.ArrayList<ModelUsage>();
			foreach (var model_usage in connection_models.values) {
				items_to_remove.add(model_usage);
			}
			foreach (var model_usage in items_to_remove) {
				this.remove(model_usage);
			}
		}
		
		/**
		 * Finds a ModelUsage by connection URL and model name.
		 * 
		 * @param connection_url The connection URL
		 * @param model_name The model name
		 * @return The ModelUsage if found, null otherwise
		 */
		public ModelUsage? find_model(string connection_url, string model_name)
		{
			var connection_models = this.connection_map.get(connection_url);
			if (connection_models == null) {
				return null;
			}
			return connection_models.get(model_name);
		}
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(ModelUsage);
		}
		
		/**
		 * ListModel interface implementation: Get the number of items.
		 */
		public uint get_n_items()
		{
			return this.items.size;
		}
		
		/**
		 * ListModel interface implementation: Get item at position.
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.items.size) {
				return null;
			}
			return this.items[(int)position];
		}
		
		/**
		 * Append an item to the list (ListStore-compatible).
		 * 
		 * @param item The ModelUsage item to append
		 */
		public void append(ModelUsage item)
		{
			var position = this.items.size;
			this.items.add(item);
			
			// Add to connection_map
			if (!this.connection_map.has_key(item.connection)) {
				this.connection_map.set(item.connection, new Gee.HashMap<string, ModelUsage>());
			}
			this.connection_map.get(item.connection).set(item.model, item);
			
			// Emit items_changed signal
			this.items_changed(position, 0, 1);
		}
		
		/**
		 * Remove an item from the list by item reference.
		 * 
		 * @param item The ModelUsage item to remove
		 */
		public void remove(ModelUsage item)
		{
			var position = this.items.index_of(item);
			if (position < 0) {
				return; // Not found
			}
			
			this.items.remove_at(position);
			
			// Remove from connection_map
			var connection_models = this.connection_map.get(item.connection);
			connection_models.unset(item.model);
			if (connection_models.size == 0) {
				this.connection_map.unset(item.connection);
			}
			
			// Emit items_changed signal
			this.items_changed((uint)position, 1, 0);
		}
		
		/**
		 * Remove an item at a specific position (ListStore-compatible).
		 * 
		 * @param position The position of the item to remove
		 */
		private void remove_at(uint position)
		{
			if (position >= this.items.size) {
				return; // Invalid position
			}
			
			this.remove(this.items.get((int)position));
		}
		
		/**
		 * Remove all items from the list.
		 */
		public void remove_all()
		{
			var count = this.items.size;
			if (count == 0) {
				return;
			}
			
			this.items.clear();
			this.connection_map.clear();
			
			// Emit items_changed signal
			this.items_changed(0, (uint)count, 0);
		}
		
		/**
		 * Check if an item exists in the list.
		 * 
		 * @param item The ModelUsage item to check
		 * @return true if item exists, false otherwise
		 */
		public bool contains(ModelUsage item)
		{
			return this.items.contains(item);
		}
	}
}

