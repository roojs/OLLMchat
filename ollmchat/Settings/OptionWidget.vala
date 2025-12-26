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
		private Gtk.SpinButton spin_button;
		private double default_value;
		private double unset_value;
		private unowned double get_value(OLLMchat.Call.Options options);
		private unowned void set_value(OLLMchat.Call.Options options, double value);

		/**
		 * Creates a new OptionFloatWidget.
		 * 
		 * @param title Row title
		 * @param subtitle Row subtitle
		 * @param min Minimum value
		 * @param max Maximum value
		 * @param step Step increment
		 * @param digits Number of decimal digits
		 * @param default_value Default value to use when unset
		 * @param unset_value Value that indicates unset (-1.0 typically)
		 * @param get_value Callback to get value from Options
		 * @param set_value Callback to set value in Options
		 */
		public OptionFloatWidget(
			string title,
			string subtitle,
			double min,
			double max,
			double step,
			uint digits,
			double default_value,
			double unset_value,
			owned double get_value(OLLMchat.Call.Options options),
			owned void set_value(OLLMchat.Call.Options options, double value)
		)
		{
			this.title = title;
			this.subtitle = subtitle;
			this.default_value = default_value;
			this.unset_value = unset_value;
			this.get_value = (owned)get_value;
			this.set_value = (owned)set_value;

			this.spin_button = new Gtk.SpinButton.with_range(min, max, step) {
				digits = digits
			};
			this.add_suffix(this.spin_button);
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			var val = this.get_value(options);
			this.spin_button.value = val != this.unset_value ? val : this.default_value;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = this.spin_button.value;
			if (val == this.default_value && this.get_value(options) == this.unset_value) {
				return; // No change
			}
			this.set_value(options, val);
		}
	}

	/**
	 * Generic int option widget that extends Adw.ActionRow.
	 * 
	 * @since 1.0
	 */
	public class OptionIntWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private double default_value;
		private int unset_value;
		private unowned int get_value(OLLMchat.Call.Options options);
		private unowned void set_value(OLLMchat.Call.Options options, int value);

		/**
		 * Creates a new OptionIntWidget.
		 * 
		 * @param title Row title
		 * @param subtitle Row subtitle
		 * @param min Minimum value
		 * @param max Maximum value
		 * @param step Step increment
		 * @param digits Number of decimal digits (0 for integers)
		 * @param default_value Default value to use when unset
		 * @param unset_value Value that indicates unset (-1 typically)
		 * @param get_value Callback to get value from Options
		 * @param set_value Callback to set value in Options
		 */
		public OptionIntWidget(
			string title,
			string subtitle,
			double min,
			double max,
			double step,
			uint digits,
			double default_value,
			int unset_value,
			owned int get_value(OLLMchat.Call.Options options),
			owned void set_value(OLLMchat.Call.Options options, int value)
		)
		{
			this.title = title;
			this.subtitle = subtitle;
			this.default_value = default_value;
			this.unset_value = unset_value;
			this.get_value = (owned)get_value;
			this.set_value = (owned)set_value;

			this.spin_button = new Gtk.SpinButton.with_range(min, max, step) {
				digits = digits
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
		private Gtk.Entry entry;
		private unowned string get_value(OLLMchat.Call.Options options);
		private unowned void set_value(OLLMchat.Call.Options options, string value);

		/**
		 * Creates a new OptionStringWidget.
		 * 
		 * @param title Row title
		 * @param subtitle Row subtitle
		 * @param placeholder Placeholder text for entry
		 * @param get_value Callback to get value from Options
		 * @param set_value Callback to set value in Options
		 */
		public OptionStringWidget(
			string title,
			string subtitle,
			string placeholder,
			owned string get_value(OLLMchat.Call.Options options),
			owned void set_value(OLLMchat.Call.Options options, string value)
		)
		{
			this.title = title;
			this.subtitle = subtitle;
			this.get_value = (owned)get_value;
			this.set_value = (owned)set_value;

			this.entry = new Gtk.Entry() {
				placeholder_text = placeholder
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
