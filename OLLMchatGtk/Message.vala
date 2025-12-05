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
	 * GTK-specific extension of Message that adds widget support.
	 * 
	 * This class extends OLLMchat.Message to add widget support for UI messages.
	 * Widgets can be attached to "ui" role messages to display interactive
	 * components like terminal views or permission widgets in the chat.
	 * 
	 * @since 1.0
	 */
	public class Message : OLLMchat.Message
	{
		/**
		 * Optional widget to display with this message.
		 * 
		 * For "ui" role messages, this widget will be displayed in the chat view.
		 * Expected to be a Gtk.Widget, but typed as Object? for flexibility.
		 * 
		 * @since 1.0
		 */
		public Gtk.Widget widget;
		
		/**
		 * Creates a new GTK Message instance.
		 * 
		 * @param message_interface The message interface
		 * @param role The message role
		 * @param content The message content
		 * @param thinking Optional thinking content
		 * @param widget Optional widget to display with the message
		 */
		public Message(OLLMchat.ChatContentInterface message_interface, 
			string role, 
			string content,
			 Gtk.Widget widget = null)
		{
			base(message_interface, role, content, "");
			this.widget = widget;
			this.is_ui_visible = false;
			this.is_hidden = true;
		}
	}
}

