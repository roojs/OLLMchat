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
		private Adw.ActionRow? separator_row = null;

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
		 * Called when the row is expanded - reparents shared options widget.
		 */
		private void expand()
		{
			if (this.is_expanded) {
				// Already expanded, just update values
				this.shared_options_widget.load_options(this.options);
				return;
			}

			// Check if the shared widget's children are already parented elsewhere
			// (i.e., another ModelRow is currently expanded)
			var rows_to_reparent = new Gee.ArrayList<Adw.ActionRow>();
			foreach (Gtk.Widget child in this.shared_options_widget.get_children()) {
				var row = child as Adw.ActionRow;
				if (row != null) {
					var current_parent = row.get_parent();
					if (current_parent != null && current_parent != this.shared_options_widget) {
						// Row is already parented to another ExpanderRow, remove it first
						current_parent.remove(row);
					}
					rows_to_reparent.add(row);
				}
			}

			// Add separator
			this.separator_row = new Adw.ActionRow();
			var separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
				hexpand = true
			};
			this.separator_row.add_suffix(separator);
			this.add_row(this.separator_row);

			// Remove from OptionsWidget and add to ExpanderRow
			foreach (var row in rows_to_reparent) {
				// Remove from OptionsWidget if it's still there
				if (row.get_parent() == this.shared_options_widget) {
					this.shared_options_widget.remove(row);
				}
				this.add_row(row);
			}

			// Load options into the widget
			this.shared_options_widget.load_options(this.options);
			this.is_expanded = true;
		}

		/**
		 * Called when the row is collapsed - saves options and reparents widget back.
		 */
		private void collapse()
		{
			if (!this.is_expanded) {
				return;
			}

			// Save options from widget
			this.shared_options_widget.save_options(this.options);
			
			// Collect all option rows that need to be reparented back
			var rows_to_reparent = new Gee.ArrayList<Adw.ActionRow>();
			foreach (Gtk.Widget child in this.get_children()) {
				var row = child as Adw.ActionRow;
				if (row != null && row != this.separator_row) {
					rows_to_reparent.add(row);
				}
			}

			// Remove option rows from ExpanderRow and add back to OptionsWidget
			foreach (var row in rows_to_reparent) {
				this.remove(row);
				this.shared_options_widget.append(row);
			}

			// Remove separator
			if (this.separator_row != null) {
				this.remove(this.separator_row);
				this.separator_row = null;
			}

			// Emit save signal
			this.save_options(this.options, this.model.name);
			this.is_expanded = false;
		}
	}
}

