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
	 * Loads config from persistent storage outside the GTK asset sandbox.
	 *
	 * @since 1.0
	 */
	public class AndroidApplication : Adw.Application, OLLMchat.ApplicationInterface
	{
		public OLLMchat.Settings.Config2 config { get; set; }
		public string data_dir { get; set; }

		static string app_private_files_dir ()
		{
			/* XDG_DATA_HOME is externalFilesDir/share (GTK asset tree, re-extracted
			 * on APK update). App data lives beside share/, not under it. */
			return GLib.Path.get_dirname (GLib.Environment.get_user_data_dir ());
		}

		static string config_storage_dir ()
		{
			/* XDG_CONFIG_HOME is externalFilesDir/etc — outside share/. */
			return GLib.Path.build_filename (
				GLib.Environment.get_user_config_dir (), "ollmchat");
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

		/**
		 * Ensures app data, history, config, and model-cache directories exist.
		 *
		 * Uses EXISTS-tolerant creation so History.Manager does not abort when
		 * a concurrent mkdir races (Manager uses query_exists + make_directory).
		 *
		 * @param data_dir Application data directory ({@link data_dir})
		 */
		public static void ensure_app_data_directories (string data_dir)
			throws GLib.Error
		{
			ensure_directory (data_dir);
			ensure_directory (
				GLib.Path.build_filename (data_dir, "history"));
			ensure_directory (
				GLib.Path.build_filename (data_dir, "config"));
			ensure_directory (GLib.Path.build_filename (
				GLib.Environment.get_user_data_dir (),
				"ollmchat", "models"));
		}

		public AndroidApplication()
		{
			Object(
				application_id: "org.roojs.ollmchat.androidpoc",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);

			this.data_dir = GLib.Path.build_filename (
				app_private_files_dir (), "ollmchat");

			/* Config loads on window realize when XDG paths are ready. */
			this.config = new OLLMchat.Settings.Config2 ();
			AndroidConnectionConfigTls.apply_to_config (this.config);

			this.activate.connect(() => {
				try {
					AndroidApplication.ensure_app_data_directories (
						this.data_dir);
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
		 * Ensures Config2.config_path and saves to persistent storage.
		 *
		 * Config lives under XDG_CONFIG_HOME (external etc/ollmchat/), not under
		 * the GTK asset tree in share/, so it survives APK asset re-extraction.
		 *
		 * @param config config to save; defaults to this.config when null
		 */
		public void persist_config (OLLMchat.Settings.Config2? config = null)
		{
			var to_save = config ?? this.config;
			var target_dir = config_storage_dir ();
			var target_path = GLib.Path.build_filename (
				target_dir, "config.2.json");

			OLLMchat.Settings.Config2.config_path = target_path;

			try {
				ensure_directory (target_dir);
			} catch (GLib.Error e) {
				GLib.warning ("AndroidApplication: config dir: %s", e.message);
				return;
			}

			var root = Json.gobject_serialize (to_save);
			if (root == null) {
				GLib.warning ("AndroidApplication: config serialize failed");
				return;
			}

			var generator = new Json.Generator ();
			generator.pretty = true;
			generator.indent = 4;
			generator.set_root (root);

			try {
				var json_text = generator.to_data (null);
				GLib.FileUtils.set_contents (target_path, json_text);
				GLib.message (
					"AndroidApplication: saved config to %s", target_path);
			} catch (GLib.Error e) {
				GLib.warning (
					"AndroidApplication: config save failed: %s", e.message);
			}
		}

		/**
		 * Loads config from persistent storage (Config2 only).
		 *
		 * Sets Config2.config_path under XDG_CONFIG_HOME/ollmchat/ then loads or
		 * returns empty Config2. Migrates from legacy {data_dir}/config/ or
		 * share/ollmchat/config/ paths when present. Does not use
		 * base_load_config() because that hardcodes ~/.config/ollmchat.
		 *
		 * @return Loaded or empty Config2 instance
		 */
		public OLLMchat.Settings.Config2 load_config()
		{
			var target_dir = config_storage_dir ();
			var target_path = GLib.Path.build_filename (
				target_dir, "config.2.json");

			if (!GLib.FileUtils.test (target_path, GLib.FileTest.EXISTS)) {
				var legacy_paths = new string[] {
					GLib.Path.build_filename (
						this.data_dir, "config", "config.2.json"),
					GLib.Path.build_filename (
						GLib.Environment.get_user_data_dir (),
						"ollmchat", "config", "config.2.json"),
				};

				foreach (var legacy_path in legacy_paths) {
					if (!GLib.FileUtils.test (
						legacy_path, GLib.FileTest.EXISTS)) {
						continue;
					}

					try {
						ensure_directory (target_dir);
						GLib.File.new_for_path (legacy_path).copy (
							GLib.File.new_for_path (target_path),
							GLib.FileCopyFlags.NONE, null);
						GLib.message (
							"AndroidApplication: migrated config from %s",
							legacy_path);
						break;
					} catch (GLib.Error e) {
						GLib.warning (
							"AndroidApplication: config migration: %s",
							e.message);
					}
				}
			}

			try {
				ensure_directory (target_dir);
			} catch (GLib.Error e) {
				GLib.warning ("AndroidApplication: config dir: %s", e.message);
			}

			OLLMchat.Settings.Config2.config_path = target_path;

			if (GLib.FileUtils.test (target_path, GLib.FileTest.EXISTS)) {
				var loaded = OLLMchat.Settings.Config2.load ();
				GLib.message (
					"AndroidApplication: load_config path=%s connections=%u",
					target_path, loaded.connections.size);
				return loaded;
			}

			GLib.message (
				"AndroidApplication: load_config path=%s connections=0 (no file)",
				target_path);
			return new OLLMchat.Settings.Config2 ();
		}
	}
}
