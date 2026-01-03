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
	 * Widget class for string properties.
	 * 
	 * Extends Row (ActionRow) and adds an entry for string properties.
	 * 
	 * @since 1.0
	 */
	public class String : Row
	{
		private Gtk.Entry entry;
		
		/**
		 * Creates a new String widget.
		 * 
		 * @param pspec The property spec for the string property
		 * @param config The config object that contains this property
		 */
		public String(ParamSpec pspec, Object config)
		{
			base(pspec, config);
		}
		
		protected override void setup_widget()
		{
			// Create entry widget
			this.entry = new Gtk.Entry() {
				width_chars = 30,
				valign = Gtk.Align.CENTER
			};
			this.add_suffix(this.entry);
			this.set_activatable_widget(this.entry);
			
			// Bind property changes
			this.entry.changed.connect(() => {
				if (this.loading_config) {
					return;
				}
				Value new_val = Value(pspec.value_type);
				new_val.set_string(this.entry.text);
				this.config.set_property(this.pspec.get_name(), new_val);
			});
		}
		
		public override void load_config(Object config)
		{
			this.loading_config = true;
			Value val = Value(pspec.value_type);
			config.get_property(this.pspec.get_name(), ref val);
			this.entry.text = val.get_string();
			this.loading_config = false;
		}
		
		public override void apply_property(Object obj)
		{
			
			Value new_val = Value(pspec.value_type);
			new_val.set_string(this.entry.text);
			obj.set_property(this.pspec.get_name(), new_val);
		}
	}
}

