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
	 * Manages available models cache with ListStore backing.
	 * 
	 * NOTE: This class is technically Ollama-specific, but is kept generic
	 * for potential future use with other model providers.
	 * 
	 * Manages downloading and caching the list of available models from
	 * a remote endpoint, with automatic cache refresh when the cache is
	 * missing or older than 3 days.
	 * Implements ListModel interface using GLib.ListStore as backing store.
	 */
	public class AvailableModels : Object, GLib.ListModel
	{
		/**
		 * Backing store: ListStore containing AvailableModel objects.
		 */
		private GLib.ListStore<AvailableModel> store { get; set; }
		
		/**
		 * ListModel interface implementation: Get the item type.
		 */
		public Type get_item_type()
		{
			return typeof(AvailableModel);
		}
		
		/**
		 * ListModel interface implementation: Get the number of items.
		 */
		public uint get_n_items()
		{
			return this.store.get_n_items();
		}
		
		/**
		 * ListModel interface implementation: Get item at position.
		 */
		public Object? get_item(uint position)
		{
			return this.store.get_item(position);
		}
		
		/**
		 * Append an item to the list (ListStore-compatible).
		 * 
		 * @param item The AvailableModel item to append
		 */
		public void append(AvailableModel item)
		{
			this.store.append(item);
		}
		
		/**
		 * Remove all items from the list (ListStore-compatible).
		 */
		public void remove_all()
		{
			this.store.remove_all();
		}
		
		/**
		 * URL to fetch models from
		 */
		private const string MODELS_URL = "https://ollama-models.zwz.workers.dev/models";
		
		/**
		 * Cache file name
		 */
		private const string CACHE_FILENAME = "models.cache.json";
		
		/**
		 * Cache age threshold in days
		 */
		private const int CACHE_AGE_DAYS = 3;
		
		/**
		 * Data directory path (set via constructor)
		 */
		public string data_dir { get; construct; }
		
		/**
		 * Cache file path (initialized in construct block)
		 */
		public string cache_path { get; private set; }
		
		/**
		 * Soup session for HTTP requests
		 */
		private Soup.Session? session = null;
		
		/**
		 * Constructor.
		 * 
		 * @param data_dir Directory where cache file will be stored
		 */
		public AvailableModels(string data_dir)
		{
			Object(data_dir: data_dir);
		}
		
		construct
		{
			// Create the ListStore
			this.store = new GLib.ListStore<AvailableModel>();
			
			// Initialize cache path
			this.cache_path = GLib.Path.build_filename(this.data_dir, CACHE_FILENAME);
			
			// Create data directory if it doesn't exist
			var dir = GLib.File.new_for_path(this.data_dir);
			if (!dir.query_exists()) {
				try {
					dir.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning("Failed to create data directory: %s", e.message);
				}
			}
		}
		
		/**
		 * Checks if cache file exists and is fresh (less than CACHE_AGE_DAYS old)
		 */
		private bool is_cache_fresh()
		{
			var cache_file = GLib.File.new_for_path(this.cache_path);
			
			if (!cache_file.query_exists()) {
				return false;
			}
			
			try {
				var modified_time = cache_file.query_info(
					"time::modified",
					GLib.FileQueryInfoFlags.NONE,
					null
				).get_modification_date_time();
				
				var age = new GLib.DateTime.now_utc().difference(modified_time);
				
				// Check if cache is older than threshold
				return (age / GLib.TimeSpan.DAY) < CACHE_AGE_DAYS;
			} catch (GLib.Error e) {
				GLib.debug("Failed to check cache age: %s", e.message);
				return false;
			}
		}
		
		/**
		 * Fetches models from remote URL and saves to cache.
		 * 
		 * @throws Error if fetch or save fails
		 */
		public async void refresh() throws Error
		{
			// Create session if needed
			if (this.session == null) {
				this.session = new Soup.Session();
			}
			
			// Create message
			var message = new Soup.Message("GET", MODELS_URL);
			
			// Send request
			GLib.debug("Fetching models from: %s", MODELS_URL);
			var bytes = yield this.session.send_and_read_async(
				message,
				GLib.Priority.DEFAULT,
				null
			);
			
			if (message.status_code != 200) {
				throw new GLib.IOError.FAILED(
					"HTTP error: " + message.status_code.to_string()
				);
			}
			
			// Parse JSON to verify it's valid
			var parser = new Json.Parser();
			parser.load_from_data((string)bytes.get_data(), -1);
			
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
				throw new GLib.IOError.FAILED("Invalid JSON response: expected array");
			}
			
			// Write incoming content directly to cache file
			GLib.FileUtils.set_contents(this.cache_path, (string)bytes.get_data());
			
			GLib.debug("Models cache saved to: %s", this.cache_path);
			
			// Load models into store
			this.load_models_from_json(root);
		}
		
		/**
		 * Loads models from cache file, or refreshes if cache is missing/stale.
		 * 
		 * @throws Error if load or refresh fails
		 */
		public async void load() throws Error
		{
			// Check if cache is fresh
			if (!this.is_cache_fresh()) {
				// Cache missing or stale, refresh
				yield this.refresh();
				return;
			}
			
			// Load from cache
			try {
				var parser = new Json.Parser();
				parser.load_from_file(this.cache_path);
				var root = parser.get_root();
				
				if (root != null && root.get_node_type() == Json.NodeType.ARRAY) {
					this.load_models_from_json(root);
					GLib.debug("Loaded models from cache: %s", this.cache_path);
					return;
				}
			} catch (GLib.Error e) {
				GLib.debug("Failed to load cache, will refresh: %s", e.message);
			}
			
			// Cache missing or stale, refresh
			yield this.refresh();
		}
		
		/**
		 * Loads models from a JSON array node into the store.
		 */
		private void load_models_from_json(Json.Node root)
		{
			// Clear existing models
			this.remove_all();
			
			var array = root.get_array();
			for (int i = 0; i < array.get_length(); i++) {
				// Deserialize AvailableModel directly from JSON node
				var model = Json.gobject_deserialize(
					typeof(AvailableModel),
					array.get_element(i)
				) as AvailableModel;
				
				if (model != null) {
					this.append(model);
				}
			}
			
			GLib.debug("Loaded %u models into store", this.get_n_items());
		}
	}
}

