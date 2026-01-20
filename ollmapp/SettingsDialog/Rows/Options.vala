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

namespace OLLMapp.SettingsDialog.Rows
{
	/**
	 * Widget that contains all option rows for model configuration.
	 * 
	 * Can be used in two modes:
	 * 1. Standalone mode (for ModelRow) - creates rows for direct attachment
	 * 2. Property binding mode (for ToolsPage) - returns container with rows
	 * 
	 * @since 1.0
	 */
	public class Options : GLib.Object
	{

		/**
		 * List of all option rows managed by this widget.
		 */
		public Gee.ArrayList<Row> rows = new Gee.ArrayList<Row>();
		
		/**
		 * Property spec (for property binding mode).
		 */
		public ParamSpec? pspec { get; private set; }
		
		/**
		 * Config object (for property binding mode).
		 */
		public Object? config { get; private set; }

		/**
		 * Constructor.
		 * 
		 * @param dialog The settings dialog
		 * @param pspec The property spec for the Call.Options property
		 * @param config The config object that contains this property
		 */
		public Options(MainDialog dialog, ParamSpec pspec, Object config)
		{
			this.pspec = pspec;
			this.config = config;
			
			// Get Options object from config
			Value val = Value(pspec.value_type);
			config.get_property(pspec.get_name(), ref val);
			var options = val.get_object() as OLLMchat.Call.Options;
			
			
			this.init_rows(dialog, options);
		}

		/**
		 * Initializes the option rows.
		 * 
		 * @param dialog The settings dialog
		 * @param options The Options object to bind rows to
		 */
		private void init_rows(MainDialog dialog, OLLMchat.Call.Options options)
		{
			unowned var options_class = options.get_class();
			
			this.rows.add(new Float(dialog, options, options_class.find_property("temperature")) {
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.8
			});

			this.rows.add(new Float(dialog, options, options_class.find_property("top_p")) {
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.9
			});

			this.rows.add(new Int(dialog, options, options_class.find_property("top_k")) {
				min_value = 1.0,
				max_value = 1000.0,
				step_value = 1.0,
				digits = 0,
				default_value = 40.0
			});

			this.rows.add(new Int(dialog, options, options_class.find_property("num_ctx")) {
				min_value = 1.0,
				max_value = 1000000.0,
				step_value = 1024.0,
				digits = 0,
				default_value = 16384.0,
				display_in_k = true
			});

			this.rows.add(new Float(dialog, options, options_class.find_property("min_p")) {
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.1
			});

			this.rows.add(new Float(dialog, options, options_class.find_property("typical_p")) {
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 1.0
			});

			this.rows.add(new Int(dialog, options, options_class.find_property("repeat_last_n")) {
				min_value = 0.0,
				max_value = 65536.0,
				step_value = 1.0,
				digits = 0,
				default_value = 64.0
			});

			this.rows.add(new Float(dialog, options, options_class.find_property("repeat_penalty")) {
				min_value = 1.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 1.1
			});

			this.rows.add(new Float(dialog, options, options_class.find_property("presence_penalty")) {
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.0
			});

			this.rows.add(new Float(dialog, options, options_class.find_property("frequency_penalty")) {
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.0
			});

			this.rows.add(new Int(dialog, options, options_class.find_property("seed")) {
				min_value = -1.0,
				max_value = 2147483647.0,
				step_value = 1.0,
				digits = 0,
				default_value = -1.0
			});
		}

		/**
		 * Loads the options from the provided Options object.
		 * Called by the settings page after creating the widget.
		 * 
		 * @param options The Options object to load values from
		 */
		public void load_config(OLLMchat.Call.Options options)
		{
			foreach (var row in this.rows) {
				row.load_options(options);
			}
		}
		
		/**
		 * Gets a container widget with all option rows for property binding mode.
		 * 
		 * @return A Box containing all option rows
		 */
		public Gtk.Widget get_container()
		{
			var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			foreach (var row in this.rows) {
				container.append(row);
			}
			return container;
		}

		public void save_options(OLLMchat.Call.Options options)
		{
			foreach (var row in this.rows) {
				row.apply_property(options);
			}
		}
	}

}

