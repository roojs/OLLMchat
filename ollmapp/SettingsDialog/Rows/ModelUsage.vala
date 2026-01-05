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
	 * Widget class for ModelUsage properties.
	 * 
	 * Returns an Adw.ExpanderRow (since ExpanderRow is sealed, we can't extend it).
	 * Creates a ModelUsage editor with connection dropdown, model dropdown, and options widget.
	 * 
	 * @since 1.0
	 */
	public class ModelUsage : GLib.Object
	{
		public MainDialog dialog { get; construct; }
		public ParamSpec pspec { get; construct; }
		public Object config { get; construct; }
		private OLLMchat.Settings.ModelUsage model_usage;
		private Adw.ExpanderRow expander_row;
		private Connection connection_widget;
		private Model model_widget;
		private Options options_widget;
		
		/**
		 * Creates a new ModelUsage widget.
		 * 
		 * @param dialog SettingsDialog to access Config2
		 * @param config The config object that contains this property
		 * @param pspec The property spec for the ModelUsage property
		 */
		public ModelUsage(MainDialog dialog, Object config, ParamSpec pspec)
		{
			Object(dialog: dialog, pspec: pspec, config: config);
			this.setup_widget();
		}
		
		/**
		 * Gets the ExpanderRow widget.
		 * 
		 * @return The ExpanderRow containing all ModelUsage configuration widgets
		 */
		public Adw.ExpanderRow get_widget()
		{
			return this.expander_row;
		}
		
		private void setup_widget()
		{
			// Get current ModelUsage value
			Value val = Value(pspec.value_type);
			this.config.get_property(this.pspec.get_name(), ref val);
			this.model_usage = val.get_object() as OLLMchat.Settings.ModelUsage;
			
			// Create expander row
			this.expander_row = new Adw.ExpanderRow() {
				title = this.pspec.get_nick()
			};
			this.expander_row.subtitle = this.pspec.get_blurb();
			
			// Create widgets for nested properties: connection, model, options
			var connection_pspec = this.model_usage.get_class().find_property("connection");
			this.connection_widget = new Connection(this.dialog, this.model_usage, connection_pspec);
			this.expander_row.add_row(this.connection_widget);
			
			// Create model dropdown
			var model_pspec = this.model_usage.get_class().find_property("model");
			this.model_widget = new Model(this.dialog, this.model_usage, model_pspec);
			this.expander_row.add_row(this.model_widget);
			
			// Monitor connection widget dropdown selection changes and update model widget
			this.connection_widget.dropdown.notify["selected"].connect(() => {
				if (this.connection_widget.loading_config) {
					return;
				}
				Value val2 = Value(model_pspec.value_type);
				((GLib.Object)this.model_usage).get_property(model_pspec.get_name(), ref val2);
				this.model_widget.load_models.begin(this.model_usage.connection, val2.get_string());
			});
			
			// Create options widget
			var options_pspec = this.model_usage.get_class().find_property("options");
			this.options_widget = new Options(this.dialog, options_pspec, this.model_usage);
			// Options returns a container, so we need to add each row individually
			foreach (var row in this.options_widget.rows) {
				this.expander_row.add_row(row);
			}
		}
		
		public void load_config(OLLMchat.Settings.ModelUsage model_usage)
		{
			this.model_usage = model_usage;
			this.connection_widget.load_config(model_usage);
			
			// Load models from connection (async) - this also sets the selected model
			Value val = Value(model_usage.get_class().find_property("model").value_type);
			((GLib.Object)model_usage).get_property("model", ref val);
			this.model_widget.load_models.begin(model_usage.connection, val.get_string());
			
			// Get options from model_usage
			Value options_val = Value(model_usage.get_class().find_property("options").value_type);
			((GLib.Object)model_usage).get_property("options", ref options_val);
			var options = options_val.get_object() as OLLMchat.Call.Options;
			this.options_widget.load_config(options);
		}
		
		/**
		 * Applies the ModelUsage object to the parent config object.
		 * 
		 * The nested widgets (Connection, Model, Options) already update the ModelUsage object
		 * directly via their apply_property methods. This method applies the ModelUsage object
		 * back to the parent config object.
		 * 
		 * @param config The parent config object to apply the ModelUsage to
		 */
		public void apply_property(Object config)
		{
			// Nested widgets already updated this.model_usage directly
			// Just set it back to the parent config
			Value new_val = Value(this.pspec.value_type);
			new_val.set_object(this.model_usage);
			config.set_property(this.pspec.get_name(), new_val);
		}
	}
}
