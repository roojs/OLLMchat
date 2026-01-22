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

namespace OLLMapp.SettingsDialog.Rows
{
	/**
	 * Widget class for model properties.
	 * 
	 * Creates a dropdown widget populated with models from the selected connection.
	 * If property is within a ModelUsage, uses the connection from that ModelUsage.
	 * Uses ConnectionModels from history manager with connection filter.
	 * 
	 * @since 1.0
	 */
	public class Model : Row
	{
	private Gtk.DropDown dropdown;
	private OLLMchat.Settings.ConnectionModels? connection_models = null;
	private Gtk.FilterListModel? filtered_models = null;
	private OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage>? sorted_models = null;
	private OLLMchatGtk.List.ModelUsageFilter connection_filter;
	private OLLMchatGtk.List.ModelUsageFactory factory;
		
		/**
		 * Creates a new Model widget.
		 * 
		 * @param dialog SettingsDialog to access Config2
		 * @param config The config object that contains this property
		 * @param pspec The property spec for the model property
		 */
		public Model(MainDialog dialog, Object config, ParamSpec pspec)
		{
			base(dialog, config, pspec);
			
			// Get ConnectionModels from parent window's history manager
			var parent_window = dialog.parent as OllmchatWindow;
			if (parent_window != null && parent_window.history_manager != null) {
				this.connection_models = parent_window.history_manager.connection_models;
			}
			
			// Create connection filter (initially empty to match all)
			this.connection_filter = new OLLMchatGtk.List.ModelUsageFilter("");
		}
		
		protected override void setup_widget()
		{
			// Create dropdown with empty model initially
			this.dropdown = new Gtk.DropDown(null, null) {
				valign = Gtk.Align.CENTER
			};
			this.add_suffix(this.dropdown);
			this.set_activatable_widget(this.dropdown);
			
			// Create factory for displaying model names (keep reference to prevent garbage collection)
			this.factory = new OLLMchatGtk.List.ModelUsageFactory();
			
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
			if (this.sorted_models == null || this.dropdown.selected == Gtk.INVALID_LIST_POSITION) {
				Value new_val = Value(pspec.value_type);
				new_val.set_string("");
				obj.set_property(this.pspec.get_name(), new_val);
				return;
			}
			
			var model_usage = this.sorted_models.get_item_typed(this.dropdown.selected);
			var model_name = model_usage != null ? model_usage.model : "";
			Value new_val = Value(pspec.value_type);
			new_val.set_string(model_name);
			obj.set_property(this.pspec.get_name(), new_val);
		}
		
		/**
		 * Loads models from the specified connection.
		 * 
		 * Uses ConnectionModels with connection filter instead of fetching models directly.
		 * 
		 * @param connection_url The connection URL to fetch models from
		 * @param current_model The currently selected model name
		 */
		public async void load_models(string connection_url, string current_model)
		{
			this.loading_config = true;
			
			// Clear dropdown if no connection
			if (connection_url == "" || this.connection_models == null) {
				this.dropdown.model = null;
				this.dropdown.selected = Gtk.INVALID_LIST_POSITION;
				this.loading_config = false;
				return;
			}
			
			// Update connection filter
			this.connection_filter.connection_url = connection_url;
			
			// Create filtered list model
			this.filtered_models = new Gtk.FilterListModel(this.connection_models, this.connection_filter);
			
			// Create sorted list model
			// Filter out ollmchat-temp/ models - they should never appear in model lists
			// (Phase 3: Hide all ollmchat-temp from model lists)
			this.sorted_models = new OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage>(
				this.filtered_models,
				new OLLMchatGtk.List.ModelUsageSort(),
				new Gtk.CustomFilter((item) => {
					return !((OLLMchat.Settings.ModelUsage)item).model.has_prefix("ollmchat-temp/");
				})
			);
			
			// Set up dropdown with sorted models
			this.dropdown.model = this.sorted_models;
			this.dropdown.set_factory(this.factory.factory);
			this.dropdown.set_list_factory(this.factory.factory);
			
			// Find and select current model using O(1) lookup
			uint selected_index = Gtk.INVALID_LIST_POSITION;
			if (current_model != "") {
				var model_usage = this.connection_models.find_model(connection_url, current_model);
				if (model_usage != null) {
					selected_index = this.sorted_models.find_position(model_usage);
				}
			}
			this.dropdown.selected = selected_index;
			
			this.loading_config = false;
		}
	}
}

