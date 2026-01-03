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

namespace OLLMchat.SettingsDialog.Rows
{
	/**
	 * Widget class for model properties.
	 * 
	 * Creates a dropdown widget populated with models from the selected connection.
	 * If property is within a ModelUsage, uses the connection from that ModelUsage.
	 * 
	 * @since 1.0
	 */
	public class Model : Row
	{
		private Gtk.DropDown dropdown;
		private OLLMchat.SettingsDialog.MainDialog settings_dialog;
		private Gtk.StringList string_list;
		
		/**
		 * Creates a new Model widget.
		 * 
		 * @param pspec The property spec for the model property
		 * @param config The config object that contains this property
		 * @param settings_dialog SettingsDialog to access Config2
		 */
		public Model(ParamSpec pspec, Object config, OLLMchat.SettingsDialog.MainDialog settings_dialog)
		{
			this.string_list = new Gtk.StringList({});
			base(pspec, config);
			this.settings_dialog = settings_dialog;
		}
		
		protected override void setup_widget()
		{
			// Create dropdown
			this.dropdown = new Gtk.DropDown(this.string_list, null) {
				valign = Gtk.Align.CENTER
			};
			this.add_suffix(this.dropdown);
			this.set_activatable_widget(this.dropdown);
			
			// Bind property changes - update config when selection changes
			this.dropdown.notify["selected"].connect(() => {
				if (this.loading_config) {
					return;
				}
				this.apply_property(this.config);
			});
		}
		
		public override void apply_property(Object obj)
		{
			
			
			var selected_item = this.string_list.get_item(this.dropdown.selected);
			
			var model_name = selected_item != null ? (selected_item as Gtk.StringObject).get_string() : "";
			Value new_val = Value(pspec.value_type);
			new_val.set_string(model_name);
			obj.set_property(this.pspec.get_name(), new_val);
		}
		
		/**
		 * Loads models from the specified connection.
		 * 
		 * @param connection_url The connection URL to fetch models from
		 * @param current_model The currently selected model name
		 */
		public async void load_models(string connection_url, string current_model)
		{
			this.loading_config = true;
			this.string_list = new Gtk.StringList({});
			this.dropdown.model = this.string_list;
			this.dropdown.selected = 0;
			if (connection_url == "") {
				this.loading_config = false;
				return;
			}
			
			var connection_obj = this.settings_dialog.app.config.connections.get(connection_url);
			
			// FIXME - model lists need some sorting rules and filtering rules globally
			try {
				var client = new OLLMchat.Client(connection_obj) {
					config = this.settings_dialog.app.config
				};
				var models_list = yield client.models();
				
				// Sort models alphabetically
				models_list.sort((a, b) => {
					return strcmp(a.name.down(), b.name.down());
				});
				
				// Create string list for dropdown
				string[] strings = {};
				uint selected_index = 0;
				for (var i = 0; i < models_list.size; i++) {
					var model = models_list.get(i);
					strings += model.name;
					if (current_model == model.name) {
						selected_index = (uint)i;
					}
				}
				this.string_list = new Gtk.StringList(strings);
				this.dropdown.model = this.string_list;
				this.dropdown.selected = selected_index;

			} catch (GLib.Error e) {
				GLib.warning("Failed to fetch models from connection %s: %s", connection_url, e.message);
			}
			
			this.loading_config = false;
		}
	}
}

