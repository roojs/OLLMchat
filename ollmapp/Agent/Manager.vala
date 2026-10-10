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

namespace OLLMapp.Agent
{
	/**
	 * Subscribes to the chat shell and decides which section is visible.
	 * The desktop window constructs this after the chat bar and the right
	 * pane exist. This class creates the browser and editor buttons, the
	 * tool toggles, and decides which of those strips is visible. The agent
	 * dropdown stays on the window.
	 *
	 * The browser is shown when {@link OLLMchatGtk.ChatBar.tool_toggle} is
	 * ''browser'' and active, when that tool emits
	 * {@link OLLMchat.Tool.UiWidgets.show_view} while the editor strip is up,
	 * and when {@link OLLMchat.History.Manager.agent_activated} or
	 * {@link OLLMchat.History.Manager.session_restored} fires for an agent
	 * with no editor while the browser page is already the visible child. It
	 * is hidden when that toggle turns off while the editor strip is down,
	 * when an editor agent is activated, and when a non-editor agent is
	 * activated while some other page is visible.
	 *
	 * The editor is shown when those signals fire for a factory whose
	 * {@link OLLMchat.Agent.Factory.has_editor} is true. The page name is
	 * ''{factory}-widget''. It is hidden when
	 * {@link OLLMchat.History.Manager.agent_deactivated} fires for an editor
	 * factory, and when a tool page replaces it.
	 *
	 * Chat, with the side pane hidden, is shown when a tool toggle turns off
	 * while the editor strip is down, when an editor agent is left, and when
	 * a non-editor agent is activated while the browser is not already up. On
	 * a phone the browser or the editor replaces the transcript. A tablet and
	 * the desktop keep the transcript beside the pane.
	 *
	 * {@link OLLMchat.ChatDesktopInterface.notification} method
	 * ''client.filesd.unreachable'' asks Retry or Close. Retry emits
	 * ''client.filesd.retry''. Close starts a Chatter session, which emits
	 * {@link OLLMchat.History.Manager.agent_deactivated} and hides the editor.
	 * Close does not quit.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var manager = new OLLMapp.Agent.Manager(window);
	 * }}}
	 */
	public class Manager : GLib.Object
	{
		/** Main window. It also implements {@link OLLMchat.ChatDesktopInterface}. */
		public ChatUserInterface shell { get; construct; }
		private Gtk.Button browser_picker;
		private Gtk.Button editor_picker;

		public Manager(ChatUserInterface shell)
		{
			Object(shell: shell);

			this.browser_picker = new Gtk.Button() {
				icon_name = "web-browser-symbolic",
				tooltip_text = "Browser"
			};
			this.editor_picker = new Gtk.Button() {
				icon_name = "document-edit-symbolic",
				tooltip_text = "Text editor"
			};
			this.shell.chat_widget.chat_bar.end_box.append(this.browser_picker);
			this.shell.chat_widget.chat_bar.end_box.append(this.editor_picker);
			this.browser_picker.clicked.connect(() => {
				var ui = this.shell.history_manager.tools.get("browser")
					as OLLMchat.Tool.UiWidgets;
				var view = (Gtk.Widget) ui.view_widget;
				var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
				var tabs = (Adw.ViewStack) desktop.tab_view();
				if (tabs.get_child_by_name("browser") == null) {
					tabs.add_named(view, "browser");
				}
				tabs.set_visible_child_name("browser");
				this.schedule_pane_update(true);
			});
			this.editor_picker.clicked.connect(() => {
				var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
				var tabs = (Adw.ViewStack) desktop.tab_view();
				var widget_id = this.shell.history_manager.session.agent_name + "-widget";
				tabs.set_visible_child_name(widget_id);
				this.schedule_pane_update(true);
			});

			this.shell.history_manager.agent_activated.connect(
				this.on_agent_activated);

			this.shell.history_manager.agent_deactivated.connect((factory) => {
				if (!factory.has_editor) {
					return;
				}
				this.schedule_pane_update(false);
			});

			this.shell.history_manager.session_restored.connect(
				this.on_session_restored);

			this.shell.chat_widget.chat_bar.tool_toggle.connect(
				this.on_tool_toggle);
			foreach (var tool in this.shell.history_manager.tools.values) {
				var ui = tool as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					continue;
				}
				var tool_name = tool.name;
				this.shell.chat_widget.chat_bar.add_tool_toggle(
					tool_name, ui.icon_name, ui.tooltip_text);
				ui.show_view.connect(() => {
					this.on_show_view(ui, tool_name);
				});
			}
			this.shell.chat_widget.chat_bar.tool_button_box.visible = false;
			this.shell.chat_widget.chat_bar.end_box.visible = true;
			this.editor_picker.visible = this.shell.history_manager.get_active_agent().has_editor;
			if (this.editor_picker.visible
				&& ((OllmchatWindow) this.shell).window_pane.intended_pane_visible) {
				this.schedule_pane_update(true);
			}

