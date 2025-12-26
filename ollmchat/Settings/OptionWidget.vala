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
	 * Widget that contains all option rows for model configuration.
	 * 
	 * @since 1.0
	 */
	public class OptionsWidget : Gtk.Box
	{
		public Gee.ArrayList<OptionRow> rows { get; private set; default = new Gee.ArrayList<OptionRow>(); }

		public OptionsWidget()
		{
			Object(orientation: Gtk.Orientation.VERTICAL);

			var temp_widget = new OptionFloatWidget() {
				title = "Temperature",
				subtitle = "Controls randomness in output (0.0 = deterministic, 2.0 = very random)",
				property_name = "temperature",
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.0
			};
			temp_widget.load_options(options);
			this.append(temp_widget);
			this.rows.add(temp_widget);

			var top_p_widget = new OptionFloatWidget() {
				title = "Top P",
				subtitle = "Nucleus sampling - considers tokens with cumulative probability up to this value",
				property_name = "top_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.9
			};
			top_p_widget.load_options(options);
			this.append(top_p_widget);
			this.rows.add(top_p_widget);

			var top_k_widget = new OptionIntWidget() {
				title = "Top K",
				subtitle = "Limits sampling to top K most likely tokens",
				property_name = "top_k",
				min_value = 1.0,
				max_value = 1000.0,
				default_value = 40.0
			};
			top_k_widget.load_options(options);
			this.append(top_k_widget);
			this.rows.add(top_k_widget);

			var num_ctx_widget = new OptionIntWidget() {
				title = "Num Ctx",
				subtitle = "Context window size - number of tokens the model can consider",
				property_name = "num_ctx",
				min_value = 1.0,
				max_value = 1000000.0,
				default_value = 2048.0
			};
			num_ctx_widget.load_options(options);
			this.append(num_ctx_widget);
			this.rows.add(num_ctx_widget);

			var num_predict_widget = new OptionIntWidget() {
				title = "Num Predict",
				subtitle = "Maximum number of tokens to generate (-1 = no limit)",
				property_name = "num_predict",
				min_value = 1.0,
				max_value = 1000000.0,
				default_value = -1.0
			};
			num_predict_widget.load_options(options);
			this.append(num_predict_widget);
			this.rows.add(num_predict_widget);

			var repeat_penalty_widget = new OptionFloatWidget() {
				title = "Repeat Penalty",
				subtitle = "Penalty for repeating tokens (1.0 = no penalty, >1.0 = penalty)",
				property_name = "repeat_penalty",
				min_value = 0.1,
				max_value = 10.0,
				step_value = 0.1,
				digits = 1,
				default_value = 1.1
			};
			repeat_penalty_widget.load_options(options);
			this.append(repeat_penalty_widget);
			this.rows.add(repeat_penalty_widget);

			var min_p_widget = new OptionFloatWidget() {
				title = "Min P",
				subtitle = "Minimum probability threshold for token selection",
				property_name = "min_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.0
			};
			min_p_widget.load_options(options);
			this.append(min_p_widget);
			this.rows.add(min_p_widget);

			var seed_widget = new OptionIntWidget() {
				title = "Seed",
				subtitle = "Random seed for reproducible outputs (-1 = random)",
				property_name = "seed",
				min_value = -1.0,
				max_value = 2147483647.0,
				default_value = -1.0
			};
			seed_widget.load_options(options);
			this.append(seed_widget);
			this.rows.add(seed_widget);

			var stop_widget = new OptionStringWidget() {
				title = "Stop",
				subtitle = "Stop sequences that cause generation to stop (comma-separated)",
				property_name = "stop",
				placeholder_text = "(optional)"
			};
			stop_widget.load_options(options);
			this.append(stop_widget);
			this.rows.add(stop_widget);
		}

		public void load_options(OLLMchat.Call.Options options)
		{
			foreach (var row in this.rows) {
				row.load_options(options);
			}
		}

		public void save_options(OLLMchat.Call.Options options)
		{
			foreach (var row in this.rows) {
				row.save_options(options);
			}
		}
	}
	/**
	 * Base class for option rows that can update their values from Options objects.
	 * 
	 * @since 1.0
	 */
	public abstract class OptionRow : Adw.ActionRow
	{
		/**
		 * Loads the widget's value from the options object.
		 * 
		 * @param options Options object to read value from
		 */
		public abstract void load_options(OLLMchat.Call.Options options);

		/**
		 * Saves the widget's current value to the options object.
		 * 
		 * @param options Options object to update
		 */
		public abstract void save_options(OLLMchat.Call.Options options);
	}

	/**
	 * Generic float option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionFloatWidget : OptionRow
	{
		public string property_name { get; set; }
		public double min_value { get; set; }
		public double max_value { get; set; }
		public double step_value { get; set; }
		public uint digits { get; set; }
		public double default_value { get; set; }
		public double unset_value { get; set; default = -1.0; }

		private Gtk.SpinButton spin_button;

		public OptionFloatWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 100.0, 1.0) {
				digits = 0
			};
			this.add_suffix(this.spin_button);
		}

		public override void load_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(double));
			options.get_property(this.property_name, ref val);
			var double_val = val.get_double();
			this.spin_button.value = double_val != this.unset_value ? double_val : this.default_value;
		}

		public override void save_options(OLLMchat.Call.Options options)
		{
			var val = this.spin_button.value;
			Value value = Value(typeof(double));
			value.set_double(val);
			options.set_property(this.property_name, value);
		}
	}

	/**
	 * Generic int option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionIntWidget : OptionRow
	{
		public string property_name { get; set; }
		public double min_value { get; set; }
		public double max_value { get; set; }
		public double step_value { get; set; default = 1.0; }
		public uint digits { get; set; default = 0; }
		public double default_value { get; set; }
		public int unset_value { get; set; default = -1; }

		private Gtk.SpinButton spin_button;

		public OptionIntWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 100.0, 1.0) {
				digits = 0
			};
			this.add_suffix(this.spin_button);
		}

		public override void load_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(int));
			options.get_property(this.property_name, ref val);
			var int_val = val.get_int();
			this.spin_button.value = int_val != this.unset_value ? (double)int_val : this.default_value;
		}

		public override void save_options(OLLMchat.Call.Options options)
		{
			var val = (int)this.spin_button.value;
			Value value = Value(typeof(int));
			value.set_int(val);
			options.set_property(this.property_name, value);
		}
	}

	/**
	 * Generic string option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionStringWidget : OptionRow
	{
		public string property_name { get; set; }
		public string placeholder_text { get; set; }

		private Gtk.Entry entry;

		public OptionStringWidget()
		{
			this.entry = new Gtk.Entry();			};
			this.add_suffix(this.entry);
		}

		public override void load_options(OLLMchat.Call.Options options)
		{
			Value val = Value(typeof(string));
			options.get_property(this.property_name, ref val);
			this.entry.text = val.get_string();
		}

		public override void save_options(OLLMchat.Call.Options options)
		{
			Value value = Value(typeof(string));
			value.set_string(this.entry.text);
			options.set_property(this.property_name, value);
		}
	}
}
