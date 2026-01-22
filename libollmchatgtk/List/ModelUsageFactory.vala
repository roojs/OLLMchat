/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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

namespace OLLMchatGtk.List
{
	/**
	 * Factory for creating list items from ModelUsage objects.
	 * 
	 * Creates list items that display ModelUsage objects with:
	 * - Icons for capabilities (tools, thinking)
	 * - Model name with size (using display_name_with_size())
	 * 
	 * Can be used with Gtk.ListView, Gtk.DropDown, and other list widgets.
	 * Access the factory via the .factory property.
	 * 
	 * **IMPORTANT:** This class must be stored as a property of the widget or
	 * object that uses it. If stored as a local variable, it may be garbage
	 * collected and the signal connections will be lost.
	 * 
	 * @since 1.0
	 */
	public class ModelUsageFactory : GLib.Object
	{
		/**
		 * The Gtk.SignalListItemFactory instance.
		 * Use this property to access the factory for dropdowns and list views.
		 */
		public Gtk.SignalListItemFactory factory { get; private set; }
		
		/**
		 * Constructor.
		 */
		public ModelUsageFactory()
		{
			this.factory = new Gtk.SignalListItemFactory();
			
			// Setup: Create widgets when list item is created
			this.factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}

				var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
					margin_start = 5,
					margin_end = 5
				};

				// Icons for capabilities
				var tools_icon = new Gtk.Image.from_icon_name("document-properties") {
					visible = false,
					tooltip_text = "Supports tool calling"
				};
				var thinking_icon = new Gtk.Image.from_icon_name("weather-fog") {
					visible = false,
					tooltip_text = "Supports thinking output"
				};

				// Model name label (with size)
				var name_label = new Gtk.Label("") {
					hexpand = true,
					halign = Gtk.Align.START
				};

				box.append(tools_icon);
				box.append(thinking_icon);
				box.append(name_label);

				// Store widget references using object data
				list_item.set_data<Gtk.Image>("tools_icon", tools_icon);
				list_item.set_data<Gtk.Image>("thinking_icon", thinking_icon);
				list_item.set_data<Gtk.Label>("name_label", name_label);

				list_item.child = box;
			});

			// Bind: Update widgets when list item is bound to a ModelUsage
			this.factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}

				var model_usage = list_item.item as OLLMchat.Settings.ModelUsage;
				if (model_usage == null) {
					return;
				}

				// Retrieve widgets using object data
				var tools_icon = list_item.get_data<Gtk.Image>("tools_icon");
				var thinking_icon = list_item.get_data<Gtk.Image>("thinking_icon");
				var name_label = list_item.get_data<Gtk.Label>("name_label");

				if (tools_icon == null || thinking_icon == null || name_label == null) {
					return;
				}

				// Update label and icon visibility based on model_obj capabilities
				if (model_usage.model_obj != null) {
					name_label.label = model_usage.model_obj.name_with_size;
					tools_icon.visible = model_usage.model_obj.can_call;
					thinking_icon.visible = model_usage.model_obj.is_thinking;
				} else {
					// should never happen really - as our model useage has to have model obj.
					name_label.label = model_usage.model;
					tools_icon.visible = false;
					thinking_icon.visible = false;
				}
			});

			// Unbind: Clean up when list item is unbound
			this.factory.unbind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}

				// Retrieve widgets
				var tools_icon = list_item.get_data<Gtk.Image>("tools_icon");
				var thinking_icon = list_item.get_data<Gtk.Image>("thinking_icon");
				var name_label = list_item.get_data<Gtk.Label>("name_label");

				// Clear bindings and reset visibility
				if (tools_icon != null) {
					tools_icon.visible = false;
				}
				if (thinking_icon != null) {
					thinking_icon.visible = false;
				}
				if (name_label != null) {
					name_label.label = "";
				}
			});
		}
	}
}

