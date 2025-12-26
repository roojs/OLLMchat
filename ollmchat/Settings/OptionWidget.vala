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
	 * Base class for option widgets that can update their values from Options objects.
	 * 
	 * @since 1.0
	 */
	public abstract class OptionWidget : Adw.ActionRow
	{
		/**
		 * Updates the widget's value from the options object.
		 * 
		 * @param options Options object to read value from
		 */
		public abstract void update_from_options(OLLMchat.Call.Options options);

		/**
		 * Updates the options object from the widget's current value.
		 * 
		 * @param options Options object to update
		 */
		public abstract void update_to_options(OLLMchat.Call.Options options);
	}

	/**
	 * Generic float option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionFloatWidget : OptionWidget
	{
		public string property_name { get; set; }
		public double min_value { get; set; }
		public double max_value { get; set; }
		public double step_value { get; set; }
		public uint digits { get; set; }
		public double default_value { get; set; }
		public double unset_value { get; set; }

		private Gtk.SpinButton spin_button;

		construct
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 100.0, 1.0) {
				digits = 0
			};
			this.add_suffix(this.spin_button);
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(double));
			options.get_property(this.property_name, ref val);
			var double_val = val.get_double();
			this.spin_button.value = double_val != this.unset_value ? double_val : this.default_value;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
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
	public class OptionIntWidget : OptionWidget
	{
		public string property_name { get; set; }
		public double min_value { get; set; }
		public double max_value { get; set; }
		public double step_value { get; set; }
		public uint digits { get; set; }
		public double default_value { get; set; }
		public int unset_value { get; set; }

		private Gtk.SpinButton spin_button;

		construct
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 100.0, 1.0) {
				digits = 0
			};
			this.add_suffix(this.spin_button);
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.set_range(this.min_value, this.max_value);
			this.spin_button.set_increments(this.step_value, this.step_value * 10);
			this.spin_button.digits = this.digits;

			Value val = Value(typeof(int));
			options.get_property(this.property_name, ref val);
			var int_val = val.get_int();
			this.spin_button.value = int_val != this.unset_value ? (double)int_val : this.default_value;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
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
	public class OptionStringWidget : OptionWidget
	{
		public string placeholder_text { get; set; }

		public signal string get_value(OLLMchat.Call.Options options);
		public signal void set_value(OLLMchat.Call.Options options, string value);

		private Gtk.Entry entry;
		private bool configured = false;

		construct
		{
			this.entry = new Gtk.Entry() {
				placeholder_text = this.placeholder_text
			};
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			if (!this.configured) {
				this.add_suffix(this.entry);
				this.configured = true;
			}
			this.entry.text = this.get_value(options);
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			this.set_value(options, this.entry.text);
		}
	}
}
