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
	 * GTK-specific version of RequestRunCommand that creates SourceView widgets
	 * for displaying terminal output.
	 * 
	 * This class extends Tools.RequestRunCommand and overrides virtual methods
	 * to provide GTK widget support.
	 */
	public class RequestRunCommand : OLLMchat.Tools.RequestRunCommand
	{
		private GtkSource.Buffer? source_buffer = null;
		private GtkSource.View? source_view = null;
		
		public RequestRunCommand()
		{
			base();
		}
		
		/**
		 * Override to create GTK Message with widget support for initial command message.
		 */
		protected override void send_initial_tool_message(string content)
		{
			// Create SourceView widget for terminal output
			this.source_buffer = new GtkSource.Buffer(null);
			this.source_view = new GtkSource.View() {
				editable = false,
				cursor_visible = false,
				show_line_numbers = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false
			};
			this.source_view.set_buffer(this.source_buffer);
			this.source_view.add_css_class("code-editor");
			this.source_view.height_request = 25;
			this.source_view.set_visible(true);
			
			this.chat_call.client.tool_message(
				new OLLMchatGtk.Message(this.chat_call, "ui",
				content, this.source_view)
			);
		}
		
		/**
		 * Override to append message to the widget instead of sending via tool_message.
		 */
		protected override void send_or_append_message(string text)
		{
			if (this.source_buffer == null) {
				return;
			}
			
			Gtk.TextIter end_iter;
			this.source_buffer.get_end_iter(out end_iter);
			
			// If text starts with newline, it's already formatted
			if (text.has_prefix("\n")) {
				this.source_buffer.insert(ref end_iter, text, -1);
			} else {
				// Add newline before text if buffer already has content
				if (this.source_buffer.get_char_count() > 0) {
					this.source_buffer.insert(ref end_iter, "\n", -1);
					this.source_buffer.get_end_iter(out end_iter);
				}
				this.source_buffer.insert(ref end_iter, text, -1);
			}
		}
	}
}
