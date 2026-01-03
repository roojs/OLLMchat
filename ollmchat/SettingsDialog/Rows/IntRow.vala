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

namespace OLLMchat.SettingsDialog.Rows
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

		private Gtk.SpinButton spin_button;

		public Int(ParamSpec pspec, Object config)
		{
			base(pspec, config);
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
			} else if (int_val > (int)this.max_value) {
				int_val = (int)this.max_value;
			}
			// Set model_value to model's default (used when user clicks Auto button)
			this.model_value = int_val;
			string label_text = int_val.to_string();
			// Update Auto button label to show model's default value
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
			} else {
				// Scenario 2: new_value is set (user has explicitly set a value)
				this.set_to_default();
				this.spin_button.value = (double)val.get_int();
			}
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

