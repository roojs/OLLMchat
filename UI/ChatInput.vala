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

namespace OLLMchat.UI
{
	/**
	 * Chat input widget with multiline text input and send/stop button.
	 * 
	 * This widget provides a text input area with a button that switches
	 * between "Send" and "Stop" states depending on whether a request
	 * is currently streaming.
	 * 
	 * @since 1.0
	 */
	public class ChatInput : Gtk.Box
	{
		private Gtk.TextView text_view;
		private Gtk.TextBuffer buffer;
		private Gtk.Button action_button;
		private Gtk.DropDown? model_dropdown = null;
		private Gtk.Label? model_loading_label = null;
		private GLib.ListStore? model_store = null;
		private Gtk.SortListModel? sorted_models = null;
		private Ollama.Client? client = null;
		private bool is_streaming = false;
		private bool is_loading_models = false;
		private Gtk.MenuButton? tools_menu_button = null;

		/**
		* Default message text to display in the input field.
		* 
		* @since 1.0
		*/
		public string default_message
		{
			private get { return "";   }
			set {
				GLib.debug("[ChatInput] default_message setter called with '%s' (length=%d)", value, value.length);
				this.buffer.set_text(value, -1);
			
			}
		}

		/**
	 * Emitted when the send button is clicked or Enter is pressed.
		 * 
		 * @param text The message text to send
		 * @since 1.0
		 */
		public signal void send_clicked(string text);

		/**
		 * Emitted when the stop button is clicked.
		 * 
		 * @since 1.0
		 */
		public signal void stop_clicked();

	/**
	 * Creates a new ChatInput instance.
	 * 
	 * @since 1.0
	 */
	public ChatInput()
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 5);

		GLib.debug("[ChatInput] Constructor called, default_message='%s' (length=%d)", this.default_message, this.default_message.length);

		// Create buffer with default message text
		this.buffer = new Gtk.TextBuffer(null);
		this.buffer.set_text(this.default_message, -1);

		// Create text view with buffer
		this.text_view = new Gtk.TextView.with_buffer(this.buffer) {
			wrap_mode = Gtk.WrapMode.WORD,
			margin_start = 10,
			margin_end = 10,
			margin_top = 5,
			margin_bottom = 5
		};
		this.text_view.set_size_request(-1, 100); // Set minimum height

			// Create scrolled window for text view
			var scrolled = new Gtk.ScrolledWindow() {
				vexpand = false
			};
			scrolled.set_child(this.text_view);
			scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
			this.append(scrolled);

