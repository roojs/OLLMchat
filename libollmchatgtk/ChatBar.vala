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

namespace OLLMchatGtk
{
	/**
	 * Chat bar widget: model dropdown, tools menu, Send/Stop button.
	 * ChatWidget creates this and places it in the lower box with the permission widget.
	 *
	 * @since 1.0
	 */
	public class ChatBar : Gtk.Box
	{
		private Gtk.Button action_button;
		private Gtk.DropDown model_dropdown;
		private Gtk.Label model_loading_label;
		private OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage> sorted_models;
		private OLLMchat.History.Manager manager;
		private bool is_streaming = false;
		private bool is_loading_models = false;
		private Gtk.MenuButton tools_menu_button;
		private Binding? tools_button_binding = null;
		private bool is_tool_list_loaded = false;
		private Gtk.Box? tools_popover_box = null;
		private OLLMchatGtk.List.ModelUsageFactory factory;

		/** Emitted when the user clicks Send (caller gets text from ChatInput and sends). */
		public signal void send_requested();

		/** Emitted when the user clicks Stop. */
		public signal void stop_clicked();

		public ChatBar(OLLMchat.History.Manager manager)
		{
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 5);
			this.manager = manager;
			this.margin_start = 10;
			this.margin_end = 10;
			this.margin_bottom = 5;
			this.hexpand = true;

			this.model_loading_label = new Gtk.Label("Loading Model data...") {
				visible = false,
				hexpand = false
			};
			this.model_dropdown = new Gtk.DropDown(null,
				new Gtk.PropertyExpression(typeof(OLLMchat.Response.Model), null, "name_with_size")) {
				visible = false,
				hexpand = false
			};
			this.tools_menu_button = new Gtk.MenuButton() {
				icon_name = "document-properties",
				tooltip_text = "Manage Tool Availability",
				visible = false,
				hexpand = false
			};

			this.append(this.model_loading_label);
			this.append(this.model_dropdown);
			this.append(this.tools_menu_button);
			this.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

			this.action_button = new Gtk.Button.with_label("Send");
			this.action_button.clicked.connect(this.on_button_clicked);
			this.append(this.action_button);
		}

		/** Call when streaming state changes; updates Send/Stop button label. */
		public void update_action_button_state(bool streaming)
		{
			this.is_streaming = streaming;
			this.action_button.label = streaming ? "Stop" : "Send";
		}

		private void on_button_clicked()
		{
			if (this.is_streaming) {
				this.stop_clicked();
			} else {
				this.send_requested();
			}
		}

		private void update_model_widgets_visibility()
		{
			bool has_models = this.manager.connection_models.get_n_items() > 0;
			this.model_dropdown.visible = has_models;
			this.model_loading_label.visible = has_models && this.is_loading_models;
			if (!has_models) {
				this.tools_menu_button.visible = false;
				return;
			}
			if (this.model_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
				this.tools_menu_button.visible = false;
				return;
			}
			var model_usage = this.sorted_models.get_item_typed(this.model_dropdown.selected);
			this.tools_menu_button.visible = model_usage.model_obj.can_call;
		}

		public void setup_model_dropdown()
		{
			var connection_models = this.manager.connection_models;
			connection_models.items_changed.connect((position, removed, added) => {
				this.update_model_widgets_visibility();
			});

			this.sorted_models = new OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage>(
				connection_models,
				new OLLMchatGtk.List.ModelUsageSort(),
				new Gtk.CustomFilter((item) => {
					return !((OLLMchat.Settings.ModelUsage)item).model.has_prefix("ollmchat-temp/");
				})
			);
			this.factory = new OLLMchatGtk.List.ModelUsageFactory();
			this.model_dropdown.model = this.sorted_models;
			this.model_dropdown.set_factory(this.factory.factory);
			this.model_dropdown.set_list_factory(this.factory.factory);

			this.model_dropdown.notify["selected"].connect(() => {
				if (this.is_loading_models) return;
				if (this.model_dropdown.selected != Gtk.INVALID_LIST_POSITION) {
					var model_usage = this.sorted_models.get_item_typed(this.model_dropdown.selected);
					if (model_usage == null || model_usage.model_obj == null) return;
					this.manager.session.activate_model(model_usage);
					var def = this.manager.default_model_usage;
					def.connection = model_usage.connection;
					def.model = model_usage.model;
					def.options = model_usage.options.clone();
					this.manager.config.save();
					this.update_model_widgets_visibility();
					if (this.manager.connection_models.get_n_items() == 0) return;
					if (this.tools_button_binding != null) this.tools_button_binding.unbind();
					this.tools_button_binding = model_usage.model_obj.bind_property(
						"can-call", this.tools_menu_button, "visible", BindingFlags.SYNC_CREATE);
				}
			});

			this.setup_tools_menu_button();
			this.manager.session_activated.connect((session) => {
				if (this.manager.connection_models.get_n_items() == 0) return;
				Idle.add(() => { this.update_models.begin(); return false; });
			});
			if (this.manager.connection_models.get_n_items() > 0) {
				Idle.add(() => { this.update_models.begin(); return false; });
			}
		}

		public void setup_tools_menu_button()
		{
			var popover = new Gtk.Popover();
			popover.show.connect(() => {
				if (this.is_tool_list_loaded) return;
				this.tools_popover_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5) {
					margin_start = 10, margin_end = 10, margin_top = 10, margin_bottom = 10
				};
				foreach (var entry in this.manager.tools.entries) {
					var tool = entry.value;
					if (tool.name != entry.key && !tool.is_wrapped) continue;
					var check_button = new Gtk.CheckButton.with_label(tool.title);
					tool.bind_property("active", check_button, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
					this.tools_popover_box.append(check_button);
				}
				this.is_tool_list_loaded = true;
				popover.set_child(this.tools_popover_box);
			});
			this.tools_menu_button.popover = popover;
		}

		public async void update_models()
		{
			if (this.manager.session != null) {
				uint position = this.sorted_models.find_position(this.manager.session.model_usage);
				if (position != Gtk.INVALID_LIST_POSITION) {
					this.model_dropdown.selected = position;
				}
				if (this.tools_button_binding != null) this.tools_button_binding.unbind();
				if (this.manager.session.model_usage.model_obj != null) {
					this.tools_button_binding = this.manager.session.model_usage.model_obj.bind_property(
						"can-call", this.tools_menu_button, "visible", BindingFlags.SYNC_CREATE);
				}
				this.update_model_widgets_visibility();
			}
		}
	}
}
