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

namespace OLLMtools.GoogleSearch
{
	/**
	 * Configuration for Google Custom Search API credentials.
	 *
	 * Loads API key and search engine ID from ~/.config/ollmchat/google.json
	 */
	public class Config : Object, Json.Serializable
	{
		/**
		 * Google Custom Search API key
		 */
		public string api_key { get; set; default = ""; }
		
		/**
		 * Google Custom Search Engine ID
		 */
		public string engine_id { get; set; default = ""; }

		/**
		 * Default constructor.
		 */
		public Config()
		{
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

        public new void Json.Serializable.set_property(ParamSpec pspec, GLib.Value value)
        {
            base.set_property(pspec.get_name(), value);
        }

        public new GLib.Value Json.Serializable.get_property(ParamSpec pspec)
        {
            GLib.Value val = GLib.Value(pspec.value_type);
            base.get_property(pspec.get_name(), ref val);
            return val;
        }

        public override Json.Node serialize_property(string property_name, GLib.Value value, ParamSpec pspec)
        {
            return default_serialize_property(property_name, value, pspec);
        }

        public override bool deserialize_property(string property_name, out GLib.Value value, ParamSpec pspec, Json.Node property_node)
        {
            return default_deserialize_property(property_name, out value, pspec, property_node);
        }

		/**
		 * Loads Config from file.
		 *
		 * Loads from ~/.config/ollmchat/google.json
		 * If the file cannot be read/parsed, returns null.
		 *
		 * @return A new Config instance loaded from the file, or null if loading failed
		 */
		public static Config? load()
		{
			var config_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".config", "ollmchat", "google.json"
			);

			try {
				string contents;
				GLib.FileUtils.get_contents(config_path, out contents);
				
				var loaded_config = Json.gobject_from_data(
					typeof(Config),
					contents,
					-1
				) as Config;
				
				if (loaded_config == null) {
					GLib.warning("Failed to deserialize Google Search config file");
					return null;
				}

				return loaded_config;
			} catch (GLib.Error e) {
				GLib.warning("Failed to load Google Search config: %s", e.message);
			}
			
			return null;
		}
	}
}

