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

		private OptionsWidget shared_options_widget;
		private bool is_expanded = false;

		/**
		 * Creates a new ModelRow.
		 * 
		 * @param model The model object
		 * @param connection_url Connection URL
		 * @param connection_name Connection display name
		 * @param options Initial options (will be cloned)
		 * @param shared_options_widget Shared OptionsWidget to reparent
		 */
		public ModelRow(
			OLLMchat.Response.Model model,
			string connection_url,
			string connection_name,
			OLLMchat.Call.Options options,
			OptionsWidget shared_options_widget
		)
		{
			Object(
				model: model,
				connection_url: connection_url,
				connection_name: connection_name
			);
			this.options = options.clone();
			this.shared_options_widget = shared_options_widget;
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
			if (this.is_expanded) {
				this.shared_options_widget.load_options(this.options);
			}
		}

		/**
		 * Saves current options from the shared widget to this model's options.
		 * Called when collapsing or when saving all options.
		 */
		public void save_current_options()
		{
			if (this.is_expanded) {
				this.shared_options_widget.save_options(this.options);
			}
		}

		/**
		 * Called when the row is expanded - creates option widgets lazily.
		 */
		private void expand()
		{
			if (this.options_created) {
				// Options already created, just update values
				foreach (var widget in this.option_widgets) {
					widget.load_options(this.options);
				}
				return;
			}

			// Create option widgets (only once)
			this.create_option_widgets();
			this.options_created = true;
		}

		/**
		 * Called when the row is collapsed - saves options.
		 */
		private void collapse()
		{
			// Update options from widgets
			foreach (var widget in this.option_widgets) {
				widget.save_options(this.options);
			}
			// Emit save signal
			this.save_options(this.options, this.model.name);
		}

		/**
		 * Creates all option widgets and adds them to the expander row.
		 */
		private void create_option_widgets()
		{
			// Connection (read-only label)
			var connection_row = new Adw.ActionRow() {
				title = "Connection"
			};
			var connection_label = new Gtk.Label(this.connection_name) {
				halign = Gtk.Align.END,
				hexpand = true
			};
			connection_row.add_suffix(connection_label);
			this.add_row(connection_row);

			// Model Name (read-only label)
			var model_name_row = new Adw.ActionRow() {
				title = "Model Name"
			};
			var model_name_label = new Gtk.Label(this.model.name) {
				halign = Gtk.Align.END,
				hexpand = true
			};
			model_name_row.add_suffix(model_name_label);
			this.add_row(model_name_row);

			// Separator
			var separator_row = new Adw.ActionRow();
			var separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
				hexpand = true
			};
			separator_row.add_suffix(separator);
			this.add_row(separator_row);

			// Create all option widgets
			this.option_widgets = OptionsWidget.create_option_rows(this.options);
			foreach (var widget in this.option_widgets) {
				this.add_row(widget);
			}
		}
	}
}

