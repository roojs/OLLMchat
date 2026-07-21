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
	 * Chat bar widget: model dropdown and play/Stop action button.
	 * ChatWidget creates this and places it in the lower box with the permission widget.
	 *
	 * @since 1.0
	 */
	public class ChatBar : Gtk.Box
	{
		public Gtk.Button action_button;
		private Gtk.DropDown model_dropdown;
		private Gtk.Label model_loading_label;
		private OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage> sorted_models;
		private OLLMchat.History.Manager manager;
		private bool is_streaming = false;
		/** True when ChatInput is expanded; ChatWidget sets this and action_button.visible. */
		public bool composer_expanded = false;
		private bool is_loading_models = false;
		private OLLMchatGtk.List.ModelUsageFactory button_factory;
		private OLLMchatGtk.List.ModelUsageFactory list_factory;

		/** Emitted when the user clicks Send (caller gets text from ChatInput and sends). */
		public signal void send_requested();

		/** Emitted when the user clicks Stop. */
		public signal void stop_clicked();

		/**
		 * Horizontal strip for tool toggles (leftmost, before model dropdown).
		 *
		 * Application may append extra widgets; prefer {@link add_tool_toggle}
		 * for {@link OLLMchat.Tool.UiWidgets} tools.
		 */
		public Gtk.Box tool_button_box { get; private set; }

		/**
		 * User toggled a tool chrome button.
		 *
		 * @param tool_name {@link OLLMchat.Tool.BaseTool.name}
		 * @param active whether the toggle is on
		 */
		public signal void tool_toggle(string tool_name, bool active);

		public ChatBar(OLLMchat.History.Manager manager)
		{
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 5);
			this.manager = manager;
			this.margin_start = 10;
			this.margin_end = 10;
			this.margin_top = 8;
			this.margin_bottom = 9;
			this.hexpand = true;

			this.model_loading_label = new Gtk.Label("Loading Model data...") {
				visible = false,
				hexpand = false
			};
			this.model_dropdown = new Gtk.DropDown(null, null) {
				visible = false,
				hexpand = false
			};
			this.model_dropdown.add_css_class("chat-bar-model");

			this.tool_button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
				hexpand = false,
				vexpand = false,
			};
			this.append(this.tool_button_box);
			this.append(this.model_loading_label);
			this.append(this.model_dropdown);
			this.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

			this.action_button = new Gtk.Button.from_icon_name("media-playback-start-symbolic") {
				tooltip_text = "Send"
			};
			/* App blue #3584E4 — not suggested-action (follows desktop accent, often orange). */
			this.action_button.add_css_class("chat-composer-send");
			this.action_button.clicked.connect(() => {
				if (this.is_streaming) {
					this.stop_clicked();
					return;
				}
				this.send_requested();
			});
			this.append(this.action_button);
			this.action_button.visible = false;
		}

		/**
		 * Create and pack a tool toggle from icon + tooltip.
		 *
		 * @param tool_name stable id ({@link OLLMchat.Tool.BaseTool.name})
		 * @param icon_name symbolic icon for the toggle
		 * @param tooltip_text tooltip for the toggle
		 */
		public void add_tool_toggle(string tool_name, string icon_name, string tooltip_text)
		{
			var button = new Gtk.ToggleButton() {
				icon_name = icon_name,
				tooltip_text = tooltip_text,
			};
			button.set_data<string>("tool-name", tool_name);
			button.toggled.connect(() => {
				this.tool_toggle(tool_name, button.active);
			});
			this.tool_button_box.append(button);
		}

		/**
		 * Set a tool toggle active without the caller holding the button.
		 *
		 * Used when a tool emits {@link OLLMchat.Tool.UiWidgets.show_view}.
		 *
		 * @param tool_name {@link OLLMchat.Tool.BaseTool.name}
		 * @param active desired toggle state
		 */
		public void toggle_active_tool(string tool_name, bool active)
		{
			for (var child = this.tool_button_box.get_first_child(); child != null; child = child.get_next_sibling()) {
				var button = child as Gtk.ToggleButton;
				if (button == null) {
					continue;
				}
				if (button.get_data<string>("tool-name") != tool_name) {
					continue;
				}
				if (button.active == active) {
					return;
				}
				button.active = active;
				return;
			}
		}

		/** Call when streaming state changes; updates play/Stop chrome and visibility. */
		public void sync_streaming(bool streaming)
		{
			this.is_streaming = streaming;
			/* Use icon_name/label only — set_child breaks Adwaita button chrome. */
			this.action_button.remove_css_class("suggested-action");
			this.action_button.remove_css_class("destructive-action");
			this.action_button.remove_css_class("chat-composer-send");
			if (streaming) {
				this.action_button.icon_name = "media-playback-stop-symbolic";
				this.action_button.label = "Stop";
				this.action_button.tooltip_text = "Stop";
				/* Faded red (Adwaita destructive) — not the blue send class. */
				this.action_button.add_css_class("destructive-action");
				this.action_button.visible = true;
				return;
			}
			this.action_button.label = null;
			this.action_button.icon_name = "media-playback-start-symbolic";
			this.action_button.tooltip_text = "Send";
			/* App blue #3584E4 — not suggested-action (desktop accent is often orange). */
			this.action_button.add_css_class("chat-composer-send");
			this.action_button.visible = this.composer_expanded;
		}

		private void sync_visibility()
		{
			var has_models = this.manager.connection_models.get_n_items() > 0;
			this.model_dropdown.visible = has_models;
			this.model_loading_label.visible = has_models && this.is_loading_models;
		}

		public void init_models()
		{
			var connection_models = this.manager.connection_models;
			connection_models.items_changed.connect((position, removed, added) => {
				this.sync_visibility();
			});

			this.sorted_models = new OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage>(
				connection_models,
				new OLLMchatGtk.List.ModelUsageSort(),
				new Gtk.CustomFilter((item) => {
					return !((OLLMchat.Settings.ModelUsage)item).model.has_prefix("ollmchat-temp/");
				})
			);
			this.button_factory = new OLLMchatGtk.List.ModelUsageFactory(22);
			this.list_factory = new OLLMchatGtk.List.ModelUsageFactory();
			this.model_dropdown.model = this.sorted_models;
			this.model_dropdown.set_factory(this.button_factory.factory);
			this.model_dropdown.set_list_factory(this.list_factory.factory);

			var popup = this.model_dropdown.get_first_child()?.get_next_sibling() as Gtk.Popover;
			if (popup != null) {
				popup.set_offset(0, 10);
				popup.show.connect(() => {
					var root = this.get_root();
					if (root == null) {
						return;
					}
					var width = root.get_width() - 32;
					Idle.add(() => {
						popup.set_size_request(width, -1);
						return false;
					});
				});
			}

			this.model_dropdown.notify["selected"].connect(() => {
				if (this.is_loading_models) {
					return;
				}
				if (this.model_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}

				var model_usage = this.sorted_models.get_item_typed(
					this.model_dropdown.selected);
				if (model_usage == null || model_usage.model_obj == null) {
					return;
				}

				this.manager.session.activate_model(model_usage);
				this.manager.default_model_usage.connection = model_usage.connection;
				this.manager.default_model_usage.model = model_usage.model;
				this.manager.default_model_usage.options = model_usage.options.clone();
				this.manager.config.save();
				this.sync_visibility();
			});

			this.manager.session_activated.connect((session) => {
				if (this.manager.connection_models.get_n_items() == 0) {
					return;
				}
				Idle.add(() => {
					this.sync_models.begin();
					return false;
				});
			});
			if (this.manager.connection_models.get_n_items() > 0) {
				Idle.add(() => {
					this.sync_models.begin();
					return false;
				});
			}
		}

		public async void sync_models()
		{
			if (this.manager.session == null) {
				return;
			}

			var position = this.sorted_models.find_position(
				this.manager.session.model_usage);
			if (position != Gtk.INVALID_LIST_POSITION) {
				this.model_dropdown.selected = position;
			}
			this.sync_visibility();
		}
	}
}
