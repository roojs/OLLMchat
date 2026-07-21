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

namespace OLLMchat.Tool
{
	/**
	 * Optional chrome for a tool: toggle metadata, host view, and show request.
	 *
	 * Implemented only by tools that need UI. {@link view_widget} is
	 * {@link GLib.Object} so {@link OLLMchat} stays GTK-free; the shell
	 * casts to {@code Gtk.Widget}. The shell / {@code ChatBar} owns the
	 * toggle button and visibility — the tool emits {@link show_view}
	 * when the user must see the host.
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class MyTool : BaseTool, UiWidgets {
	 *     public string icon_name { get { return "web-browser-symbolic"; } }
	 *     public string tooltip_text { get { return "Browser"; } }
	 *     public GLib.Object view_widget { get { return this.host; } }
	 *
	 *     void on_challenge() {
	 *         this.show_view();
	 *     }
	 * }
	 * }}}
	 */
	public interface UiWidgets : GLib.Object
	{
		/**
		 * Icon name for the {@code ChatBar} toggle (e.g. web-browser-symbolic).
		 */
		public abstract string icon_name { get; }

		/**
		 * Tooltip for the {@code ChatBar} toggle.
		 */
		public abstract string tooltip_text { get; }

		/**
		 * Host view for this tool.
		 *
		 * Shell casts to {@code Gtk.Widget} and parents it into the desktop
		 * right pane or {@code ChatWidget.view_stack}.
		 */
		public abstract GLib.Object view_widget { get; }

		/**
		 * Tool needs the host visible (e.g. Cloudflare challenge).
		 *
		 * Shell shows the view and sets the matching toggle active.
		 */
		public signal void show_view();
	}
}
