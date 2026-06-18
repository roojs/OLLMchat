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

				this.window.startup_status_label.label = "Loading model…";

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

				this.window.startup_status_label.label = "Preparing chat history…";

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

				AndroidToolsRegistration.fill_tools(
					this.window.history_manager);

				if (this.window.history_manager.default_model_usage != null) {
					var current_conn = config.connections.get(
						this.window.history_manager.default_model_usage.connection
					);
					if (current_conn == null || !current_conn.is_working) {
						this.window.history_manager.default_model_usage.connection =
							working_conn.url;
					}
				}

				try {
					yield this.window.history_manager.ensure_model_usage();
				} catch (GLib.Error e) {
					GLib.warning(
						"AndroidStartup: model verification failed: %s",
						e.message);
					if (!(yield this.initialize_model(config, working_conn))) {
						yield this.show_settings(
							"No chat model found (only embedding models available). "
							+ "Please add or select a model.",
							"models"
						);
						return false;
					}
				}

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

			this.window.startup_status_label.label = "Loading models…";
			var temp_connection_models = new OLLMchat.Settings.ConnectionModels(
				config
			);
			yield temp_connection_models.refresh();

			var connection_models = temp_connection_models.connection_map.get(
				working_conn.url
			);
			if (connection_models == null || connection_models.size == 0) {
				GLib.warning(
					"AndroidStartup: no models for connection '%s'",
					working_conn.url);
				return false;
			}

			if (default_model != null && default_model.model != "") {
				if (default_model.connection == "") {
					default_model.connection = working_conn.url;
				}
				var usage = temp_connection_models.find_model(
					default_model.connection, default_model.model);
				if (usage != null
				    && usage.model_obj != null
				    && usage.model_obj.is_embedding) {
					default_model.model = "";
				}
			}

			if (default_model != null && default_model.model != "") {
				var conn_obj = config.connections.get(default_model.connection);
				if (conn_obj != null
				    && conn_obj.models.size > 0
				    && conn_obj.models.has_key(default_model.model)) {
					var usage = temp_connection_models.find_model(
						default_model.connection, default_model.model);
					if (usage == null
					    || usage.model_obj == null
					    || !usage.model_obj.is_embedding) {
						GLib.message (
							"AndroidStartup: initialize_model ok model=%s",
							default_model.model);
						return true;
					}
					default_model.model = "";
				} else {
					if (yield default_model.verify_model(config)) {
						var usage = temp_connection_models.find_model(
							default_model.connection, default_model.model);
						if (usage == null
						    || usage.model_obj == null
						    || !usage.model_obj.is_embedding) {
							GLib.message (
								"AndroidStartup: initialize_model ok model=%s",
								default_model.model);
							return true;
						}
						default_model.model = "";
					} else {
						default_model.model = "";
					}
				}
			}

			OLLMchat.Settings.ModelUsage? first_chat_model = null;
			foreach (var model_usage in connection_models.values) {
				if (model_usage.model_obj == null
				    || model_usage.model_obj.is_hidden
				    || model_usage.model_obj.is_embedding) {
					continue;
				}
				first_chat_model = model_usage;
				break;
			}
			if (first_chat_model == null) {
				GLib.warning(
					"AndroidStartup: no chat model for connection '%s'",
					working_conn.url);
				return false;
			}

			if (default_model == null) {
				default_model = new OLLMchat.Settings.ModelUsage() {
					connection = first_chat_model.connection,
					model = first_chat_model.model,
					options = first_chat_model.options.clone()
				};
				config.usage.set("default_model", default_model);
			} else {
				default_model.connection = first_chat_model.connection;
				default_model.model = first_chat_model.model;
				default_model.options = first_chat_model.options.clone();
			}

			this.window.app.persist_config (config);
			GLib.message (
				"AndroidStartup: initialize_model ok model=%s",
				default_model.model);
			return true;
		}
	}
}
