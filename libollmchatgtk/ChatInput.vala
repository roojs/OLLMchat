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
		private Gtk.DropDown model_dropdown;
		private Gtk.Label model_loading_label;
		private OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage> sorted_models;
		private OLLMchat.History.Manager manager;
		private bool is_streaming = false;
		private bool is_loading_models = false;
		private Gtk.MenuButton tools_menu_button;
		private Binding? tools_button_binding = null;
		private bool is_tool_list_loaded { get; set; default = false; }
		private Gtk.Box? tools_popover_box { get; set; default = null; }
		private OLLMchatGtk.List.ModelUsageFactory factory;
			

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

			// Create model-related widgets (always created, visibility controlled later)
			this.model_loading_label = new Gtk.Label("Loading Model data...") {
				visible = false,
				hexpand = false
			};
			
		// Create empty dropdown (will be set up in setup_model_dropdown)
		// Use expression for Model.name_with_size (will be replaced in setup_model_dropdown)
		this.model_dropdown = new Gtk.DropDown(null, 
			new Gtk.PropertyExpression(typeof(OLLMchat.Response.Model), null, "name_with_size")) {
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
			
			// Add widgets to button box
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
		 * Updates the visibility of model-related widgets based on connection_models size.
		 * 
		 * @since 1.0
		 */
		private void update_model_widgets_visibility()
		{
			bool has_models = this.manager.connection_models.get_n_items() > 0;
			
			this.model_dropdown.visible = has_models;
			this.model_loading_label.visible = has_models && this.is_loading_models;
			
			// Tools button visibility is controlled by both has_models and model's can_call property
			// The binding (set up in selection handler) automatically updates visibility when can_call changes
			if (!has_models) {
				// Hide when there are no models (binding will be cleaned up in selection handler)
				this.tools_menu_button.visible = false;
				return;
			}
			
			// Update tools button visibility based on current model selection
			// The binding handles automatic updates, we just need to ensure it's visible if model supports tools
			if (this.model_dropdown.selected == Gtk.INVALID_LIST_POSITION) {
				this.tools_menu_button.visible = false;
				return;
			}
			
			var model_usage = this.sorted_models.get_item_typed(this.model_dropdown.selected);
			
			// Visibility is controlled by binding to model_obj.can_call property
			// If binding doesn't exist yet, it will be created in the selection handler
			// For now, just set visibility based on current value
			this.tools_menu_button.visible = model_usage.model_obj.can_call;
		}

		/**
		 * Sets up the model dropdown widget.
		 * 
		 * @since 1.0
		 */
		public void setup_model_dropdown()
		{
			// Use ConnectionModels from history manager
			var connection_models = this.manager.connection_models;

			// Connect to items-changed signal to update visibility based on model count
			connection_models.items_changed.connect((position, removed, added) => {
				this.update_model_widgets_visibility();
			});

			// Create sorted list model
			// Filter out ollmchat-temp/ models - they should never appear in model lists
			// (Phase 3: Hide all ollmchat-temp from model lists)
			this.sorted_models = new OLLMchatGtk.List.SortedList<OLLMchat.Settings.ModelUsage>(
				connection_models,
				new OLLMchatGtk.List.ModelUsageSort(),
				new Gtk.CustomFilter((item) => {
					return !((OLLMchat.Settings.ModelUsage)item).model.has_prefix("ollmchat-temp/");
				})
			);

			// Create factory using ModelUsageFactory (keep reference to prevent garbage collection)
			this.factory = new OLLMchatGtk.List.ModelUsageFactory();

			// Set up dropdown with models (SortedList implements ListModel)
			this.model_dropdown.model = this.sorted_models;

			// Use the same factory for both button and popup (with icons)
			this.model_dropdown.set_factory(this.factory.factory);
			this.model_dropdown.set_list_factory(this.factory.factory);

			// Connect selection change to update session.model, chat.model, chat.think, and tools
			// Ignore selection changes during model loading to preserve configured values
			this.model_dropdown.notify["selected"].connect(() => {
				// Ignore selection changes while loading models
				if (this.is_loading_models) {
					return;
				}
				
					if (this.model_dropdown.selected != Gtk.INVALID_LIST_POSITION) {
						var model_usage = this.sorted_models.get_item_typed(this.model_dropdown.selected);
					if (model_usage == null || model_usage.model_obj == null) {
						return;
					}
					
					// Activate model on session (stores ModelUsage with options overlaid from config)
					this.manager.session.activate_model(model_usage);
					
					// Update binding to new model's can_call property for automatic visibility updates
					this.update_model_widgets_visibility();

					if (this.manager.connection_models.get_n_items() == 0) {
						return;
					}
					
					if (this.tools_button_binding != null) {
						this.tools_button_binding.unbind();
					}
					this.tools_button_binding = model_usage.model_obj.bind_property(
						"can-call",
						this.tools_menu_button,
						"visible",
						BindingFlags.SYNC_CREATE
					);
					
					// Update tools button visibility based on model's can_call property
					
				}
			});

			// Set up tools menu button
			this.setup_tools_menu_button();
			
			// Connect to session_activated signal to update when session changes
			this.manager.session_activated.connect((session) => {
				// Reload models for the new session's client
				if (this.manager.connection_models.get_n_items() == 0) {
					return;
				}
				Idle.add(() => {
					this.update_models.begin();
					return false;
				});
			});
			
			// Load models asynchronously if available
			if (this.manager.connection_models.get_n_items() == 0) {
				return;
			}
			Idle.add(() => {
				this.update_models.begin();
				return false;
			});
		}

		/**
		 * Sets up the tools menu button with popover containing checkboxes for each tool.
		 * Builds the menu once when first shown if tools are loaded.
		 * 
		 * @since 1.0
		 */
		public void setup_tools_menu_button()
		{
			// Create popover for tools menu
			var popover = new Gtk.Popover();
			
			// Build menu content when popover is shown (only build once if tools are loaded)
			popover.show.connect(() => {
				// Return early if already built
				if (this.is_tool_list_loaded) {
					return;
				}
				
				// Create popover box
				this.tools_popover_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5) {
					margin_start = 10,
					margin_end = 10,
					margin_top = 10,
					margin_bottom = 10
				};

				// Create checkboxes for each tool (tools are on Manager)
				foreach (var tool in this.manager.tools.values) {
					var check_button = new Gtk.CheckButton.with_label(
						tool.title
					);
					// Bind checkbox active state to tool active property
					tool.bind_property("active", check_button, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
					this.tools_popover_box.append(check_button);
				}
				
				this.is_tool_list_loaded = true;
				popover.set_child(this.tools_popover_box);
			});

			// Configure the existing menu button (created in constructor) with popover
			this.tools_menu_button.popover = popover;
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
			GLib.debug("update_models: session.model='%s'", this.manager.session.model);
			
			// Set selection to match session.model_usage - no refresh, just update selection
			if (this.manager.session != null) {
				// Find position in sorted_models
				uint position = this.sorted_models.find_position(this.manager.session.model_usage);
				if (position != Gtk.INVALID_LIST_POSITION) {
					this.model_dropdown.selected = position;
				}
				
				// Update tools button visibility based on model's can_call property
				if (this.tools_button_binding != null) {
					this.tools_button_binding.unbind();
				}
				if (this.manager.session.model_usage.model_obj != null) {
					this.tools_button_binding = this.manager.session.model_usage.model_obj.bind_property(
						"can-call",
						this.tools_menu_button,
						"visible",
						BindingFlags.SYNC_CREATE
					);
				}
				this.update_model_widgets_visibility();
			}
		}
	}
}

