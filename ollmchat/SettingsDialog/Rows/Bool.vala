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
	 * Widget class for bool properties.
	 * 
	 * Extends Row (ActionRow) and adds a switch for boolean properties.
	 * 
	 * @since 1.0
	 */
	public class Bool : Row
	{
		private Gtk.Switch switch_widget;
		
		/**
		 * Creates a new Bool widget.
		 * 
		 * @param dialog The settings dialog
		 * @param config The config object that contains this property
		 * @param pspec The property spec for the bool property
		 */
		public Bool(MainDialog dialog, Object config, ParamSpec pspec)
		{
			base(dialog, config, pspec);
		}
		
		protected override void setup_widget()
		{
			// Create switch widget
			this.switch_widget = new Gtk.Switch() {
				valign = Gtk.Align.CENTER
			};
			this.add_suffix(this.switch_widget);
			this.set_activatable_widget(this.switch_widget);
			
			// Bind property changes
			this.switch_widget.notify["active"].connect(() => {
				if (this.loading_config) {
					return;
				}
				// Check if value actually changed
				Value current_val = Value(pspec.value_type);
				this.config.get_property(this.pspec.get_name(), ref current_val);
				if (current_val.get_boolean() == this.switch_widget.active) {
					return;
				}
				this.apply_property(this.config);
			});
		}
		
		public override void load_config(Object config)
		{
			this.loading_config = true;
			Value val = Value(pspec.value_type);
			config.get_property(this.pspec.get_name(), ref val);
			this.switch_widget.active = val.get_boolean();
			this.loading_config = false;
		}
		
		public override void apply_property(Object obj)
		{
			
			Value new_val = Value(pspec.value_type);
			new_val.set_boolean(this.switch_widget.active);
			obj.set_property(this.pspec.get_name(), new_val);
		}
	}
}

