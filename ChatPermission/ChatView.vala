namespace OLLMchat.ChatPermission
{
	/**
	 * Permission provider that displays permission requests as interactive widgets in ChatView.
	 * 
	 * Shows a permission question with buttons for different response options.
	 * The widget is added to the end of the ChatView and removed after user responds.
	 */
	public class ChatView : Provider
	{
		private UI.ChatView chat_view;
		private Gtk.Frame permission_widget;
		private Gtk.Label question_label;
		private Gtk.TextChildAnchor? permission_anchor = null;
		private PermissionResponse? pending_response = null;
		private SourceFunc? resume_callback = null;
		
		/**
		 * Creates a new ChatView permission provider.
		 * 
		 * @param chat_view The ChatView instance to display permission widgets in
		 * @param directory Directory where permission files are stored (empty string by default)
		 */
		public ChatView(UI.ChatView chat_view, string directory = "")
		{
			base(directory);
			this.chat_view = chat_view;
			this.create_permission_widget();
		}
		
		/**
		 * Creates the permission widget structure once.
		 */
		private void create_permission_widget()
		{
			// Create question label
			this.question_label = new Gtk.Label("") {
				wrap = true,
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 8
			};
			
			// Create button row
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 12,
				halign = Gtk.Align.START
			};
			
			// Create buttons with styling
			var deny_always_btn = this.create_button("Deny Always", "Permanently deny this permission", PermissionResponse.DENY_ALWAYS, true);
			var deny_btn = this.create_button("Deny", "Deny for this session only", PermissionResponse.DENY_SESSION, true);
			var allow_btn = this.create_button("Allow", "Allow for this session only", PermissionResponse.ALLOW_SESSION, false);
			var allow_once_btn = this.create_button("Allow Once", "Allow this one time only", PermissionResponse.ALLOW_ONCE, false);
			var allow_always_btn = this.create_button("Allow Always", "Permanently allow this permission", PermissionResponse.ALLOW_ALWAYS, false);
			
			// Add buttons to button box
			button_box.append(deny_always_btn);
			button_box.append(deny_btn);
			button_box.append(allow_btn);
			button_box.append(allow_once_btn);
			button_box.append(allow_always_btn);
			
			// Create main container
			var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true
			};
			container.append(this.question_label);
			container.append(button_box);
			
			// Create frame
			this.permission_widget = new Gtk.Frame(null) {
				margin_top = 16,
				hexpand = true
			};
			this.permission_widget.set_child(container);
			this.permission_widget.add_css_class("permission-widget");
			this.permission_widget.set_visible(false);
		}
		
		protected override async PermissionResponse request_user(Ollama.Tool tool)
		{
			// Create or update the permission widget
			this.show_permission_widget(tool);
			
			// Wait for user response using callback pattern
			this.pending_response = null;
			this.resume_callback = request_user.callback;
			
			// Yield and wait for callback to be invoked
			yield;
			
			// Clean up
			this.resume_callback = null;
			
			return this.pending_response ?? PermissionResponse.DENY_ONCE;
		}
		
		/**
		 * Shows the permission widget in the ChatView.
		 */
		private void show_permission_widget(Ollama.Tool tool)
		{
			// Update question text
			this.question_label.label = tool.permission_question;
			
			// Remove widget from old position if already added
			if (this.permission_anchor != null) {
				this.chat_view.remove_widget_frame(this.permission_widget, this.permission_anchor);
				this.permission_anchor = null;
				
				// Defer re-adding to next idle to ensure removal completes
				GLib.Idle.add(() => {
					// Ensure widget is fully unparented
					if (this.permission_widget.get_parent() != null) {
						this.permission_widget.unparent();
					}
					
					// Ensure widget is visible and ready to be added
					this.permission_widget.set_visible(true);
					
					// Add blank line and frame at end
					this.chat_view.add_blank_line();
					this.permission_anchor = this.chat_view.add_widget_frame(this.permission_widget);
					return false;
				});
			} else {
				// First time showing - add directly (no removal needed)
				// Ensure widget is visible and ready
				this.permission_widget.set_visible(true);
				
				// Add blank line and frame at end
				this.chat_view.add_blank_line();
				this.permission_anchor = this.chat_view.add_widget_frame(this.permission_widget);
			}
		}
		
		/**
		 * Creates a styled permission button.
		 */
		private Gtk.Button create_button(string label, string tooltip, PermissionResponse response, bool is_deny)
		{
			var btn = new Gtk.Button.with_label(label) {
				tooltip_text = tooltip
			};
			
			if (is_deny) {
				btn.add_css_class("destructive-action");
			} else {
				btn.add_css_class("suggested-action");
			}
			
			// Set cursor to pointer (fixes issue with TextView showing text cursor)
			var cursor = new Gdk.Cursor.from_name("pointer", null);
			if (cursor != null) {
				btn.set_cursor(cursor);
			}
			
			btn.clicked.connect(() => {
				this.handle_button_click(response);
			});
			
			return btn;
		}
		
		/**
		 * Hides and removes the permission widget from ChatView.
		 */
		private void hide_permission_widget()
		{
			if (this.permission_anchor != null) {
				this.chat_view.remove_widget_frame(this.permission_widget, this.permission_anchor);
				this.permission_anchor = null;
			}
			this.permission_widget.set_visible(false);
		}
		
		/**
		 * Handles button click and resumes the async function.
		 */
		private void handle_button_click(PermissionResponse response)
		{
			this.pending_response = response;
			this.hide_permission_widget();
			
			// Resume the async function
			if (this.resume_callback != null) {
				this.resume_callback();
			}
		}
	}
}

