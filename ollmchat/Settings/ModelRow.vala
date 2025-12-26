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
	 * and option editing.
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

		private bool options_created = false;
		public Gee.ArrayList<OptionRow> option_widgets { get; private set; default = new Gee.ArrayList<OptionRow>(); }

		/**
		 * Creates a new ModelRow.
		 * 
		 * @param model The model object
		 * @param connection_url Connection URL
		 * @param connection_name Connection display name
		 * @param options Initial options (will be cloned)
		 */
		public ModelRow(
			OLLMchat.Response.Model model,
			string connection_url,
			string connection_name,
			OLLMchat.Call.Options options
		)
		{
			Object(
				model: model,
				connection_url: connection_url,
				connection_name: connection_name
			);
			this.options = options.clone();
			this.title = model.name;
			this.subtitle = connection_name;

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
			// Update widget values if they've been created
			if (this.options_created) {
				foreach (var widget in this.option_widgets) {
					widget.load_options(this.options);
				}
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
			var temp_widget = new OptionFloatWidget() {
				title = "Temperature",
				subtitle = "Controls randomness in output (0.0 = deterministic, 2.0 = very random)",
				property_name = "temperature",
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.0,
				unset_value = -1.0
			};
			temp_widget.load_options(this.options);
			this.add_row(temp_widget);
			this.option_widgets.add(temp_widget);

			var top_p_widget = new OptionFloatWidget() {
				title = "Top P",
				subtitle = "Nucleus sampling - considers tokens with cumulative probability up to this value",
				property_name = "top_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.9,
				unset_value = -1.0
			};
			top_p_widget.load_options(this.options);
			this.add_row(top_p_widget);
			this.option_widgets.add(top_p_widget);

			var top_k_widget = new OptionIntWidget() {
				title = "Top K",
				subtitle = "Limits sampling to top K most likely tokens",
				property_name = "top-k",
				min_value = 1.0,
				max_value = 1000.0,
				step_value = 1.0,
				digits = 0,
				default_value = 40.0,
				unset_value = -1
			};
			top_k_widget.load_options(this.options);
			this.add_row(top_k_widget);
			this.option_widgets.add(top_k_widget);

			var num_ctx_widget = new OptionIntWidget() {
				title = "Num Ctx",
				subtitle = "Context window size - number of tokens the model can consider",
				property_name = "num-ctx",
				min_value = 1.0,
				max_value = 1000000.0,
				step_value = 1.0,
				digits = 0,
				default_value = 2048.0,
				unset_value = -1
			};
			num_ctx_widget.load_options(this.options);
			this.add_row(num_ctx_widget);
			this.option_widgets.add(num_ctx_widget);

			var num_predict_widget = new OptionIntWidget() {
				title = "Num Predict",
				subtitle = "Maximum number of tokens to generate (-1 = no limit)",
				property_name = "num-predict",
				min_value = 1.0,
				max_value = 1000000.0,
				step_value = 1.0,
				digits = 0,
				default_value = -1.0,
				unset_value = -1
			};
			num_predict_widget.load_options(this.options);
			this.add_row(num_predict_widget);
			this.option_widgets.add(num_predict_widget);

			var repeat_penalty_widget = new OptionFloatWidget() {
				title = "Repeat Penalty",
				subtitle = "Penalty for repeating tokens (1.0 = no penalty, >1.0 = penalty)",
				property_name = "repeat-penalty",
				min_value = 0.1,
				max_value = 10.0,
				step_value = 0.1,
				digits = 1,
				default_value = 1.1,
				unset_value = -1.0
			};
			repeat_penalty_widget.load_options(this.options);
			this.add_row(repeat_penalty_widget);
			this.option_widgets.add(repeat_penalty_widget);

			var min_p_widget = new OptionFloatWidget() {
				title = "Min P",
				subtitle = "Minimum probability threshold for token selection",
				property_name = "min-p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.0,
				unset_value = -1.0
			};
			min_p_widget.load_options(this.options);
			this.add_row(min_p_widget);
			this.option_widgets.add(min_p_widget);

			var seed_widget = new OptionIntWidget() {
				title = "Seed",
				subtitle = "Random seed for reproducible outputs (-1 = random)",
				property_name = "seed",
				min_value = -1.0,
				max_value = 2147483647.0,
				step_value = 1.0,
				digits = 0,
				default_value = -1.0,
				unset_value = -1
			};
			seed_widget.load_options(this.options);
			this.add_row(seed_widget);
			this.option_widgets.add(seed_widget);

			var stop_widget = new OptionStringWidget() {
				title = "Stop",
				subtitle = "Stop sequences that cause generation to stop (comma-separated)",
				property_name = "stop",
				placeholder_text = "(optional)"
			};
			stop_widget.load_options(this.options);
			this.add_row(stop_widget);
			this.option_widgets.add(stop_widget);
		}
	}
}

