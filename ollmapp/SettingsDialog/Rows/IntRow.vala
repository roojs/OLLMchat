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
	 * Generic int option widget that extends Row.
	 * 
	 * @since 1.0
	 */
	public class Int : Row
	{
		public double min_value { get; set; }
		public double max_value { get; set; }
		public double step_value { get; set; default = 1.0; }
		public uint digits { get; set; default = 0; }
		public double default_value { get; set; }  // Hardcoded default (never changes)
		public int model_value { get; set; default = -1; }   // Model's default value (set via set_model_value(), defaults to unset_value if not set)
		public int unset_value { get; set; default = -1; }
		public bool display_in_k { get; set; default = false; }  // Display values in K format (e.g., 64K instead of 65536)

		private Gtk.SpinButton spin_button;

		public Int(MainDialog dialog, Object config, ParamSpec pspec)
		{
			base(dialog, config, pspec);
		}

		protected override void setup_widget()
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

			// Setup Auto/clear buttons
			this.setup_auto_clear_buttons();

			// Add value widget and clear button to button box
			this.button_box.append(this.spin_button);
			this.button_box.append(this.clear_button);
			this.clear_button.visible = false;

			// Add button box to suffix
			this.add_suffix(this.button_box);
			
			// Always connect output/input signal handlers for K formatting (methods check display_in_k)
			this.spin_button.output.connect(this.on_output);
			this.spin_button.input.connect((spin, out new_value) => {
				return this.on_input(out new_value);
			});
			
			// If bound to a property, set up signal handler to update it
			
			this.spin_button.value_changed.connect(() => {
				if (this.loading_config) {
					return;
				}
				if (!this.auto_button.visible) {
					Value new_val = Value(pspec.value_type);
					new_val.set_int((int)this.spin_button.value);
					this.config.set_property(this.pspec.get_name(), new_val);
				}
			});
			this.auto_button.clicked.connect(() => {
				if (this.loading_config) {
					return;
				}
				Value new_val = Value(pspec.value_type);
				new_val.set_int(this.unset_value);
				this.config.set_property(this.pspec.get_name(), new_val);
			});
		
		}

		/**
		 * Output signal handler: formats value in K format if display_in_k is enabled.
		 * 
		 * @return true if value was formatted, false otherwise
		 */
		private bool on_output()
		{
			if (!this.display_in_k) {
				return false;
			}
			
			// Format output: convert tokens to K (e.g., 65536 -> "64K")
		
			this.spin_button.numeric = false;
			this.spin_button.text = "%dK".printf(
				this.spin_button.get_value_as_int() / 1024)
			;
			this.spin_button.numeric = true;
			return true;
		}
		
		/**
		 * Input signal handler: parses K format back to tokens if display_in_k is enabled.
		 * 
		 * @param new_value The out double parameter to set with the parsed token count
		 * @return 1 if value was parsed (handled), 0 otherwise
		 */
		private int on_input(out double new_value)
		{
			if (!this.display_in_k) {
				// Return 0 (not handled) - GTK will use default integer parsing
				// new_value is set to satisfy out parameter, but GTK ignores it when we return 0
				new_value = 0.0;
				return 0;
			}
			
			// Parse input: convert K to tokens (e.g., "64K" -> 65536)
			var text = this.spin_button.text.strip().up();
			
			// Remove trailing 'K' if present
			if (text.has_suffix("K")) {
				text = text.substring(0, text.length - 1);
			}
			
			// Parse as integer
			int k_value;
			if (!int.try_parse(text, out k_value)) {
				new_value = 0.0;
				return 0;
			}
			
			// Convert K to tokens and clamp to valid range
			if (k_value * 1024 < (int)this.min_value) {
				new_value = this.min_value;
				return 1;
			}
			if (k_value * 1024 > (int)this.max_value) {
				new_value = this.max_value;
				return 1;
			}
			new_value = (double)k_value * 1024;
			return 1;
		}

		protected override bool is_default(Value value)
		{
			return value.get_int() == this.unset_value;
		}

		protected override void set_start_value()
		{
			if (this.model_value != this.unset_value) {
				this.spin_button.value = (double)this.model_value;
				return;
			} 
			this.spin_button.value = this.default_value;
			
		}
		
		public override void set_model_value(Value value)
		{
			var int_val = value.get_int();
			// Clamp to valid range
			if (int_val < (int)this.min_value) {
				int_val = (int)this.min_value;
			}
			if (int_val > (int)this.max_value) {
				int_val = (int)this.max_value;
			}
			// Set model_value to model's default (used when user clicks Auto button)
			this.model_value = int_val;
			
			// Format label text
			if (this.display_in_k) {
				this.auto_button.label = "%dK".printf(int_val / 1024);
				return;
			}
			var label_text = int_val.to_string();
			this.auto_button.label = label_text == "" ? "Auto" : label_text;
		}
		
		public override void load_options(OLLMchat.Call.Options options)
		{
			this.loading_config = true;
			// Reset model_value - it will be set by set_model_value() if the model has a default
			this.model_value = this.unset_value;
			
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(int));
			((GLib.Object)options).get_property(this.pspec.get_name(), ref val);
			
			if (this.is_default(val)) {
				// Scenario 1: new_value is unset (default/empty)
				this.auto_button.label = "Auto";
				this.set_to_auto();
				this.loading_config = false;
				return;
			}
			
			// Scenario 2: new_value is set (user has explicitly set a value)
			this.set_to_default();
			this.spin_button.value = (double)val.get_int();
			this.loading_config = false;
		}

		public override void apply_property(Object obj)
		{
			Value value = Value(typeof(int));
			value.set_int(this.auto_button.visible ? this.unset_value : (int)this.spin_button.value);
			obj.set_property(this.pspec.get_name(), value);
		}
	}
}

