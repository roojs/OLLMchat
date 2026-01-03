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

namespace OLLMchat.OLLMchat.SettingsDialog.Rows
{
	/**
	 * Widget class for connection properties.
	 * 
	 * Creates a dropdown widget populated from Config2.connections map.
	 * 
	 * @since 1.0
	 */
	public class Connection : Row
	{
		public Gtk.DropDown dropdown;
		private OLLMchat.SettingsDialog.MainDialog settings_dialog;
		private Gtk.StringList string_list;
		
		/**
		 * Creates a new Connection widget.
		 * 
		 * @param pspec The property spec for the connection property
		 * @param config The config object that contains this property
		 * @param settings_dialog SettingsDialog to access Config2
		 */
		public Connection(ParamSpec pspec, Object config, OLLMchat.SettingsDialog.MainDialog settings_dialog)
		{
			this.string_list = new Gtk.StringList({});
			base(pspec, config);
			this.settings_dialog = settings_dialog;
			
		}
		
		protected override void setup_widget()
		{
			// Create dropdown (will be populated in load_config)
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
		
		public override void load_config(Object config)
		{
			// Block signal handler during load
			this.loading_config = true;
			
			// Get current value (connection URL)
			Value val = Value(pspec.value_type);
			config.get_property(this.pspec.get_name(), ref val);
			var current_url = val.get_string();
			
			// Build URLs array and find selected index in one pass
			string[] urls = {};
			uint selected_index = 0;
			int index = 0;
			foreach (var entry in this.settings_dialog.app.config.connections.entries) {
				urls += entry.key;
				if (entry.key == current_url) {
					selected_index = (uint)index;
				}
				index++;
			}
			
			// Create string list for dropdown
			this.string_list = new Gtk.StringList(urls);
			this.dropdown.model = this.string_list;
			this.dropdown.selected = selected_index;
			
			// Unblock signal handler
			this.loading_config = false;
		}
		
		public override void apply_property(Object obj)
		{
			
		 
			var selected_item = this.string_list.get_item(this.dropdown.selected);
			
			var url = selected_item != null ? (selected_item as Gtk.StringObject).get_string() : "";
			Value new_val = Value(pspec.value_type);
			new_val.set_string(url);
			obj.set_property(this.pspec.get_name(), new_val);
		}
	}
}

