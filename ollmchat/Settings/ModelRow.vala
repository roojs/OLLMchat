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

namespace OLLMchat.Settings
{
	/**
	 * Model row widget that extends Adw.ExpanderRow.
	 * 
	 * Stores the model object and options data, handles expansion/collapse
	 * and option editing using a shared OptionsWidget that gets reparented.
	 * 
	 * @since 1.0
	 */
	public class ModelRow : Adw.ExpanderRow
	{
		/**
		 * The model object from the connection.
		 */
		public OLLMchat.Response.Model model { get; construct; }

		/**
		 * The connection this model belongs to.
		 */
		public Connection connection { get; construct; }

		/**
		 * The model's options (can be modified).
		 */
		public OLLMchat.Call.Options options { get; private set; }

		public ModelsPage models_page { get; construct; }
		private bool is_expanding = false;

		/**
		 * Creates a new ModelRow.
		 * 
		 * @param model The model object
		 * @param connection The connection object
		 * @param options Initial options (will be cloned)
		 * @param models_page Parent ModelsPage containing the shared options widget
		 */
		public ModelRow( 
			OLLMchat.Response.Model model,
			Connection connection,
			OLLMchat.Call.Options options,
			ModelsPage models_page
		)
		{
			Object(
				model: model,
				connection: connection,
				models_page: models_page,
				title: model.name
			);
			this.options = options.clone();

			// Connect expand/collapse signal
			this.notify["expanded"].connect(() => {
				if (this.expanded) {
					this.expand();
				} else {
					this.collapse();
				}
			});
		}

		/**
		 * Loads options from config into this model row (called when refreshing).
		 * 
		 * @param new_options New options to load
		 */
		public void load_options(OLLMchat.Call.Options new_options)
		{
			this.options = new_options.clone();
			// Update widget values if currently expanded
			if (this.expanded) {
				this.load_options_with_parameters();
			}
		}


		/**
		 * Called when the row is expanded - reparents shared options widget.
		 */
		private void expand()
		{
			// Recursion guard - prevent re-entry
			if (this.is_expanding) {
				return;
			}
			this.is_expanding = true;

			// If rows are already attached to this row, just update values
			if (this.models_page.options_widget.current_model_row == this) {
				this.load_options_with_parameters();
				this.is_expanding = false;
				return;
			}

			// If another ModelRow currently has the widget, collapse it first
			var previous_row = this.models_page.options_widget.current_model_row;
			if (previous_row != null && previous_row != this) {
				previous_row.collapse();
			}
			
			// Attach option rows to this ExpanderRow (also sets current_model_row)
			this.models_page.options_widget.attach_to_model_row(this);
				
			// Load options into the widget with parameters
			this.load_options_with_parameters();
			this.is_expanding = false;
		}
		
		/**
		 * Loads options into the widget, using model.options for default values.
		 */
		private void load_options_with_parameters()
		{
			// Use model.options for default values (automatically filled from parameters)
			this.models_page.options_widget.load_options_with_model_defaults(this.options, this.model.options);
			
			// If parameters are not available, try to fetch model details asynchronously
			if ((this.model.parameters == null || this.model.parameters == "") && this.model.client != null) {
				this.fetch_model_parameters.begin();
			}
		}
		
		/**
		 * Fetches model details including parameters asynchronously.
		 */
		private async void fetch_model_parameters()
		{
			try {
				var detailed_model = yield this.model.client.show_model(this.model.name);
				// Update the model with parameters from the detailed model
				// This will automatically trigger fill_from_model via the setter
				if (detailed_model.parameters != null && detailed_model.parameters != "") {
					this.model.parameters = detailed_model.parameters;
					// Reload options with the newly fetched model defaults
					this.models_page.options_widget.load_options_with_model_defaults(this.options, this.model.options);
				}
			} catch (Error e) {
				// Silently fail - parameters are optional
				GLib.debug("Failed to fetch model parameters: %s", e.message);
			}
		}

		/**
		 * Called when the row is collapsed - saves options and reparents widget back.
		 * Can be called externally when another row expands.
		 */
		internal void collapse()
		{
			// Recursion guard - prevent re-entry
			if (this.is_expanding) {
				return;
			}
			this.is_expanding = true;

			// Only collapse if actually expanded
			if (!this.expanded) {
				this.is_expanding = false;
				return;
			}

			// Save options from widget
			this.models_page.options_widget.save_options(this.options);
			
			// Detach option rows from this ExpanderRow
			this.models_page.options_widget.detach_from_expander_row();

			// Clear the reference to this row in the options widget
			if (this.models_page.options_widget.current_model_row == this) {
				this.models_page.options_widget.current_model_row = null;
			}

			// Set expanded property to false to keep UI in sync
			// (This will trigger the signal handler, but the early return prevents recursion)
			this.expanded = false;
			
			// Save options to config - ModelsPage.save_options() will check if options
			// have non-default values and only save to config if they do
			this.models_page.save_options(this.model.name, this.options);
			
			this.is_expanding = false;
		}
	}
}

