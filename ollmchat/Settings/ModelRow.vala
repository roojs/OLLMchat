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
		private OptionsWidget? options_widget = null;

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
				this.load_defaults();
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

			// Collapse other expanded ModelRows
			foreach (var row in this.models_page.model_rows.values) {
				if (row != this && row.expanded) {
					row.collapse();
				}
			}

			// If widget already exists, just update values
			if (this.options_widget != null) {
				this.load_defaults();
				this.is_expanding = false;
				return;
			}
			
			// Create new OptionsWidget for this ModelRow
			this.options_widget = new OptionsWidget();
			
			// Add rows from options_widget to this ExpanderRow
			foreach (var row in this.options_widget.rows) {
				this.add_row(row);
			}
				
			// Load default values from model.options and then load options
			this.load_defaults();
			
			// Scroll to position this row 20px below the top of the view
			// Use timeout to wait for expand animation to complete
			Timeout.add(300, () => {
				this.models_page.scroll_to(this);
				return false; // Don't repeat
			});
			
			this.is_expanding = false;
		}
		
		/**
		 * Loads default values from model.options and then loads options.
		 */
		private void load_defaults()
		{
			// Use model.options for default values (automatically filled from parameters)
			GLib.debug("load_defaults for model '%s' - parameters: '%s'", this.model.name, this.model.parameters ?? "(null)");
			GLib.debug("load_defaults: model.options.temperature = %f, top_k = %d, top_p = %f", 
				this.model.options.temperature, this.model.options.top_k, this.model.options.top_p);
			foreach (var row in this.options_widget.rows) {
				GLib.debug("load_defaults: Processing row.pname = '%s'", row.pname);
				// Convert underscore to hyphen for GObject property name
				var property_name = row.pname.replace("_", "-");
				
				// Load user's options first
				row.load_options(this.options);
				
				// Then check if model has a default value and set it if user option is unset
				// Use switch case on property name (with hyphens - Vala uses hyphens for GObject)
				switch (property_name) {
					// Integer properties
					case "seed":
					case "top-k":
					case "num-predict":
					case "num-ctx":
						Value model_value = Value(typeof(int));
						((GLib.Object)this.model.options).get_property(property_name, ref model_value);
						var int_val = model_value.get_int();
						GLib.debug("load_defaults: %s = %d", row.pname, int_val);
						if (int_val != -1) {
							row.set_model_value(model_value);
						}
						break;
					
					// Double properties
					case "temperature":
					case "top-p":
					case "min-p":
						Value model_value = Value(typeof(double));
						((GLib.Object)this.model.options).get_property(property_name, ref model_value);
						var double_val = model_value.get_double();
						GLib.debug("load_defaults: %s = %f", row.pname, double_val);
						if (double_val != -1.0) {
							row.set_model_value(model_value);
						}
						break;
					
					default:
						break;
				}
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
			if (this.options_widget != null) {
				this.options_widget.save_options(this.options);
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

