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
	 * Android startup: connection check, default model, history manager.
	 *
	 * Android-only counterpart to ollmapp/Initialize.vala.
	 *
	 * @since 1.0
	 */
	public class AndroidStartup : Object
	{
		private AndroidMainWindow window;

		/**
		 * Emitted when settings close and initialization should restart.
		 */
		public signal void reinitialize();

		public AndroidStartup(AndroidMainWindow window)
		{
			this.window = window;
		}

		/**
		 * Verifies connection and default chat model, then creates history manager.
		 *
		 * @param config Application configuration
		 * @return true when initialization succeeded
		 */
		public async bool run(OLLMchat.Settings.Config2 config)
		{
			AndroidConnectionConfigTls.apply_to_config (config);

			GLib.message (
				"AndroidStartup: run connections=%u",
				config.connections.size);

			while (true) {
				var checking_dialog =
					new SettingsDialog.CheckingConnectionDialog (
						this.window);

				var working_conn = (OLLMchat.Settings.Connection?) null;
				const uint MAX_CONN_ATTEMPTS = 5;
				for (var attempt = 0; attempt < MAX_CONN_ATTEMPTS;
				     attempt++) {
					if (attempt > 0) {
						GLib.message (
							"AndroidStartup: connection retry %u",
							attempt);
						GLib.Thread.usleep (1500000);
					}
					checking_dialog.show_dialog ();
					yield config.check_connections ();
					checking_dialog.hide_dialog ();
					working_conn = config.working_connection ();
					if (working_conn != null) {
						break;
					}
				}

				if (working_conn == null) {
					GLib.message (
						"AndroidStartup: run failed no working connection");
					yield this.show_settings(
						"No working connection found. Please check your connection settings.",
						"connections"
					);
					return false;
				}

				this.window.set_startup_status ("Loading model…");

				if (!(yield this.initialize_model (config, working_conn))) {
					GLib.message (
						"AndroidStartup: run failed no chat model");
					yield this.show_settings(
						"No chat model found (only embedding models available). "
						+ "Please add or select a model.",
						"models"
					);
					return false;
				}

				this.window.set_startup_status ("Preparing chat history…");

				try {
					AndroidApplication.ensure_app_data_directories (
						this.window.app.data_dir);
				} catch (GLib.Error e) {
					GLib.warning (
						"AndroidStartup: data dirs: %s", e.message);
				}

				this.window.history_manager = new OLLMchat.History.Manager(
					this.window.app
				);

				if (this.window.history_manager.default_model_usage != null) {
					var current_conn = config.connections.get(
						this.window.history_manager.default_model_usage.connection
					);
					if (current_conn == null || !current_conn.is_working) {
						this.window.history_manager.default_model_usage.connection =
							working_conn.url;
					}
				}

				// initialize_model already verified the saved model via /api/tags;
				// skip ensure_model_usage (loads /api/show for every model on server).

				break;
			}

			this.window.app.persist_config (config);
			var default_usage = config.usage.get ("default_model")
				as OLLMchat.Settings.ModelUsage;
			GLib.message (
				"AndroidStartup: run ok model=%s",
				default_usage != null ? default_usage.model : "");
			return true;
		}

		private async bool show_settings(string error_message, string settings_page)
		{
			var dialog_title = "Required Models Unavailable";
			switch (settings_page) {
				case "connections":
					dialog_title = "Connection Failed";
					break;
				case "models":
					dialog_title = "No Chat Model";
					break;
			}

			var alert = new Adw.AlertDialog(
				dialog_title,
				error_message + "\n\nPlease check your connection settings and try again."
			);
			alert.add_response("cancel", "Close");
			alert.add_response("settings", "Configure");
			alert.set_response_appearance(
				"settings", Adw.ResponseAppearance.SUGGESTED
			);
			var response = yield alert.choose(this.window, null);

			if (response != "settings") {
				(this.window.app as Gtk.Application).quit();
				return false;
			}

			ulong signal_id = 0;
			signal_id = this.window.settings_dialog.closed.connect(() => {
				this.window.settings_dialog.disconnect(signal_id);
				this.reinitialize();
			});

			this.window.settings_dialog.show_dialog.begin(settings_page);

			return true;
		}

		private async bool initialize_model(
			OLLMchat.Settings.Config2 config,
			OLLMchat.Settings.Connection working_conn
		) {
			var default_model = config.usage.get("default_model")
				as OLLMchat.Settings.ModelUsage;

			if (default_model != null && default_model.model != "") {
				if (default_model.connection == "") {
					default_model.connection = working_conn.url;
				}
				var name_lower = default_model.model.down ();
				if (name_lower.contains ("embed")
				    || name_lower.has_prefix ("bge-")) {
					default_model.model = "";
				} else {
					this.window.set_startup_status (
						"Loading model %s…".printf (
							default_model.model));
					if (yield this.load_one_model (
						working_conn, default_model.model)) {
						default_model.is_valid = true;
						GLib.message (
							"AndroidStartup: initialize_model ok model=%s",
							default_model.model);
						return true;
					}
					GLib.warning (
						"AndroidStartup: saved model '%s' unavailable",
						default_model.model);
					default_model.model = "";
				}
			}

			this.window.set_startup_status ("Fetching model list…");
			var client = new OLLMchat.Client (working_conn);
			Gee.ArrayList<OLLMchat.Response.Model> models_list;
			try {
				models_list = yield client.models ();
			} catch (GLib.Error e) {
				GLib.warning (
					"AndroidStartup: model list failed: %s", e.message);
				return false;
			}

			if (models_list.size == 0) {
				GLib.warning (
					"AndroidStartup: no models for connection '%s'",
					working_conn.url);
				return false;
			}

			foreach (var list_model in models_list) {
				if (list_model.is_hidden) {
					continue;
				}
				var pick_lower = list_model.name.down ();
				if (pick_lower.contains ("embed")
				    || pick_lower.has_prefix ("bge-")) {
					continue;
				}
				this.window.set_startup_status (
					"Loading model %s…".printf (list_model.name));
				if (!(yield this.load_one_model (
					working_conn, list_model.name))) {
					continue;
				}
				if (default_model == null) {
					default_model = new OLLMchat.Settings.ModelUsage () {
						connection = working_conn.url,
						model = list_model.name
					};
					config.usage.set ("default_model", default_model);
				} else {
					default_model.connection = working_conn.url;
					default_model.model = list_model.name;
				}
				default_model.is_valid = true;
				this.window.app.persist_config (config);
				GLib.message (
					"AndroidStartup: initialize_model ok model=%s",
					default_model.model);
				return true;
			}

			GLib.warning (
				"AndroidStartup: no chat model for connection '%s'",
				working_conn.url);
			return false;
		}

		/**
		 * Loads one model from disk cache or a single /api/show call.
		 *
		 * @param working_conn Connection to attach the model to
		 * @param model_name Model name on the server
		 * @return true when the model is in working_conn.models
		 */
		private async bool load_one_model (
			OLLMchat.Settings.Connection working_conn,
			string model_name
		) {
			if (working_conn.models.has_key (model_name)) {
				working_conn.models.get (model_name).connection =
					working_conn;
				return true;
			}

			var list_probe = new OLLMchat.Response.Model (working_conn) {
				name = model_name
			};
			var cached_model = list_probe.load_from_cache ();
			if (cached_model != null) {
				cached_model.connection = working_conn;
				working_conn.models.set (model_name, cached_model);
				GLib.message (
					"AndroidStartup: model cache hit %s", model_name);
				return true;
			}

			this.window.set_startup_status (
				"Fetching model details for %s…".printf (model_name));
			try {
				var show_call = new OLLMchat.Call.ShowModel (
					working_conn, model_name);
				var detailed_model = yield show_call.exec_show ();
				detailed_model.connection = working_conn;
				detailed_model.save_to_cache ();
				working_conn.models.set (model_name, detailed_model);
				GLib.message (
					"AndroidStartup: model fetched %s", model_name);
				return true;
			} catch (GLib.Error e) {
				GLib.warning (
					"AndroidStartup: show model %s: %s",
					model_name, e.message);
				return false;
			}
		}
	}
}
