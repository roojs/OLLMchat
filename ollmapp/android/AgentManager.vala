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

namespace OLLMapp.Android
{
	/**
	 * Phone and tablet pane for {@link OLLMapp.Agent.Manager}.
	 *
	 * The phone window constructs this after the chat bar exists.
	 * ''is_phone'' is true when the pane replaces the transcript. A tablet
	 * keeps the transcript beside the pane column. This adds the chat
	 * button and the borderless page pickers. The editor button mounts
	 * the active agent's page, then shows it.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var manager = new OLLMapp.Android.AgentManager(window, true);
	 * }}}
	 */
	public class AgentManager : Agent.Manager
	{
		/**
		 * Chat button. The window swaps its icon while a reply is
		 * streaming. Visible only when ''is_phone'' is true.
		 */
		public Gtk.Button chat_picker { get; private set; }

		/**
		 * @param shell main window
		 * @param is_phone ''true'' when the pane replaces the transcript
		 */
		public AgentManager(ChatUserInterface shell, bool is_phone)
		{
			base(shell, is_phone, true);
			this.browser_picker.has_frame = false;
			this.browser_picker.add_css_class("page-picker");
			this.editor_picker.has_frame = false;
			this.editor_picker.add_css_class("page-picker");
			this.chat_picker = new Gtk.Button() {
				icon_name = "chat-message-symbolic",
				tooltip_text = "Chat",
				visible = is_phone,
				has_frame = false
			};
			this.chat_picker.add_css_class("page-picker");
			this.chat_picker.add_css_class("picker-on");
			this.shell.chat_widget.chat_bar.end_box.append(this.chat_picker);
			this.chat_picker.clicked.connect(() => {
				this.schedule_pane_update(false);
			});
		}

		/**
		 * Mount the active agent's page, then show it.
		 *
		 * Activation creates the editor view before the pane opens.
		 */
		protected override void on_editor()
		{
			var factory = this.shell.history_manager.get_active_agent();
			factory.activate.begin(this.shell, (obj, res) => {
				factory.activate.end(res);
				this.schedule_pane_update(true);
			});
		}

		/**
		 * Show the phone stack or the tablet column, then mark pickers.
		 *
		 * A hidden phone pane marks the chat button.
		 *
		 * @param visible ''true'' to show the pane, ''false'' to hide it
		 */
		public override void schedule_pane_update(bool visible)
		{
			var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
			var tabs = (Adw.ViewStack) desktop.tab_view();
			if (this.is_phone) {
				this.shell.chat_widget.view_stack.visible_child_name =
					visible ? "pane" : "chat";
			}
			if (!this.is_phone) {
				tabs.visible = visible;
			}
			this.chat_picker.remove_css_class("picker-on");
			base.schedule_pane_update(visible);
			if (!visible) {
				this.chat_picker.add_css_class("picker-on");
			}
		}
	}
}
