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

namespace OLLMapp
{
	/**
	 * Android remote-chat application entry.
	 *
	 * Loads config from app-private storage. Does not use desktop tool registries.
	 *
	 * @since 1.0
	 */
	public class AndroidApplication : Adw.Application, OLLMchat.ApplicationInterface
	{
		public OLLMchat.Settings.Config2 config { get; set; }
		public string data_dir { get; set; }

		public AndroidApplication()
		{
			Object(
				application_id: "org.roojs.ollmchat.androidpoc",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);

			this.data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat"
			);

			this.config = this.load_config();

			this.activate.connect(() => {
				this.ensure_data_dir();
				var window = new AndroidMainWindow(this);
				this.add_window(window);
				window.present();
			});
		}

		/**
		 * Loads config from app-private paths (Config2 only).
		 *
		 * Sets Config2.config_path under {data_dir}/config/ then loads or
		 * returns empty Config2. Does not use base_load_config() because
		 * that hardcodes ~/.config/ollmchat.
		 *
		 * @return Loaded or empty Config2 instance
		 */
		public OLLMchat.Settings.Config2 load_config()
		{
			var config_dir = GLib.Path.build_filename(this.data_dir, "config");
			var config_dir_file = GLib.File.new_for_path(config_dir);
			if (!config_dir_file.query_exists()) {
				try {
					config_dir_file.make_directory_with_parents(null);
				} catch (GLib.Error e) {
					GLib.warning("AndroidApplication: config dir: %s", e.message);
				}
			}

			var dummy2 = new OLLMchat.Settings.Config2();

			OLLMchat.Settings.Config2.config_path = GLib.Path.build_filename(
				config_dir, "config.2.json"
			);

			if (GLib.FileUtils.test(
				OLLMchat.Settings.Config2.config_path, GLib.FileTest.EXISTS
			)) {
				return OLLMchat.Settings.Config2.load();
			}

			return new OLLMchat.Settings.Config2();
		}
	}
}
