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
	 * Stores option rows in an ArrayList and manages attaching/detaching them
	 * to/from ExpanderRows.
	 * 
	 * @since 1.0
	 */
	public class OptionsWidget : GLib.Object
	{
		/**
		 * The ModelRow that currently has this widget assigned to it.
		 * Used to call collapse() when another row expands.
		 */
		public ModelRow? current_model_row { get; set; }

		/**
		 * List of all option rows managed by this widget.
		 */
		public Gee.ArrayList<OptionRow> rows = new Gee.ArrayList<OptionRow>();

		public OptionsWidget()
		{
			this.rows.add(new OptionFloatWidget() {
				title = "Temperature",
				subtitle = "Controls randomness in output (0.0 = deterministic, 2.0 = very random)",
				pname = "temperature",
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.7
			});

			this.rows.add(new OptionFloatWidget() {
				title = "Top P",
				subtitle = "Nucleus sampling - considers tokens with cumulative probability up to this value",
				pname = "top_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.9
			});

			this.rows.add(new OptionIntWidget() {
				title = "Top K",
				subtitle = "Limits sampling to top K most likely tokens",
				pname = "top_k",
				min_value = 1.0,
				max_value = 1000.0,
				default_value = 40.0
			});

			this.rows.add(new OptionIntWidget() {
				title = "Num Ctx",
				subtitle = "Context window size - number of tokens the model can consider",
				pname = "num_ctx",
				min_value = 1.0,
				max_value = 1000000.0,
				step_value = 1024.0,
				default_value = 16384.0
			});

			this.rows.add(new OptionIntWidget() {
				title = "Num Predict",
				subtitle = "Maximum number of tokens to generate (-1 = no limit)",
				pname = "num_predict",
				min_value = 1.0,
				max_value = 1000000.0,
				default_value = 16384.0
			});

			this.rows.add(new OptionFloatWidget() {
				title = "Min P",
				subtitle = "Minimum probability threshold for token selection",
				pname = "min_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.1
			});

			this.rows.add(new OptionIntWidget() {
				title = "Seed",
				subtitle = "Random seed used for reproducible outputs (-1 = random)",
				pname = "seed",
				min_value = -1.0,
				max_value = 2147483647.0,
				default_value = 42.0
			});
		}

		public void load_options(OLLMchat.Call.Options options)
		{
			foreach (var row in this.rows) {
				row.load_options(options);
			}
		}
		
		/**
		 * Loads options with default values from model.options.
		 * 
		 * @param options Options object to read values from (user's custom options)
		 * @param model_options Optional model's default options (from model.options)
		 */

		public void save_options(OLLMchat.Call.Options options)
		{
			foreach (var row in this.rows) {
				row.save_options(options);
			}
		}

		/**
		 * Attaches all option rows to the given ModelRow's ExpanderRow.
		 * 
		 * @param model_row The ModelRow to attach option rows to
		 */
		public void attach_to_model_row(ModelRow model_row)
		{
			// Set this row as the current owner
			this.current_model_row = model_row;

			// Defer the entire operation (detach and attach) to an idle callback
			// This ensures GTK has fully processed any previous operations before
			// we start manipulating the widget hierarchy
			Idle.add_full(Priority.LOW, () => {
				// Verify this is still the current model row (might have changed)
				if (this.current_model_row != model_row) {
					return false; // Don't proceed if model row changed
				}
				
				// Clear any previously attached rows (do this in idle too)
				this.detach_from_expander_row();
				
				// Now add each OptionRow to the ExpanderRow
				// By this point, GTK should have processed all unparenting
				// and widgets should be in a clean state without old sibling references
				foreach (var option_row in this.rows) {
					if (option_row.get_parent() == null) {
						model_row.add_row(option_row);
						option_row.visible = true;
					}
				}
				return false; // Don't repeat
			});
		}

		/**
		 * Detaches all option rows from their current ExpanderRow parent.
		 */
		public void detach_from_expander_row()
		{
			// Remove each OptionRow that was attached to an ExpanderRow
			foreach (var option_row in this.rows) {
				if (option_row.get_parent() != null) {
					option_row.unparent();
				}
			}
		}
	}

	/**
	 * Base class for option rows that can update their values from Options objects.
	 * 
	 * Provides Auto/clear button functionality for options that support auto mode.
	 * 
	 * @since 1.0
	 */
	public abstract class OptionRow : Adw.ActionRow
	{
		/**
		 * The value widget (SpinButton, Entry, etc.) that should be shown/hidden.
		 */
		protected Gtk.Widget? value_widget { get; set; }
		
		/**
		 * The property name in Options object (e.g., "temperature", "num_ctx").
		 * Also used to match parameter names from model's parameters string.
		 */
		public string pname { get; set; default = ""; }

		/**
		 * Checks if the current value is in default/auto state (unset).
		 * 
		 * @param value The current value from the options object
		 * @return true if value is unset (default/auto), false otherwise
		 */
		protected abstract bool is_default(Value value);

		/**
		 * Sets the value widget to its default value.
		 */
		protected abstract void reset_default();

		/**
		 * Sets the default value from a Value object.
		 * 
		 * @param value The Value object containing the default value
		 */
		public abstract void set_value(Value value);

		protected Gtk.Button auto_button;
		protected Gtk.Button clear_button;
		protected Gtk.Box button_box;

		protected OptionRow()
		{
			// Create Auto button
			this.auto_button = new Gtk.Button.with_label("Auto") {
				tooltip_text = "Click to set a custom value",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.auto_button.clicked.connect(() => {
				this.set_to_default();
			});

			// Create clear button with edit-clear icon
			this.clear_button = new Gtk.Button.from_icon_name("edit-clear-symbolic") {
				tooltip_text = "Reset to Auto",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.clear_button.clicked.connect(() => {
				this.reset_to_auto();
			});

			// Create button box to hold either Auto or (value widget + clear)
			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.button_box.append(this.auto_button);
		}

		protected void set_to_default()
		{
			if (this.value_widget == null) {
				return;
			}

			// Hide Auto button, show value widget and clear button
			this.auto_button.visible = false;
			this.value_widget.visible = true;
			this.clear_button.visible = true;
			
			// Set value widget to default value
			this.reset_default();
		}

		protected void reset_to_auto()
		{
			if (this.value_widget == null) {
				return;
			}

			// Hide value widget and clear button, show Auto button
			this.value_widget.visible = false;
			this.clear_button.visible = false;
			this.auto_button.visible = true;
		}
		

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
		public double min_value { get; set; }
		public double max_value { get; set; }
		public double step_value { get; set; }
		public uint digits { get; set; }
		public double default_value { get; set; }
		public double auto_value { get; set; default = -1.0; }
		private bool default_value_set = false;

		private Gtk.SpinButton spin_button;

		public OptionFloatWidget()
		{
			// Create spin button
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 100.0, 1.0) {
				digits = 0,
				visible = false,
				width_request = 150,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};

			// Set value widget for base class
			this.value_widget = this.spin_button;

			// Add value widget and clear button to button box (base class created it)
			this.button_box.append(this.spin_button);
			this.button_box.append(this.clear_button);
			this.clear_button.visible = false;

			// Add button box to suffix
			this.add_suffix(this.button_box);
		}

		protected override bool is_default(Value value)
		{
			return value.get_double() == this.auto_value;
		}

		protected override void reset_default()
		{
			this.spin_button.value = this.default_value;
		}
		
		public override void set_value(Value value)
		{
			var double_val = value.get_double();
			// Clamp to valid range
			if (double_val < this.min_value) {
				double_val = this.min_value;
			} else if (double_val > this.max_value) {
				double_val = this.max_value;
			}
			this.default_value = double_val;
			this.default_value_set = true;
			// Format the value for display based on digits
			string formatted = "%.*f".printf((int)this.digits, double_val);
			// Always set the label
			this.auto_button.label = formatted == "" ? "Auto" : formatted;
		}
		
		public override void load_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(double));
			var property_name = this.pname.replace("_", "-");
			((GLib.Object)options).get_property(property_name, ref val);
			
			if (this.is_default(val)) {
				// Value is unset, show Auto button with default value label if set via set_value()
				if (this.default_value_set) {
					// Use the default value that was set via set_value()
					string formatted = "%.*f".printf((int)this.digits, this.default_value);
					this.auto_button.label = formatted == "" ? "Auto" : formatted;
				} else {
					this.auto_button.label = "Auto";
				}
				this.reset_to_auto();
			} else {
				// Value is set, show spin button with value
				this.set_to_default();
				this.spin_button.value = val.get_double();
			}
		}

		public override void save_options(OLLMchat.Call.Options options)
		{
			Value value = Value(typeof(double));
			if (this.auto_button.visible) {
				// Auto is selected, save auto value (unset)
				value.set_double(this.auto_value);
			} else {
				// Value is set, save the spin button value
				value.set_double(this.spin_button.value);
			}
			((GLib.Object)options).set_property(this.pname, value);
		}
	}

	/**
	 * Generic int option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionIntWidget : OptionRow
	{
		public double min_value { get; set; }
		public double max_value { get; set; }
		public double step_value { get; set; default = 1.0; }
		public uint digits { get; set; default = 0; }
		public double default_value { get; set; }
		public int auto_value { get; set; default = -1; }
		private bool default_value_set = false;

		private Gtk.SpinButton spin_button;

		public OptionIntWidget()
		{
			// Create spin button
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 100.0, 1.0) {
				digits = 0,
				visible = false,
				width_request = 150,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};

			// Set value widget for base class
			this.value_widget = this.spin_button;

			// Add value widget and clear button to button box (base class created it)
			this.button_box.append(this.spin_button);
			this.button_box.append(this.clear_button);
			this.clear_button.visible = false;

			// Add button box to suffix
			this.add_suffix(this.button_box);
		}

		protected override bool is_default(Value value)
		{
			return value.get_int() == this.auto_value;
		}

		protected override void reset_default()
		{
			this.spin_button.value = this.default_value;
		}
		
		public override void set_value(Value value)
		{
			var int_val = value.get_int();
			// Clamp to valid range
			if (int_val < (int)this.min_value) {
				int_val = (int)this.min_value;
			} else if (int_val > (int)this.max_value) {
				int_val = (int)this.max_value;
			}
			this.default_value = (double)int_val;
			this.default_value_set = true;
			string label_text = int_val.to_string();
			// Always set the label
			this.auto_button.label = label_text == "" ? "Auto" : label_text;
		}
		
		public override void load_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(int));
			var property_name = this.pname.replace("_", "-");
			((GLib.Object)options).get_property(property_name, ref val);
			
			if (this.is_default(val)) {
				// Value is unset, show Auto button with default value label if set via set_value()
				if (this.default_value_set) {
					// Use the default value that was set via set_value()
					string label_text = "%d".printf((int)this.default_value);
					this.auto_button.label = label_text == "" ? "Auto" : label_text;
				} else {
					this.auto_button.label = "Auto";
				}
				this.reset_to_auto();
			} else {
				// Value is set, show spin button with value
				this.set_to_default();
				this.spin_button.value = (double)val.get_int();
			}
		}

		public override void save_options(OLLMchat.Call.Options options)
		{
			Value value = Value(typeof(int));
			if (this.auto_button.visible) {
				// Auto is selected, save auto value (unset)
				value.set_int(this.auto_value);
			} else {
				// Value is set, save the spin button value
				value.set_int((int)this.spin_button.value);
			}
			((GLib.Object)options).set_property(this.pname, value);
		}
	}

}

