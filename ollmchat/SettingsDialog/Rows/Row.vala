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
	 * Base class for all config widget classes.
	 * 
	 * Extends Adw.ActionRow and provides common functionality for property binding,
	 * getting nick/blurb from pspec, and common widget setup.
	 * 
	 * Also provides Auto/clear button functionality for option rows that support auto mode.
	 * 
	 * @since 1.0
	 */
	public abstract class Row : Adw.ActionRow
	{
		/**
		 * The settings dialog (for accessing config, etc.)
		 */
		public MainDialog dialog { get; construct; }
		
		/**
		 * The property spec for this widget.
		 */
		public ParamSpec pspec { get; construct; }
		
		/**
		 * The config object that contains this property.
		 * 
		 * Can be BaseToolConfig or any Object with GObject properties.
		 */
		public Object config { get; construct; }
		
		/**
		 * The value widget (SpinButton, Entry, etc.) that should be shown/hidden.
		 * Used by option rows with Auto/clear functionality.
		 */
		protected Gtk.Widget? value_widget { get; set; }
		
		
		/**
		 * Flag to prevent signal handlers from firing during programmatic updates.
		 * Set to true before programmatically setting widget values, false after.
		 */
		public bool loading_config = false;
		
		/**
		 * Auto/clear button widgets (used by option rows).
		 */
		protected Gtk.Button auto_button;
		protected Gtk.Button clear_button;
		protected Gtk.Box button_box;
		
		/**
		 * Creates a new Row.
		 * 
		 * @param dialog The settings dialog
		 * @param config The config object that contains this property (BaseToolConfig or Object with GObject properties)
		 * @param pspec The property spec for the property this widget represents
		 */
		protected Row(MainDialog dialog, Object config, ParamSpec pspec)
		{
			Object(dialog: dialog, pspec: pspec, config: config);
			this.title = this.pspec.get_nick();
			this.subtitle = this.pspec.get_blurb();
			this.setup_widget();
		}
		
		/**
		 * Sets up the widget after construction.
		 * 
		 * Must be implemented by subclasses to configure the row structure
		 * (create UI elements, bind signals). Does NOT load values from config.
		 */
		protected abstract void setup_widget();
		
		/**
		 * Loads the widget's value from the config object.
		 * 
		 * Called by the settings page after creating the widget to load initial values.
		 * Default implementation does nothing - subclasses should override if needed.
		 * 
		 * @param config The config object to load the value from
		 */
		public virtual void load_config(Object config)
		{
			// Default implementation does nothing
		}
		
		
		/**
		 * Sets up Auto/clear button functionality for option rows.
		 * 
		 * Call this in setup_widget() for option rows that need Auto/clear functionality.
		 */
		protected void setup_auto_clear_buttons()
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
				this.set_to_auto();
			});

			// Create button box to hold either Auto or (value widget + clear)
			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.button_box.append(this.auto_button);
		}
		
		/**
		 * Shows the value widget (hides Auto button) and sets it to starting value.
		 * 
		 * Used by option rows with Auto/clear functionality.
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
			
			// Set value widget to starting value
			this.set_start_value();
		}

		/**
		 * Hides value widget and clear button, shows Auto button.
		 * 
		 * Used by option rows with Auto/clear functionality.
		 */
		protected void set_to_auto()
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
		 * Sets the value widget to its starting value when user begins editing.
		 * Uses model_value if set, otherwise uses hardcoded default_value.
		 * 
		 * Must be implemented by option rows that use Auto/clear functionality.
		 */
		protected virtual void set_start_value()
		{
			// Default implementation does nothing
		}
		
		/**
		 * Checks if the current value is in default/auto state (unset).
		 * 
		 * Must be implemented by option rows that use Auto/clear functionality.
		 * 
		 * @param value The current value from the options object
		 * @return true if value is unset (default/auto), false otherwise
		 */
		protected virtual bool is_default(Value value)
		{
			return false;
		}

		/**
		 * Sets the model's default value from a Value object.
		 * 
		 * Must be implemented by option rows that use Auto/clear functionality.
		 * 
		 * @param value The Value object containing the model's default value
		 */
		public virtual void set_model_value(Value value)
		{
			// Default implementation does nothing
		}

		/**
		 * Loads the widget's value from the options object.
		 * 
		 * Must be implemented by option rows.
		 * 
		 * @param options Options object to read value from
		 */
		public virtual void load_options(OLLMchat.Call.Options options)
		{
			// Default implementation does nothing
		}

		/**
		 * Applies the widget's current value to the given object's property.
		 * 
		 * For option rows, this applies the value to an Options object.
		 * For regular config widgets, this applies the value to the config object.
		 * 
		 * @param obj The object to apply the property value to
		 */
		public virtual void apply_property(Object obj)
		{
			// Default implementation does nothing
		}
	}
}

