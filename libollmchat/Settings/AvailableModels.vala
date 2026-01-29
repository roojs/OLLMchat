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

namespace OLLMchat.Settings
{
	/**
	 * Manages available models cache with ArrayList backing.
	 *
	 * NOTE: This class is technically Ollama-specific, but is kept generic
	 * for potential future use with other model providers.
	 *
	 * Manages downloading and caching the list of available models from
	 * a remote endpoint, with automatic cache refresh when the cache is
	 * missing or older than 3 days.
	 * Implements ListModel interface using Gee.ArrayList as backing store.
	 */
	public class AvailableModels : Object, GLib.ListModel
	{
		/**
		 * Backing store: ArrayList for order and ListModel.
		 */
		private Gee.ArrayList<AvailableModel> store { get; set;
			default = new Gee.ArrayList<AvailableModel>();
		}
		
		/**
		 * Name => model for duplicate check on append.
		 */
		private Gee.HashMap<string, AvailableModel> by_name { get; set;
			default = new Gee.HashMap<string, AvailableModel>();
		}
		
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
			return this.store.size;
		}
		
		/**
		 * ListModel interface implementation: Get item at position.
		 */
		public Object? get_item(uint position)
		{
			if (position >= this.store.size) {
				return null;
			}
			return this.store[(int)position];
		}
		
		/**
		 * Append an item to the list.
		 * If a model with the same name is already present, the new one is ignored.
		 *
		 * @param item The AvailableModel item to append
		 */
		public void append(AvailableModel item)
		{
			if (this.by_name.has_key(item.name)) {
				return;
			}
			this.by_name.set(item.name, item);
			var position = this.store.size;
			this.store.add(item);
			this.items_changed(position, 0, 1);
		}
		
		/**
		 * Remove all items from the list.
		 */
		public void remove_all()
		{
			var n_items = this.store.size;
			if (n_items > 0) {
				this.store.clear();
				this.by_name.clear();
				this.items_changed(0, n_items, 0);
			}
		}
		
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
			
			// Initialize cache path
			this.cache_path = GLib.Path.build_filename(this.data_dir, "models.cache.json");
		
			// Note: data_dir is expected to already exist (app.ensure_data_dir() is called earlier)
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
		 //NOTE: Currently disabled - will be enabled later when remote URL is configured
	 	 
		public async void refresh() throws Error
		{
			// Create session if needed (keep soup session code for future use)
			if (this.session == null) {
				this.session = new Soup.Session();
			}
			
			// TODO: Enable when remote URL is configured
			// Create message
			// var message = new Soup.Message("GET", MODELS_URL);
			// 
			// // Send request
			// GLib.debug("Fetching models from: %s", MODELS_URL);
			// var bytes = yield this.session.send_and_read_async(
			// 	message,
			// 	GLib.Priority.DEFAULT,
			// 	null
			// );
			// 
			// if (message.status_code != 200) {
			// 	throw new GLib.IOError.FAILED(
			// 		"HTTP error: " + message.status_code.to_string()
			// 	);
			// }
			// 
			// // Parse JSON to verify it's valid
			// var parser = new Json.Parser();
			// parser.load_from_data((string)bytes.get_data(), -1);
			// 
			// var root = parser.get_root();
			// if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
			// 	throw new GLib.IOError.FAILED("Invalid JSON response: expected array");
			// }
			// 
			// // Write incoming content directly to cache file
			// GLib.FileUtils.set_contents(this.cache_path, (string)bytes.get_data());
			// 
			// GLib.debug("Models cache saved to: %s", this.cache_path);
			// 
			// // Load models into store
			// this.load_models_from_json(root);
			
			// Currently disabled - throw error to indicate not implemented
			throw new GLib.IOError.NOT_SUPPORTED("Remote refresh not yet implemented");
		}
		
		/**
		 * Gets the path to the local ollama-models.json file in data_dir
		 */
		private string get_ollama_models_path()
		{
			return GLib.Path.build_filename(this.data_dir, "ollama-models.json");
		}
		
		/**
		 * Attempts to parse JSON from a file path.
		 *
		 * @param path File path to parse
		 * @return Json.Node if successful, null otherwise
		 */
		private Json.Node? try_parse_json_from_file(string path)
		{
			var file = GLib.File.new_for_path(path);
			if (!file.query_exists()) {
				return null;
			}
			try {
				var parser = new Json.Parser();
				parser.load_from_file(path);
				return parser.get_root();
			} catch (GLib.Error e) {
				GLib.debug("Failed to parse JSON from file %s: %s", path, e.message);
				return null;
			}
		}
		
		/**
		 * Attempts to parse JSON from a data string.
		 *
		 * @param data JSON data string to parse
		 * @return Json.Node if successful, null otherwise
		 */
		private Json.Node? try_parse_json_from_data(string data)
		{
			try {
				var parser = new Json.Parser();
				parser.load_from_data(data, -1);
				return parser.get_root();
			} catch (GLib.Error e) {
				GLib.debug("Failed to parse JSON from data: %s", e.message);
				return null;
			}
		}
		
		/**
		 * Attempts to load models from a JSON node if it's a valid array.
		 *
		 * @param root JSON root node to load from
		 * @param source_name Name of the source for logging purposes
		 * @return true if models were loaded successfully, false otherwise
		 */
		private bool try_load_from_json_node(Json.Node? root, string source_name)
		{
			if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
				return false;
			}
			
			this.load_models_from_json(root);
			GLib.debug("Loaded models from %s", source_name);
			return true;
		}
		
		/**
		 * Loads models: resource first, then from file (ollama-models.json in data_dir) if it exists.
		 * Duplicates by name are skipped on append.
		 *
		 * @throws Error if load fails
		 */
		public async void load() throws Error
		{
			this.remove_all();
			
			try {
				var resource_file = GLib.File.new_for_uri("resource:///ollmchat/ollama-models.json");
				uint8[] data;
				resource_file.load_contents(null, out data, null);
				var resource_root = this.try_parse_json_from_data((string)data);
				this.load_models_from_json(resource_root);
				GLib.debug("Loaded models from resource");
			} catch (GLib.Error e) {
				GLib.debug("Failed to load from resource: %s", e.message);
				throw new GLib.IOError.NOT_FOUND("No models data found in resources");
			}
			
			var ollama_models_path = this.get_ollama_models_path();
			var ollama_models_file = GLib.File.new_for_path(ollama_models_path);
			if (ollama_models_file.query_exists()) {
				var root = this.try_parse_json_from_file(ollama_models_path);
				if (root != null && root.get_node_type() == Json.NodeType.ARRAY) {
					this.load_models_from_json(root);
					GLib.debug("Loaded models from file: %s", ollama_models_path);
				}
			}
		}
		
		/**
		 * Loads models from a JSON array node into the store (appends; duplicates by name are skipped).
		 */
		private void load_models_from_json(Json.Node root)
		{
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
		}
	}
}

