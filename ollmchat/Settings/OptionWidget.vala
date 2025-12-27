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

		/**
		 * Shows the value widget (hides Auto button) and sets it to default value.
		 * 
		 * This is called when:
		 * - User clicks "Auto" button to set a custom value (scenario 3)
		 *   In this case, reset_default() is correct - we want to show default_value
		 * 
		 * NOTE: This is also incorrectly called from load_options() when loading a saved value.
		 * In that case, we should NOT use reset_default() because we want to show the saved value,
		 * not the default_value. The current code works because it overwrites the value immediately
		 * after, but it's inefficient and confusing.
		 */
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
			// WRONG when called from load_options() with a saved value - should use saved value instead
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
		public double unset_value { get; set; default = -1.0; }

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
			// Check if value is the "empty/unset" value (unset_value, e.g., -1.0)
			// This represents the default/empty state that never changes
			// Returns true if the value from Options equals unset_value (meaning it's unset)
			return value.get_double() == this.unset_value;
		}

		/**
		 * Sets the spin button to the default value.
		 * 
		 * This is called when user clicks "Auto" button to start setting a custom value.
		 * The default_value may be:
		 * - The hardcoded default from widget constructor (e.g., 0.7 for temperature)
		 * - The model's default value if set via set_value() from model.options
		 * 
		 * DISPLAY LOGIC SCENARIOS:
		 * 
		 * new_value = the value stored in Options object (user's saved setting, read via options.get_property())
		 * 
		 * 1. new_value in Options is unset (new_value == unset_value, e.g., -1.0):
		 *    - If set_value() was called (model has default): Show Auto button with model's default as label
		 *    - If set_value() was NOT called: Show Auto button with "Auto" label
		 *    - Display: Auto button visible, spin button hidden
		 * 
		 * 2. new_value in Options is set (user has explicitly set a value, new_value != unset_value):
		 *    - Display: Spin button visible with the actual saved new_value from Options
		 *    - The value shown MUST be the new_value from Options, NOT default_value
		 *    - Auto button hidden
		 * 
		 * 3. User clicks "Auto" button to set a custom value:
		 *    - Display: Show spin button with default_value as starting value
		 *    - default_value may be model's default (if set via set_value()) or hardcoded default
		 *    - This is the ONLY scenario where reset_default() should set the spin button value
		 * 
		 * 4. User clicks clear button to reset to Auto:
		 *    - Display: Show Auto button (with model default label if available), hide spin button
		 * 
		 * NOTE: In load_options() when new_value is set, we call set_to_default() which calls
		 * reset_default(), but then immediately overwrite with the actual saved new_value.
		 * This is inefficient - reset_default() should NOT be called in that scenario.
		 */
		protected override void reset_default()
		{
			// WRONG: This is only correct for scenario 3 (user clicking Auto button)
			// When loading a saved value (scenario 2), we should NOT use default_value,
			// we should use the actual saved value from Options
			this.spin_button.value = this.default_value;
		}
		
		/**
		 * Sets the model's default value (only called by model, not user).
		 * 
		 * This updates default_value and the Auto button label to show the model's default.
		 * This does NOT change the actual saved value in Options - it only affects:
		 * - What label is shown on Auto button when value is unset
		 * - What value appears in spin button when user clicks "Auto" to set custom value
		 */
		public override void set_value(Value value)
		{
			var double_val = value.get_double();
			// Clamp to valid range
			if (double_val < this.min_value) {
				double_val = this.min_value;
			} else if (double_val > this.max_value) {
				double_val = this.max_value;
			}
			// Update default_value to model's default (used when user clicks Auto button)
			this.default_value = double_val;
			// Format the value for display based on digits
			string formatted = "%.*f".printf((int)this.digits, double_val);
			// Update Auto button label to show model's default value
			this.auto_button.label = formatted == "" ? "Auto" : formatted;
		}
		
		/**
		 * Loads the widget's value from the options object.
		 * 
		 * new_value = the value stored in Options object (user's saved setting, read via options.get_property())
		 * 
		 * DISPLAY LOGIC:
		 * - If new_value in Options is unset (new_value == unset_value): Show Auto button (with model default label if set_value() was called)
		 * - If new_value in Options is set (new_value != unset_value): Show spin button with the actual saved new_value from Options (NOT default_value)
		 */
		public override void load_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(double));
			var property_name = this.pname.replace("_", "-");
			((GLib.Object)options).get_property(property_name, ref val);
			
			if (this.is_default(val)) {
				// Scenario 1: new_value is unset (default/empty)
				// WRONG: This always sets label to "Auto", but should check if set_value() was called
				// to show model's default value in the label (like OptionIntWidget does)
				this.auto_button.label = "Auto";
				
				this.reset_to_auto();
				return;
			}
			// Scenario 2: Value is set (user has explicitly set a value)
			// WRONG: set_to_default() calls reset_default() which sets spin button to default_value,
			// but we immediately overwrite it with the actual saved value. This is inefficient.
			// We should directly set the spin button to val.get_double() without calling reset_default()
			this.set_to_default();
			this.spin_button.value = val.get_double();
			
		}

		public override void save_options(OLLMchat.Call.Options options)
		{
			Value value = Value(typeof(double));
			if (this.auto_button.visible) {
				// Auto is selected, save unset_value (unset)
				value.set_double(this.unset_value);
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
		public int unset_value { get; set; default = -1; }
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
			// Check if value is the "empty/unset" value (unset_value, e.g., -1)
			// This represents the default/empty state that never changes
			// Returns true if the value from Options equals unset_value (meaning it's unset)
			return value.get_int() == this.unset_value;
		}

		/**
		 * Sets the spin button to the default value.
		 * 
		 * This is called when user clicks "Auto" button to start setting a custom value.
		 * The default_value may be:
		 * - The hardcoded default from widget constructor (e.g., 40 for top_k)
		 * - The model's default value if set via set_value() from model.options
		 * 
		 * DISPLAY LOGIC SCENARIOS:
		 * 
		 * new_value = the value stored in Options object (user's saved setting, read via options.get_property())
		 * 
		 * 1. new_value in Options is unset (new_value == unset_value, e.g., -1):
		 *    - If set_value() was called (model has default): Show Auto button with model's default as label
		 *    - If set_value() was NOT called: Show Auto button with "Auto" label
		 *    - Display: Auto button visible, spin button hidden
		 * 
		 * 2. new_value in Options is set (user has explicitly set a value, new_value != unset_value):
		 *    - Display: Spin button visible with the actual saved new_value from Options
		 *    - The value shown MUST be the new_value from Options, NOT default_value
		 *    - Auto button hidden
		 * 
		 * 3. User clicks "Auto" button to set a custom value:
		 *    - Display: Show spin button with default_value as starting value
		 *    - If set_value() was called (model has default): Show model's default value
		 *    - If set_value() was NOT called: Show hardcoded default value
		 *    - This is the ONLY scenario where reset_default() should set the spin button value
		 * 
		 * 4. User clicks clear button to reset to Auto:
		 *    - Display: Show Auto button (with model default label if available), hide spin button
		 * 
		 * NOTE: In load_options() when new_value is set, we call set_to_default() which calls
		 * reset_default(), but then immediately overwrite with the actual saved new_value.
		 * This is inefficient - reset_default() should NOT be called in that scenario.
		 */
		protected override void reset_default()
		{
			// WRONG: This is only correct for scenario 3 (user clicking Auto button)
			// When loading a saved new_value (scenario 2), we should NOT use default_value,
			// we should use the actual saved new_value from Options
			this.spin_button.value = this.default_value;
		}
		
		/**
		 * Sets the model's default value (only called by model, not user).
		 * 
		 * This updates default_value and the Auto button label to show the model's default.
		 * This does NOT change the actual saved value in Options - it only affects:
		 * - What label is shown on Auto button when value is unset
		 * - What value appears in spin button when user clicks "Auto" to set custom value
		 */
		public override void set_value(Value value)
		{
			var int_val = value.get_int();
			// Clamp to valid range
			if (int_val < (int)this.min_value) {
				int_val = (int)this.min_value;
			} else if (int_val > (int)this.max_value) {
				int_val = (int)this.max_value;
			}
			// Update default_value to model's default (used when user clicks Auto button)
			this.default_value = (double)int_val;
			this.default_value_set = true;
			string label_text = int_val.to_string();
			// Update Auto button label to show model's default value
			this.auto_button.label = label_text == "" ? "Auto" : label_text;
		}
		
		/**
		 * Loads the widget's value from the options object.
		 * 
		 * new_value = the value stored in Options object (user's saved setting, read via options.get_property())
		 * 
		 * DISPLAY LOGIC:
		 * - If new_value in Options is unset (new_value == unset_value): Show Auto button (with model default label if set_value() was called)
		 * - If new_value in Options is set (new_value != unset_value): Show spin button with the actual saved new_value from Options (NOT default_value)
		 */
		public override void load_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(int));
			var property_name = this.pname.replace("_", "-");
			((GLib.Object)options).get_property(property_name, ref val);
			
			if (this.is_default(val)) {
				// Scenario 1: new_value is unset (default/empty)
				// CORRECT: Check if set_value() was called to show model's default value in label
				if (this.default_value_set) {
					// Use the default value that was set via set_value()
					string label_text = "%d".printf((int)this.default_value);
					this.auto_button.label = label_text == "" ? "Auto" : label_text;
				} else {
					this.auto_button.label = "Auto";
				}
				this.reset_to_auto();
			} else {
				// Scenario 2: new_value is set (user has explicitly set a value)
				// WRONG: set_to_default() calls reset_default() which sets spin button to default_value,
				// but we immediately overwrite it with the actual saved new_value. This is inefficient.
				// We should directly set the spin button to val.get_int() without calling reset_default()
				this.set_to_default();
				this.spin_button.value = (double)val.get_int();
			}
		}

		public override void save_options(OLLMchat.Call.Options options)
		{
			Value value = Value(typeof(int));
			if (this.auto_button.visible) {
				// Auto is selected, save unset_value (unset)
				value.set_int(this.unset_value);
			} else {
				// Value is set, save the spin button value
				value.set_int((int)this.spin_button.value);
			}
			((GLib.Object)options).set_property(this.pname, value);
		}
	}

}

