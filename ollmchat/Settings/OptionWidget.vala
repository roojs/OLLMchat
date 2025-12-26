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
		public double min_value { get; construct; }
		public double max_value { get; construct; }
		public double step_value { get; construct; }
		public uint digits { get; construct; }
		public double default_value { get; construct; }
		public double unset_value { get; construct; }

		public delegate double GetValueFunc(OLLMchat.Call.Options options);
		public delegate void SetValueFunc(OLLMchat.Call.Options options, double value);

		public GetValueFunc get_value_func { get; set; }
		public SetValueFunc set_value_func { get; set; }

		private Gtk.SpinButton spin_button;

		construct
		{
			this.spin_button = new Gtk.SpinButton.with_range(this.min_value, this.max_value, this.step_value) {
				digits = this.digits
			};
			this.add_suffix(this.spin_button);
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			var val = this.get_value_func(options);
			this.spin_button.value = val != this.unset_value ? val : this.default_value;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = this.spin_button.value;
			if (val == this.default_value && this.get_value_func(options) == this.unset_value) {
				return; // No change
			}
			this.set_value_func(options, val);
		}
	}

	/**
	 * Generic int option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionIntWidget : OptionWidget
	{
		public double min_value { get; construct; }
		public double max_value { get; construct; }
		public double step_value { get; construct; }
		public uint digits { get; construct; }
		public double default_value { get; construct; }
		public int unset_value { get; construct; }

		public int get_value(OLLMchat.Call.Options options) { get; set; }
		public void set_value(OLLMchat.Call.Options options, int value) { get; set; }

		private Gtk.SpinButton spin_button;

		construct
		{
			this.spin_button = new Gtk.SpinButton.with_range(this.min_value, this.max_value, this.step_value) {
				digits = this.digits
			};
			this.add_suffix(this.spin_button);
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			var val = this.get_value(options);
			this.spin_button.value = val != this.unset_value ? (double)val : this.default_value;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = (int)this.spin_button.value;
			if (val == (int)this.default_value && this.get_value(options) == this.unset_value) {
				return; // No change
			}
			this.set_value(options, val);
		}
	}

	/**
	 * Generic string option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionStringWidget : OptionWidget
	{
		public string placeholder_text { get; construct; }

		public string get_value(OLLMchat.Call.Options options) { get; set; }
		public void set_value(OLLMchat.Call.Options options, string value) { get; set; }

		private Gtk.Entry entry;

		construct
		{
			this.entry = new Gtk.Entry() {
				placeholder_text = this.placeholder_text
			};
			this.add_suffix(this.entry);
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.entry.text = this.get_value(options);
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			this.set_value(options, this.entry.text);
		}
	}
}
