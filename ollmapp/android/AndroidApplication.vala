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

		static string app_private_files_dir ()
		{
			/* XDG_DATA_HOME is .../files/share (GTK asset tree). Keep app data in
			 * .../files/ollmchat instead of under share/. */
			return GLib.Path.get_dirname (GLib.Environment.get_user_data_dir ());
		}

		static void ensure_directory (string path) throws GLib.Error
		{
			var dir = GLib.File.new_for_path (path);

			if (dir.query_file_type (GLib.FileQueryInfoFlags.NONE)
			    == GLib.FileType.DIRECTORY) {
				return;
			}

			try {
				dir.make_directory_with_parents (null);
			} catch (GLib.IOError e) {
				if (e.code != GLib.IOError.EXISTS) {
					throw e;
				}
				if (dir.query_file_type (GLib.FileQueryInfoFlags.NONE)
				    != GLib.FileType.DIRECTORY) {
					throw new GLib.IOError.EXISTS (
						"Path exists but is not a directory: %s", path);
				}
			}
		}

		public AndroidApplication()
		{
			Object(
				application_id: "org.roojs.ollmchat.androidpoc",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);

			this.data_dir = GLib.Path.build_filename (
				app_private_files_dir (), "ollmchat");

			this.config = this.load_config();
			AndroidConnectionConfigTls.apply_to_config (this.config);

			this.activate.connect(() => {
				try {
					ensure_directory (this.data_dir);
				} catch (GLib.Error e) {
					GLib.critical (
						"AndroidApplication: data dir: %s", e.message);
					return;
				}

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
			try {
				ensure_directory (config_dir);
			} catch (GLib.Error e) {
				GLib.warning("AndroidApplication: config dir: %s", e.message);
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
