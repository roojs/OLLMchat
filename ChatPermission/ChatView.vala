namespace OLLMchat.ChatPermission
{
	/**
	 * Permission provider that displays permission requests using ChatWidget's permission widget.
	 * 
	 * This provider delegates to ChatWidget's integrated permission widget,
	 * which is positioned between ChatView and ChatInput for stable display.
	 * Also sends a system notification to inform the user about the permission request.
	 */
	public class ChatView : Provider
	{
		private UI.ChatWidget chat_widget;
		
		/**
		 * GLib.Application instance to use for sending notifications.
		 * If null, notifications will not be sent.
		 */
		public GLib.Application? application { get; set; default = null; }
		
		/**
		 * Creates a new ChatView permission provider.
		 * 
		 * @param chat_widget The ChatWidget instance that contains the permission widget
		 * @param directory Directory where permission files are stored (empty string by default)
		 */
		public ChatView(UI.ChatWidget chat_widget, string directory = "")
		{
			base(directory);
			this.chat_widget = chat_widget;
		}
		
		protected override async PermissionResponse request_user(Ollama.Tool tool)
		{
			// Send notification if application is available
			if (this.application != null) {
				this.application.send_notification(
					"ollmchat-permission-%u".printf((uint)GLib.get_real_time()),
					new GLib.Notification(tool.permission_question)
				);
			}
			
			return yield this.chat_widget.request_permission(tool);
		}
	}
}

