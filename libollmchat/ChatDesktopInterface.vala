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

namespace OLLMchat
{
	/**
	 * Desktop host surface for coder and skill {@link Agent.Factory}
	 * activate / deactivate.
	 *
	 * Implemented by the desktop main window (ollmapp
	 * ''OllmchatWindow''). Factories cast the window to this
	 * interface, then mount GTK chrome via opaque
	 * {@link GLib.Object} returns (cast at the call site). Mid-run
	 * pending messages use {@link MessageQueue} via
	 * {@link chat_message_queue}; enable or disable with
	 * {@link MessageQueue.can_queue}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * public override async void activate(GLib.Object window)
	 * {
	 *     var ui = (OLLMchat.ChatDesktopInterface) window;
	 *     var tabs = (Adw.ViewStack) ui.tab_view();
	 *     tabs.add_named(this.widget, this.name + "-widget");
	 *     ui.schedule_pane_update(true);
	 *     var queue = ui.chat_message_queue();
	 *     queue.items = agent.session.queued_messages;
	 *     queue.can_queue(true);
	 * }
	 * }}}
	 */
	public interface ChatDesktopInterface : GLib.Object
	{
		/**
		 * Active session agent, or ''null'' when none is set.
		 *
		 * @return current {@link Agent.Base}, or ''null''
		 */
		public abstract Agent.Base? session_agent();

		/**
		 * Box above the composer for mounting strip widgets
		 * (skill progress, queue ColumnView host).
		 *
		 * Shell casts to ''Gtk.Box''.
		 *
		 * @return above-input container as {@link GLib.Object}
		 */
		public abstract GLib.Object above_input_widget();

		/**
		 * Pending-queue {@link MessageQueue} owned by the chat
		 * strip.
		 *
		 * Never swap the ColumnView model — assign
		 * {@link MessageQueue.items} only. Emit
		 * {@link MessageQueue.can_queue} to enable or disable
		 * mid-run queuing.
		 *
		 * @return strip {@link MessageQueue}
		 */
		public abstract MessageQueue chat_message_queue();

		/**
		 * Right-pane tab stack.
		 *
		 * Shell casts to ''Adw.ViewStack''.
		 *
		 * @return tab stack as {@link GLib.Object}
		 */
		public abstract GLib.Object tab_view();

		/**
		 * Show or hide the right pane on idle.
		 *
		 * @param visible ''true'' to show the pane, ''false'' to
		 *   hide
		 */
		public abstract void schedule_pane_update(bool visible);

		/**
		 * Daemon ''event.*'' or client ''client.*'' activity for
		 * the status bar.
		 *
		 * @param notif RPC-shaped notification (method + message
		 *   payload)
		 */
		public signal void notification(OLLMrpc.Notification notif);

		/**
		 * Scroll the transcript so the render row for index
		 * ''idx'' is visible.
		 *
		 * @param idx session-local render row index, or negative
		 *   to no-op
		 */
		public abstract void scroll_to_message(int idx);
	}
}