			var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
			desktop.notification.connect((notif) => {
				switch (notif.method) {
					case "client.filesd.unreachable":
						this.on_unavailable();
						break;

					default:
						break;
				}
			});
		}

		/**
		 * Show or hide the desktop right pane on idle, then mark the browser or editor picker.
		 *
		 * @param visible ''true'' to show the pane, ''false'' to hide it
		 */
		public void schedule_pane_update(bool visible)
		{
			var window = (OllmchatWindow) this.shell;
			var pane = window.window_pane;
			pane.intended_pane_visible = visible;
			GLib.Idle.add(() => {
				if (pane.intended_pane_visible) {
					pane.show_right_pane();
					return false;
				}
				pane.hide_right_pane();
				return false;
			});
			this.browser_picker.remove_css_class("picker-on");
			this.editor_picker.remove_css_class("picker-on");
			if (!visible) {
				return;
			}
			if (pane.tab_view.visible_child_name == "browser") {
				this.browser_picker.add_css_class("picker-on");
				return;
			}
			this.editor_picker.add_css_class("picker-on");
		}

		private void on_agent_activated(OLLMchat.Agent.Factory factory)
		{
			this.shell.chat_widget.chat_bar.tool_button_box.visible = false;
			this.shell.chat_widget.chat_bar.end_box.visible = true;
			this.editor_picker.visible = factory.has_editor;
			var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
			var tabs = (Adw.ViewStack) desktop.tab_view();
			if (factory.has_editor) {
				var widget_id = factory.name + "-widget";
				if (tabs.get_child_by_name(widget_id) != null) {
					tabs.set_visible_child_name(widget_id);
				}
				this.schedule_pane_update(true);
				return;
			}
			if (tabs.visible_child_name == "browser") {
				this.schedule_pane_update(true);
				return;
			}
			this.schedule_pane_update(false);
		}

		private void on_session_restored(OLLMchat.History.SessionBase session)
		{
			var name = session.agent_name;
			if (name == "") {
				name = "just-ask";
			}
			var factory = this.shell.history_manager.agent_factories.get(name);
			if (factory == null) {
				factory = this.shell.history_manager.get_active_agent();
			}
			this.on_agent_activated(factory);
		}

		private void on_tool_toggle(string tool_name, bool active)
		{
			if (!this.shell.history_manager.tools.has_key(tool_name)) {
				return;
			}
			var ui = this.shell.history_manager.tools.get(tool_name)
				as OLLMchat.Tool.UiWidgets;
			if (ui == null) {
				return;
			}
			var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
			var tabs = (Adw.ViewStack) desktop.tab_view();
			if (!active) {
				if (this.shell.chat_widget.chat_bar.end_box.visible) {
					return;
				}
				this.schedule_pane_update(false);
				return;
			}
			var view = (Gtk.Widget) ui.view_widget;
			if (tabs.get_child_by_name(tool_name) == null) {
				tabs.add_named(view, tool_name);
			}
			view.visible = true;
			tabs.set_visible_child_name(tool_name);
			this.schedule_pane_update(true);
		}

		private void on_show_view(OLLMchat.Tool.UiWidgets ui, string tool_name)
		{
			if (!this.shell.chat_widget.chat_bar.end_box.visible) {
				this.shell.chat_widget.chat_bar.toggle_active_tool(tool_name, true);
				return;
			}
			var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
			var view = (Gtk.Widget) ui.view_widget;
			var tabs = (Adw.ViewStack) desktop.tab_view();
			if (tabs.get_child_by_name(tool_name) == null) {
				tabs.add_named(view, tool_name);
			}
			tabs.set_visible_child_name(tool_name);
			this.schedule_pane_update(true);
		}

		private void on_unavailable()
		{
			var desktop = (OLLMchat.ChatDesktopInterface) this.shell;
			var alert = new Adw.AlertDialog(
				"Desktop unavailable",
				"The desktop environment is unavailable."
			);
			alert.add_response("close", "Close");
			alert.add_response("retry", "Retry");
			alert.set_response_appearance(
				"retry", Adw.ResponseAppearance.SUGGESTED
			);
			alert.set_close_response("close");
			alert.set_default_response("retry");
			alert.choose.begin((Gtk.Window) this.shell, null, (obj, res) => {
				var response = alert.choose.end(res);
				if (response == "retry") {
					desktop.notification(new OLLMrpc.Notification() {
						method = "client.filesd.retry",
					});
					return;
				}
				if (response != "close") {
					return;
				}
				var empty_session = this.shell.history_manager.create_new_session();
				empty_session.project_path =
					this.shell.history_manager.session.project_path;
				empty_session.agent_name = "chatter";
				this.shell.chat_widget.switch_to_session.begin(empty_session);
			});
		}
	}
}
