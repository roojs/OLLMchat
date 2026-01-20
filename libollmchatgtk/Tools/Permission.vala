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

namespace OLLMchatGtk.Tools
{
	/**
	 * Permission provider that displays permission requests using ChatWidget's permission widget.
	 * 
	 * This provider delegates to ChatWidget's integrated permission widget,
	 * which is positioned between ChatView and ChatInput for stable display.
	 * Also sends a system notification to inform the user about the permission request.
	 */
	public class Permission : OLLMchat.ChatPermission.Provider
	{
		private OLLMchatGtk.ChatWidget chat_widget;
		
		/**
		 * GLib.Application instance to use for sending notifications.
		 * If null, notifications will not be sent.
		 */
		[CCode (type = "GApplication*", transfer = "none")]
		public GLib.Application? application { get; set; default = null; }
		
		/**
		 * Creates a new Permission provider.
		 * 
		 * @param chat_widget The ChatWidget instance that contains the permission widget
		 * @param directory Directory where permission files are stored (empty string by default)
		 */
		public Permission(OLLMchatGtk.ChatWidget chat_widget, string directory = "")
		{
			base(directory);
			this.chat_widget = chat_widget;
		}
		
		protected override async OLLMchat.ChatPermission.PermissionResponse request_user(OLLMchat.Tool.RequestBase request)
		{
			GLib.debug("OLLMchatGtk.Tools.Permission.request_user: Tool '%s', chat_widget=%p", 
				request.tool.name, this.chat_widget);
			
			// Send notification if application is available
			if (this.application != null) {
				this.application.send_notification(
					"ollmchat-permission-%u".printf((uint)GLib.get_real_time()),
					new GLib.Notification(request.permission_question)
				);
			}
			
			GLib.debug("OLLMchatGtk.Tools.Permission.request_user: Calling permission_widget.request");
			var response = yield this.chat_widget.permission_widget.request(
					request.permission_question, request.one_time_only);
			GLib.debug("OLLMchatGtk.Tools.Permission.request_user: Got response: %s", response.to_string());
			return response;
		}
	}
}