			// Create button box with dropdown on left, button on right
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
				margin_start = 10,
				margin_end = 10,
				margin_bottom = 5,
				hexpand = true
			};

			// Model dropdown will be added here when setup_model_dropdown is called
			// It will be on the left side of the button box

			// Add spacer to push button to the right
			var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			};
			button_box.append(spacer);
			
			// Create action button (Send/Stop) - will be on the right
			this.action_button = new Gtk.Button.with_label("Send");
			this.action_button.clicked.connect(this.on_button_clicked);
			button_box.append(this.action_button);

			this.append(button_box);

			// Connect key press event for Enter key handling
			var controller = new Gtk.EventControllerKey();
			controller.key_pressed.connect(this.on_key_pressed);
			this.text_view.add_controller(controller);
		}

		/**
		 * Sets the streaming state, updating button label and input state.
		 * 
		 * @param streaming Whether a request is currently streaming
		 * @since 1.0
		 */
		public void set_streaming(bool streaming)
		{
			this.is_streaming = streaming;
			if (streaming) {
				this.action_button.label = "Stop";
				this.text_view.editable = false;
				this.text_view.sensitive = false;
			} else {
				this.action_button.label = "Send";
				this.text_view.editable = true;
				this.text_view.sensitive = true;
			}
		}

	/**
	 * Clears the input text view.
	 * 
	 * @since 1.0
	 */
	public void clear_input()
	{
		Gtk.TextIter start_iter, end_iter;
		this.buffer.get_start_iter(out start_iter);
		this.buffer.get_end_iter(out end_iter);
		this.buffer.delete(ref start_iter, ref end_iter);
	}

	/**
	 * Sets the default text in the input field.
	 * 
	 * @param text The default text to display
	 * @since 1.0
	 */
	public void set_default_text(string text)
	{
		Gtk.TextIter start_iter, end_iter;
		this.buffer.get_start_iter(out start_iter);
		this.buffer.get_end_iter(out end_iter);
		this.buffer.delete(ref start_iter, ref end_iter);
		this.buffer.insert(ref start_iter, text, -1);
	}

		private void on_button_clicked()
		{
			if (this.is_streaming) {
				this.stop_clicked();
			} else {
				this.send_current_text();
			}
		}

		private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state)
		{
			// Enter key sends message (unless Ctrl+Enter or Shift+Enter for newline)
			if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
				bool ctrl_pressed = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
				bool shift_pressed = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

				// Ctrl+Enter or Shift+Enter creates newline
				if (ctrl_pressed || shift_pressed) {
					return false; // Let default behavior handle it
				}

				// Enter sends message (if not streaming)
				if (!this.is_streaming) {
					this.send_current_text();
					return true; // Consume the event
				}
			}

			return false;
		}

		private void send_current_text()
		{
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			string text = this.buffer.get_text(start_iter, end_iter, false);

			if (text.strip().length < 1) {
				return;
			}
			this.send_clicked(text);
			
		}

		/**
		 * Sets up the model dropdown widget.
		 * 
		 * @param client The Ollama client instance
		 * @since 1.0
		 */
		public void setup_model_dropdown(Ollama.Client client)
		{
			this.client = client;

			// Create ListStore for models
			this.model_store = new GLib.ListStore(typeof(Ollama.Model));

			// Create sorted model that sorts by name
			var name_expression = new Gtk.PropertyExpression(typeof(Ollama.Model), null, "name");
			var sorter = new Gtk.StringSorter(name_expression);
			this.sorted_models = new Gtk.SortListModel(this.model_store, sorter);

			// Create shared factory for both button and popup (with icons, name, size)
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
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

				// Store widget references using object data (like the GTK example)
				list_item.set_data<Gtk.Image>("tools_icon", tools_icon);
				list_item.set_data<Gtk.Image>("thinking_icon", thinking_icon);
				list_item.set_data<Gtk.Label>("name_label", name_label);

				list_item.child = box;
			});

			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}

				var model = list_item.item as Ollama.Model;

				// Retrieve widgets using object data
				var tools_icon = list_item.get_data<Gtk.Image>("tools_icon");
				var thinking_icon = list_item.get_data<Gtk.Image>("thinking_icon");
				var name_label = list_item.get_data<Gtk.Label>("name_label");

				// Bind widget properties to model properties
				model.bind_property("can_call", tools_icon, "visible", BindingFlags.SYNC_CREATE);
				model.bind_property("is_thinking", thinking_icon, "visible", BindingFlags.SYNC_CREATE);
				model.bind_property("name_with_size", name_label, "label", BindingFlags.SYNC_CREATE);
			});

			factory.unbind.connect((item) => {
				// Property bindings are automatically cleaned up when objects are destroyed
			});

			// Create dropdown
			this.model_dropdown = new Gtk.DropDown(this.sorted_models, null) {
				visible = false,
				hexpand = false
			};

			// Use the same factory for both button and popup (with icons)
			this.model_dropdown.set_factory(factory);
			this.model_dropdown.set_list_factory(factory);

			// Connect selection change to update client.model, think, and tools
			// Ignore selection changes during model loading to preserve configured values
			this.model_dropdown.notify["selected"].connect(() => {
				// Ignore selection changes while loading models
				if (this.is_loading_models) {
					return;
				}
				
				var selected = this.model_dropdown.selected;
				if (selected != Gtk.INVALID_LIST_POSITION) {
					var model = this.sorted_models.get_item(selected) as Ollama.Model;
					
					this.client.model = model.name;
					// Set think based on model capability
					this.client.think = model.is_thinking;
					
					// Update tools button visibility based on model's can_call property
					if (this.tools_menu_button != null) {
						this.tools_menu_button.visible = model.can_call;
					}
				}
			});

			// Create loading label
			this.model_loading_label = new Gtk.Label("Loading Model data...") {
				visible = true,
				hexpand = false
			};

			// Create tools menu button
			this.setup_tools_menu_button();

			// Add loading label, dropdown, and tools button to button box (before the Send button, on the left)
			var button_box = this.get_last_child() as Gtk.Box;
			if (button_box != null) {
				button_box.prepend(this.model_loading_label);
				button_box.prepend(this.model_dropdown);
				if (this.tools_menu_button != null) {
					button_box.prepend(this.tools_menu_button);
				}
			}
		}

		/**
		 * Sets up the tools menu button with popover containing checkboxes for each tool.
		 * 
		 * @since 1.0
		 */
		private void setup_tools_menu_button()
		{
			// Create popover for tools menu
			var popover = new Gtk.Popover();
			var popover_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5) {
				margin_start = 10,
				margin_end = 10,
				margin_top = 10,
				margin_bottom = 10
			};
			popover.set_child(popover_box);

			// Create checkboxes for each tool
			foreach (var tool in this.client.tools.values) {
				var check_button = new Gtk.CheckButton.with_label(tool.name);
				// Bind checkbox active state to tool active property
				tool.bind_property("active", check_button, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
				popover_box.append(check_button);
			}

			// Create menu button with icon
			this.tools_menu_button = new Gtk.MenuButton() {
				icon_name = "document-properties",
				tooltip_text = "Manage Tool Availability",
				visible = false,
				hexpand = false,
				popover = popover
			};
		}

		/**
		 * Loads models and updates the model dropdown with available models and sets selection.
		 * 
		 * First populates the list with basic model info from models(), then asynchronously
		 * fetches detailed info via show_model() which will automatically update the UI.
		 * 
		 * @since 1.0
		 */
		public async void update_models()
		{
			this.is_loading_models = true;
			try {
				// Get basic model list - this populates available_models automatically
				var models_list = yield this.client.models();
				
				// Clear existing models
				this.model_store.remove_all();

				// Add models from available_models (populated by models() call)
				foreach (var model in this.client.available_models.values) {
					this.model_store.append(model);
				}
				
				// Hide loading label and show dropdown
				if (this.model_loading_label != null) {
					this.model_loading_label.visible = false;
				}
				this.model_dropdown.visible = true;

				// Set selection to match client.model and update client state
				// This will trigger the notify signal, but we're ignoring it during loading
				if (this.client.model != "") {
					for (uint i = 0; i < this.sorted_models.get_n_items(); i++) {
						var model = this.sorted_models.get_item(i) as Ollama.Model;
						if (model.name != this.client.model) {
							continue;
						}
						this.model_dropdown.selected = i;
						// Update client.think based on selected model (do this directly, not via signal)
						this.client.think = model.is_thinking;
						// Update tools button visibility based on model's can_call property
						if (this.tools_menu_button != null) {
							this.tools_menu_button.visible = model.can_call;
						}
						break;
					}
				}
				
				// Asynchronously fetch detailed info for each model
				// This will automatically update the UI since we're updating the same Model objects
				foreach (var model in models_list) {
					try {
						yield this.client.show_model(model.name);
					} catch (Error e) {
						GLib.warning("Failed to get details for model %s: %s", model.name, e.message);
						// Continue with other models
					}
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to load models: %s", e.message);
				// Don't show error to user - dropdown will just remain hidden
				return;
			} finally {
				this.is_loading_models = false;
			}
		}
	}
}

