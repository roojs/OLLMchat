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
		 * The connection URL this model belongs to.
		 */
		public string connection_url { get; construct; }

		/**
		 * The connection display name.
		 */
		public string connection_name { get; construct; }

		/**
		 * The model's options (can be modified).
		 */
		public OLLMchat.Call.Options options { get; private set; }

		/**
		 * Callback to save options when collapsed.
		 */
		public signal void save_options(OLLMchat.Call.Options options, string model_name);

		private ModelsPage models_page;
		private bool is_expanding = false;

		/**
		 * Creates a new ModelRow.
		 * 
		 * @param model The model object
		 * @param connection_url Connection URL
		 * @param connection_name Connection display name
		 * @param options Initial options (will be cloned)
		 * @param models_page Parent ModelsPage containing the shared options widget
		 */
		public ModelRow( 
			OLLMchat.Response.Model model,
			string connection_url,
			string connection_name,
			OLLMchat.Call.Options options,
			ModelsPage models_page
		)
		{
			Object(
				model: model,
				connection_url: connection_url,
				connection_name: connection_name
			);
			this.options = options.clone();
			this.models_page = models_page;
			this.title = model.name;

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
		 * Updates the options from config (called when refreshing).
		 * 
		 * @param new_options New options to merge
		 */
		public void update_options(OLLMchat.Call.Options new_options)
		{
			this.options = new_options.clone();
			// Update widget values if currently expanded
			if (this.is_expanding) {
				this.models_page.options_widget.load_options(this.options);
			}
		}

		/**
		 * Saves current options from the shared widget to this model's options.
		 * Called when collapsing or when saving all options.
		 */
		public void save_current_options()
		{
			if (this.is_expanding) {
				this.models_page.options_widget.save_options(this.options);
			}
		}

		/**
		 * Called when the row is expanded - reparents shared options widget.
		 */
		private void expand()
		{
			if (this.is_expanding) {
				// Already expanded, just update values
				this.models_page.options_widget.load_options(this.options);
				return;
			}

			// If another ModelRow currently has the widget, collapse it first
			var previous_row = this.models_page.options_widget.current_model_row;
			if (previous_row != null && previous_row != this) {
				previous_row.collapse();
			}
			
			// Set this row as the current owner of the options widget
			this.models_page.options_widget.current_model_row = this;
			
			// Add the OptionsWidget Box directly to the ExpanderRow
			// Using append() to add it as a child of the ExpanderRow (not the parent list)
			// This is the correct way - the theoretical code using this.parent.insert_child_after()
			// would add it to the parent container after this ModelRow, not inside it
			this.append(this.models_page.options_widget);			

			// Load options into the widget
			this.models_page.options_widget.load_options(this.options);
			this.is_expanding = true;
		}

		/**
		 * Called when the row is collapsed - saves options and reparents widget back.
		 * Can be called externally when another row expands.
		 */
		internal void collapse()
		{
			if (!this.is_expanding) {
				return;
			}

			// Save options from widget
			this.models_page.options_widget.save_options(this.options);
			
			// Remove the OptionsWidget Box from the ExpanderRow
			// The OptionRows are already inside the OptionsWidget, so we just remove the Box
			if (this.models_page.options_widget.get_parent() == this) {
				this.remove(this.models_page.options_widget);
			}

			// Clear the reference to this row in the options widget
			if (this.models_page.options_widget.current_model_row == this) {
				this.models_page.options_widget.current_model_row = null;
			}

			// Set is_expanding to false first to prevent recursion if signal fires
			this.is_expanding = false;
			
			// Set expanded property to false to keep UI in sync
			// (This will trigger the signal handler, but the early return prevents recursion)
			this.expanded = false;
			
			// Emit save signal
			this.save_options(this.options, this.model.name);
		}
	}
}

