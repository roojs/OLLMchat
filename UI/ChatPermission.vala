namespace OLLMchat.UI
{
	/**
	 * Permission widget that displays permission requests with buttons.
	 * 
	 * This widget is designed to be integrated into ChatWidget between
	 * ChatView and ChatInput. It handles showing/hiding internally and
	 * uses async methods to return user responses.
	 * 
	 * @since 1.0
	 */
	public class ChatPermission : Gtk.Frame
	{
		private Gtk.Label question_label;
		private Gtk.Box button_box;
		private SourceFunc? resume_callback = null;
		private OLLMchat.ChatPermission.PermissionResponse? pending_response = null;
		
		/**
		 * Creates a new ChatPermission widget.
		 * 
		 * @since 1.0
		 */
		public ChatPermission()
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
			this.button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 12,
				halign = Gtk.Align.START
			};
			
			// Create buttons with styling
			var deny_always_btn = this.create_button("Deny Always", "Permanently deny this permission", OLLMchat.ChatPermission.PermissionResponse.DENY_ALWAYS, true);
			var deny_btn = this.create_button("Deny", "Deny for this session only", OLLMchat.ChatPermission.PermissionResponse.DENY_SESSION, true);
			var allow_btn = this.create_button("Allow", "Allow for this session only", OLLMchat.ChatPermission.PermissionResponse.ALLOW_SESSION, false);
			var allow_once_btn = this.create_button("Allow Once", "Allow this one time only", OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE, false);
			var allow_always_btn = this.create_button("Allow Always", "Permanently allow this permission", OLLMchat.ChatPermission.PermissionResponse.ALLOW_ALWAYS, false);
			
			// Add buttons to button box
			this.button_box.append(deny_always_btn);
			this.button_box.append(deny_btn);
			this.button_box.append(allow_btn);
			this.button_box.append(allow_once_btn);
			this.button_box.append(allow_always_btn);
			
			// Create main container
			var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true
			};
			container.append(this.question_label);
			container.append(this.button_box);
			
			// Configure frame
			this.margin_top = 16;
			this.hexpand = true;
			this.set_child(container);
			this.add_css_class("permission-widget");
			this.set_visible(false);
		}
		
		/**
		 * Requests permission from the user with the given question.
		 * 
		 * Shows the widget, waits for user response, then hides the widget.
		 * 
		 * @param question The permission question to display
		 * @return The user's permission response
		 * @since 1.0
		 */
		public async OLLMchat.ChatPermission.PermissionResponse request(string question)
		{
			// Update question text
			this.question_label.label = question;
			
			// Show the widget
			this.set_visible(true);
			
			// Wait for user response using callback pattern
			this.pending_response = null;
			this.resume_callback = request.callback;
			
			// Yield and wait for callback to be invoked
			yield;
			
			// Clean up
			this.resume_callback = null;
			
			// Hide the widget
			this.set_visible(false);
			
			return this.pending_response ?? OLLMchat.ChatPermission.PermissionResponse.DENY_ONCE;
		}
		
		/**
		 * Creates a styled permission button.
		 */
		private Gtk.Button create_button(string label, string tooltip, OLLMchat.ChatPermission.PermissionResponse response, bool is_deny)
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
		 * Handles button click and resumes the async function.
		 */
		private void handle_button_click(OLLMchat.ChatPermission.PermissionResponse response)
		{
			this.pending_response = response;
			
			// Resume the async function
			if (this.resume_callback != null) {
				this.resume_callback();
			}
		}
	}
}

