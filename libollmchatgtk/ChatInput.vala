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

namespace OLLMchatGtk
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
		private Gtk.DropDown agent_dropdown;
		private Gtk.DropDown model_dropdown;
		private Gtk.Label model_loading_label;
		private GLib.ListStore? model_store = null;
		private Gtk.SortListModel? sorted_models = null;
		private OLLMchat.History.Manager manager;
		private bool is_streaming = false;
		private bool is_loading_models = false;
		private Gtk.MenuButton tools_menu_button;
		private Binding? tools_button_binding = null;
		

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
		 * Whether to show the model selection dropdown.
		 * 
		 * @since 1.0
		 */
		public bool show_models { get; set; default = true; }

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
		* @param manager The history manager instance
		* @since 1.0
		*/
		public ChatInput(OLLMchat.History.Manager manager)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 5);
			this.manager = manager;
			// Allow vertical expansion so input area can grow when paned is resized
			this.vexpand = true;

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
				margin_bottom = 5,
				tooltip_text = "Ctrl+Enter to send, Enter adds new lines"
			};
			// Set initial height for 3 lines of text visible
			// The text view will grow naturally with content when the scrolled window expands
			this.text_view.set_size_request(-1, 60);
			// Add CSS class for styling
			this.text_view.add_css_class("chat-input-text");

			// Create scrolled window for text view
			var scrolled = new Gtk.ScrolledWindow() {
				vexpand = true,  // Allow vertical expansion when paned is resized
				hexpand = true
			};
			// Set minimum size for 3 lines of text visible (~60px for text + margins)
			// This ensures we start with 3 lines visible, but can grow without limit
			scrolled.set_size_request(-1, 60);
			scrolled.set_child(this.text_view);
			//scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
			// Add CSS class for styling
 			this.append(scrolled);

			// Create button box with dropdown on left, button on right
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5) {
				margin_start = 10,
				margin_end = 10,
				margin_bottom = 5,
				hexpand = true
			};

			// Create agent dropdown (will be set up in setup_agent_dropdown)
			this.agent_dropdown = new Gtk.DropDown(null, null) {
				hexpand = false
			};
			
			// Create model-related widgets (always created, visibility controlled later)
			this.model_loading_label = new Gtk.Label("Loading Model data...") {
				visible = false,
				hexpand = false
			};
			
			// Create empty dropdown (will be set up in setup_model_dropdown)
			this.model_dropdown = new Gtk.DropDown(null, null) {
				visible = false,
				hexpand = false
			};
			
			// Create tools menu button (will be set up in setup_model_dropdown)
			this.tools_menu_button = new Gtk.MenuButton() {
				icon_name = "document-properties",
				tooltip_text = "Manage Tool Availability",
				visible = false,
				hexpand = false
			};
			
			// Always add widgets to button box in order (agent dropdown before model dropdown)
			button_box.append(this.agent_dropdown);
			button_box.append(this.model_loading_label);
			button_box.append(this.model_dropdown);
			button_box.append(this.tools_menu_button);

			// Add spacer to push button to the right
			button_box.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			
			// Create action button (Send/Stop) - will be on the right
			this.action_button = new Gtk.Button.with_label("Send");
			this.action_button.clicked.connect(this.on_button_clicked);
			button_box.append(this.action_button);

			this.append(button_box);

			// Connect key press event for Enter key handling
			var controller = new Gtk.EventControllerKey();
			controller.key_pressed.connect(this.on_key_pressed);
			this.text_view.add_controller(controller);
			
			// TODO: Clipboard feature needs proper design - see TODO.md
			// Connect to paste-clipboard signal to intercept paste and replace with file reference if available
			// this.text_view.paste_clipboard.connect(() => {
			// 	this.on_paste_clipboard();
			// });
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
			// Ctrl+Enter sends message, Enter adds newline
			if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
				// Ctrl+Enter sends message (if not streaming)
				if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
					if (!this.is_streaming) {
						this.send_current_text();
						return true; // Consume the event
					}
					return true; // Consume Ctrl+Enter even when streaming
				}

				// Enter without Ctrl adds newline (let default behavior handle it)
				return false;
			}

			return false;
		}

		// TODO: Clipboard feature needs proper design - see TODO.md
		// /**
		//  * Handle paste-clipboard signal to replace pasted text with file reference if available.
		//  * 
		//  * Note: This handler needs to work synchronously to prevent default paste behavior.
		//  * We use a workaround: read clipboard content provider to check for metadata.
		//  */
		// private void on_paste_clipboard()
		// {
		// 	// Get clipboard
		// 	var display = Gdk.Display.get_default();
		// 	if (display == null) {
		// 		return;
		// 	}
		// 	
		// 	var clipboard = display.get_clipboard();
		// 	
		// 	// Try to read clipboard text synchronously using content provider
		// 	// This is a workaround since we need to check before default paste happens
		// 	var content = clipboard.get_content();
		// 	if (content == null) {
		// 		return;
		// 	}
		// 	
		// 	// Check if we can get text from content provider
		// 	// We'll use a MainLoop to make this synchronous within the signal handler
		// 	string? clipboard_text = null;
		// 	bool got_text = false;
		// 	
		// 	content.read_async.begin(typeof(string), Gdk.ContentProvider.PRIORITY_DEFAULT, null, (obj, res) => {
		// 		try {
		// 			var value = content.read_async.end(res);
		// 			if (value != null && value.holds(typeof(string))) {
		// 				clipboard_text = (string)value.get_string();
		// 			}
		// 			got_text = true;
		// 		} catch (Error e) {
		// 			got_text = true; // Mark as done even on error
		// 		}
		// 	});
		// 	
		// 	// Wait for async operation to complete (with timeout)
		// 	var loop = new MainLoop();
		// 	var timeout_id = Timeout.add(100, () => {
		// 		loop.quit();
		// 		return false;
		// 	});
		// 	
		// 	// Wait for result or timeout
		// 	while (!got_text) {
		// 		loop.run();
		// 		if (got_text) {
		// 			Source.remove(timeout_id);
		// 			break;
		// 		}
		// 	}
		// 	
		// 	if (clipboard_text == null) {
		// 		// Couldn't read clipboard, let default paste happen
		// 		return;
		// 	}
		// 	
		// 	// Check if clipboard metadata is available and can provide a file reference
		// 	if (ClipboardManager.metadata != null) {
		// 		string? file_ref = ClipboardManager.metadata.get_file_reference_for_clipboard_text(clipboard_text);
		// 		if (file_ref != null) {
		// 			// File reference found - replace paste with file reference
		// 			// Get cursor position
		// 			Gtk.TextIter cursor_iter;
		// 			this.buffer.get_iter_at_mark(out cursor_iter, this.buffer.get_insert());
		// 			
		// 			// Insert file reference at cursor position
		// 			this.buffer.insert(ref cursor_iter, file_ref, -1);
		// 			
		// 			// Move cursor to end of inserted text
		// 			this.buffer.place_cursor(cursor_iter);
		// 			
		// 			// Stop signal emission to prevent default paste behavior
		// 			// Note: In GTK4, we can't directly stop signal, but we've already inserted our text
		// 			// The default paste will still happen, but we'll handle it by checking if our text was already inserted
		// 			return;
		// 		}
		// 	}
		// 	// If no clipboard manager or no metadata, let default paste behavior proceed
		// }

		private void send_current_text()
		{
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			var text = this.buffer.get_text(start_iter, end_iter, false);

			// Trim trailing line breaks from the interface
			text = text.strip();

			if (text.length < 1) {
				return;
			}
			this.send_clicked(text);
			
		}

		/**
		 * Updates the visibility of model-related widgets based on show_models property.
		 * 
		 * @since 1.0
		 */
		private void update_model_widgets_visibility()
		{
			this.model_dropdown.visible = this.show_models;
			this.model_loading_label.visible = this.show_models && this.is_loading_models;
			
			// Tools button visibility is controlled by both show_models and model's can_call property
			if (!this.show_models) {
				// Unbind and hide when show_models is false
				if (this.tools_button_binding != null) {
					this.tools_button_binding.unbind();
					this.tools_button_binding = null;
				}
				this.tools_menu_button.visible = false;
				return;
			}
			
			// Update tools button visibility based on current model selection
			if (this.model_dropdown.selected == Gtk.INVALID_LIST_POSITION || this.sorted_models == null) {
				return;
			}
			
			var model = this.sorted_models.get_item(this.model_dropdown.selected) as OLLMchat.Response.Model;
			if (model == null) {
				return;
			}
			
			// Ensure binding is set up for automatic updates
			if (this.tools_button_binding == null) {
				this.tools_button_binding = model.bind_property("can-call", this.tools_menu_button, "visible", 
					BindingFlags.SYNC_CREATE);
			}
		}

		/**
		 * Sets up the agent dropdown widget.
		 * 
		 * @since 1.0
		 */
		public void setup_agent_dropdown()
		{
			// Create ListStore for agents
			var agent_store = new GLib.ListStore(typeof(OLLMagent.BaseAgent));
			
			// Add all registered agents to the store and set selection during load
			uint selected_index = 0;
			uint i = 0;
			foreach (var agent in this.manager.agents.values) {
				agent_store.append(agent);
				if (agent.name == this.manager.session.agent_name) {
					selected_index = i;
				}
				i++;
			}
			
			// Create factory for agent dropdown
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}
				
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});
			
			factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				
				var agent = list_item.item as OLLMagent.BaseAgent;
				var label = list_item.get_data<Gtk.Label>("label");
				
				if (label != null && agent != null) {
					label.label = agent.title;
				}
			});
			
			// Set up dropdown with agents
			this.agent_dropdown.model = agent_store;
			this.agent_dropdown.set_factory(factory);
			this.agent_dropdown.set_list_factory(factory);
			this.agent_dropdown.selected = selected_index;
			
			// Connect selection change to update session's agent_name and client
			this.agent_dropdown.notify["selected"].connect(() => {
				if (this.agent_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				
				var agent = (this.agent_dropdown.model as GLib.ListStore).get_item(this.agent_dropdown.selected) as OLLMagent.BaseAgent;
				  
				this.manager.session.agent_name = agent.name;
				// Update current session's client prompt_assistant (direct assignment, agents are stateless)
				this.manager.session.client.prompt_assistant = agent;
				
				// Emit agent_activated signal for UI updates (Window listens to this)
				this.manager.agent_activated(agent);
			});
			
			// Connect to session_activated signal to update when session changes
			this.manager.session_activated.connect((session) => {
				// Update agent selection to match session's agent
				var store = this.agent_dropdown.model as GLib.ListStore;
				if (store == null) {
					return;
				}
				
 				for (uint j = 0; j < store.get_n_items(); j++) {
					
					if (((OLLMagent.BaseAgent)store.get_item(j)).name != session.agent_name) {
						continue;
					}
					this.agent_dropdown.selected = j;
					break;
					
				}
			});
		}
		
		/**
		 * Sets up the model dropdown widget.
		 * 
		 * @since 1.0
		 */
		public void setup_model_dropdown()
		{

			// Create ListStore for models
			this.model_store = new GLib.ListStore(typeof(OLLMchat.Response.Model));

			// Create sorted model that sorts by name
			this.sorted_models = new Gtk.SortListModel(this.model_store, new Gtk.StringSorter(new Gtk.PropertyExpression(typeof(OLLMchat.Response.Model), null, "name")));

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

				var model = list_item.item as OLLMchat.Response.Model;

				// Retrieve widgets using object data
				var tools_icon = list_item.get_data<Gtk.Image>("tools_icon");
				var thinking_icon = list_item.get_data<Gtk.Image>("thinking_icon");
				var name_label = list_item.get_data<Gtk.Label>("name_label");

				// Bind widget properties to model properties
				// SYNC_CREATE syncs on binding creation, and bindings automatically update when source properties change
				model.bind_property("can_call", tools_icon, "visible", BindingFlags.SYNC_CREATE);
				model.bind_property("is_thinking", thinking_icon, "visible", BindingFlags.SYNC_CREATE);
				model.bind_property("name_with_size", name_label, "label", BindingFlags.SYNC_CREATE);
			});

			factory.unbind.connect((item) => {
				// Property bindings are automatically cleaned up when objects are destroyed
			});

			// Set up dropdown with models
			this.model_dropdown.model = this.sorted_models;

			// Use the same factory for both button and popup (with icons)
			this.model_dropdown.set_factory(factory);
			this.model_dropdown.set_list_factory(factory);

			// Connect selection change to update client.config.model, think, and tools
			// Ignore selection changes during model loading to preserve configured values
			this.model_dropdown.notify["selected"].connect(() => {
				// Ignore selection changes while loading models
				if (this.is_loading_models) {
					return;
				}
				
				if (this.model_dropdown.selected != Gtk.INVALID_LIST_POSITION) {
					var model = this.sorted_models.get_item(this.model_dropdown.selected) as OLLMchat.Response.Model;
					
					this.manager.session.client.config.model = model.name;
					// Set think based on model capability
					this.manager.session.client.think = model.is_thinking;
					
					// Update binding to new model's can_call property
					if (this.show_models) {
						if (this.tools_button_binding != null) {
							this.tools_button_binding.unbind();
						}
						this.tools_button_binding = model.bind_property("can-call", this.tools_menu_button, "visible", 
							BindingFlags.SYNC_CREATE);
					}
					
					// Update tools button visibility based on model's can_call property
					this.update_model_widgets_visibility();
				}
			});

			// Set up tools menu button
			this.setup_tools_menu_button();
			
			// Connect to session_activated signal to update when session changes
			this.manager.session_activated.connect((session) => {
				// Update tools menu button when session changes
				this.setup_tools_menu_button();
				// Reload models for the new session's client
				if (this.show_models) {
					Idle.add(() => {
						this.update_models.begin();
						return false;
					});
				}
			});
			
			// Load models asynchronously if enabled
			if (this.show_models) {
				Idle.add(() => {
					this.update_models.begin();
					return false;
				});
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
			var popover_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5) {
				margin_start = 10,
				margin_end = 10,
				margin_top = 10,
				margin_bottom = 10
			};

			// Create checkboxes for each tool
			foreach (var tool in this.manager.session.client.tools.values) {
				 
				var check_button = new Gtk.CheckButton.with_label(
					tool.description.strip().split("\n")[0]
				);
				// Bind checkbox active state to tool active property
				tool.bind_property("active", check_button, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
				popover_box.append(check_button);
			}

			// Configure the existing menu button (created in constructor) with popover
			this.tools_menu_button.popover = new Gtk.Popover() {
				child = popover_box
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
			GLib.debug("update_models: client.model='%s'", this.manager.session.client.config.model);
			this.is_loading_models = true;
			try {
				// Get basic model list - this populates available_models automatically
				var models_list = yield this.manager.session.client.models();
				
				// Clear existing models
				this.model_store.remove_all();

				// Add models from available_models (populated by models() call)
				// Prioritize the current model by adding it first
				if (this.manager.session.client.config.model != "" && this.manager.session.client.available_models.has_key(this.manager.session.client.config.model)) {
					var current_model = this.manager.session.client.available_models.get(this.manager.session.client.config.model);
					this.model_store.append(current_model);
				} else {
					GLib.debug("Current model '%s' not in available_models", this.manager.session.client.config.model);
				}
				
				// Add all other models (excluding the current one if it was already added)
				foreach (var model in this.manager.session.client.available_models.values) {
					if (this.manager.session.client.config.model != "" && model.name == this.manager.session.client.config.model) {
						continue; // Skip current model as it was already added first
					}
					this.model_store.append(model);
				}
				
				// Set selection to match client.model and update client state
				// This will trigger the notify signal, but we're ignoring it during loading
				OLLMchat.Response.Model? current_model_obj = null;
				if (this.manager.session.client.config.model != "") {
					for (uint i = 0; i < this.sorted_models.get_n_items(); i++) {
						var model = this.sorted_models.get_item(i) as OLLMchat.Response.Model;
						if (model.name != this.manager.session.client.config.model) {
							continue;
						}
						this.model_dropdown.selected = i;
						current_model_obj = model;
						// Update client.think based on selected model (do this directly, not via signal)
						this.manager.session.client.think = model.is_thinking;
						// Update tools button visibility based on model's can_call property
						this.update_model_widgets_visibility();
						break;
					}
				}
				
				// Bind tools button visibility to current model's can_call property if we have a model
				// This will automatically update when model capabilities are loaded
				// The binding will update visibility based on can_call, but we still need to check show_models
				if (current_model_obj != null && this.show_models) {
					if (this.tools_button_binding != null) {
						this.tools_button_binding.unbind();
					}
					this.tools_button_binding = current_model_obj.bind_property("can-call", this.tools_menu_button, "visible", 
						BindingFlags.SYNC_CREATE);
				}
				
				// Models are now loaded - hide loading label and show dropdown
				// Set is_loading_models to false so update_model_widgets_visibility() hides the label
				this.is_loading_models = false;
				this.update_model_widgets_visibility();
				
				// Asynchronously fetch detailed info for each model
				// Prioritize the current model by fetching its details first
				// This will automatically update the UI since we're updating the same Model objects
				if (this.manager.session.client.config.model != "" && this.manager.session.client.available_models.has_key(this.manager.session.client.config.model)) {
					try {
						yield this.manager.session.client.show_model(this.manager.session.client.config.model);
						// Update tools button visibility immediately after current model details are loaded
						this.update_model_widgets_visibility();
					} catch (Error e) {
						GLib.warning("Failed to get details for current model %s: %s", this.manager.session.client.config.model, e.message);
					}
				}
				
				// Then fetch details for all other models (in background)
				foreach (var model in models_list) {
					// Skip current model as it was already fetched
					if (this.manager.session.client.config.model != "" && model.name == this.manager.session.client.config.model) {
						continue;
					}
					try {
						yield this.manager.session.client.show_model(model.name);
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

