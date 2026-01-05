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
	 * Tool row widget that extends Adw.ExpanderRow.
	 * 
	 * Manages a single tool's configuration with all its property widgets.
	 * 
	 * @since 1.0
	 */
	public class Tool : Adw.ExpanderRow
	{
		/**
		 * The tool name (key in Config2.tools).
		 */
		public string tool_name { get; construct; }
		
		/**
		 * The tool config object.
		 */
		public OLLMchat.Settings.BaseToolConfig config { get; construct; }
		
		/**
		 * Reference to SettingsDialog for accessing Config2.
		 */
		public MainDialog dialog { get; construct; }
		
		private Gee.ArrayList<ModelUsage> model_usage_widgets = new Gee.ArrayList<ModelUsage>();
		private Gee.ArrayList<Row> row_widgets = new Gee.ArrayList<Row>();
		
		/**
		 * Creates a new Tool.
		 * 
		 * @param dialog SettingsDialog to access Config2
		 * @param tool The Tool.BaseTool object (can be null if Client.tools not available)
		 * @param config The BaseToolConfig object
		 * @param tool_name The tool name (used if tool is null)
		 */
		public Tool(
			MainDialog dialog,
			OLLMchat.Tool.BaseTool? tool,
			OLLMchat.Settings.BaseToolConfig config,
			string tool_name
		)
		{
			Object(
				dialog: dialog,
				tool_name: tool_name,
				config: config,
				title: config.title
			);
			
			// Introspect config properties and create widgets
			this.introspect_config_properties();
		}
		
		/**
		 * Introspects GObject properties of config object and creates widgets.
		 */
		private void introspect_config_properties()
		{
			GLib.debug("Introspecting properties for config class: %s", this.config.get_class().get_type().name());
			foreach (var pspec in this.config.get_class().list_properties()) {
				GLib.debug("Found property: %s (type: %s)", pspec.get_name(), pspec.value_type.name());
				// Skip properties that shouldn't be shown in UI
				// (e.g., internal GObject properties)
				if (pspec.get_name().has_prefix("_") || 
				    pspec.get_name() == "type" ||
				    pspec.get_name() == "type-instance") {
					continue;
				}
				
				// Create widget for this property
				var widget = this.create_property_widget(pspec);
				if (widget != null) {
					this.add_row(widget);
				}
			}
		}
		
		/**
		 * Generates UI widget for a property based on its pspec.
		 * 
		 * @param pspec The property spec
		 * @return The widget for this property, or null if property type is not supported
		 */
		private Gtk.Widget? create_property_widget(ParamSpec pspec)
		{
			switch (pspec.value_type.name()) {
				case "gboolean":
					var widget = new Bool(this.dialog, this.config, pspec);
					this.row_widgets.add(widget);
					return widget;
				
				case "gchararray":
					break;
				
				default:
					if (pspec.value_type.is_a(typeof(OLLMchat.Settings.ModelUsage))) {
						var widget = new ModelUsage(this.dialog, this.config, pspec);
						this.model_usage_widgets.add(widget);
						return widget.get_widget();
					}
					
					GLib.warning("Unsupported property type for property %s: %s", pspec.get_name(), pspec.value_type.name());
					return null;
			}
			
			// Handle string properties
			switch (pspec.get_name()) {
				case "connection":
					var widget = new Connection(this.dialog, this.config, pspec);
					this.row_widgets.add(widget);
					return widget;
				
				case "model":
					var widget = new Model(this.dialog, this.config, pspec);
					this.row_widgets.add(widget);
					return widget;
				
				default:
					var widget = new String(this.dialog, this.config, pspec);
					this.row_widgets.add(widget);
					return widget;
			}
		}
		
		/**
		 * Loads all configuration values into widgets.
		 * 
		 * Called when the settings dialog is shown to populate widgets with current config values.
		 */
		public void load_config()
		{
			// Load configs for all Row widgets
			foreach (var row_widget in this.row_widgets) {
				row_widget.load_config(row_widget.config);
			}
			
			// Load configs for all ModelUsage widgets
			foreach (var model_usage_widget in this.model_usage_widgets) {
				// Get ModelUsage object from config
				Value val = Value(model_usage_widget.pspec.value_type);
				model_usage_widget.config.get_property(model_usage_widget.pspec.get_name(), ref val);
				var model_usage = val.get_object() as OLLMchat.Settings.ModelUsage;
				model_usage_widget.load_config(model_usage);
			}
		}
	}
}

