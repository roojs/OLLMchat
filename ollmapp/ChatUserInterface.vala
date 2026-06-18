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

namespace OLLMapp
{
	/**
	 * Shared chat shell for desktop and Android main windows (ollmapp only).
	 *
	 * Coder pane API for liboccoder is {@link OLLMchat.ChatDesktopInterface}
	 * (desktop window only).
	 */
	public interface ChatUserInterface : GLib.Object
	{
		public abstract OLLMchat.History.Manager history_manager { get; set; }
		public abstract AgentDropdown agent_dropdown { get; set; }
		public abstract OLLMchatGtk.ChatWidget chat_widget { get; set; }

		/** Shared with {@link OLLMchat.ChatDesktopInterface} on desktop. */
		public OLLMchat.Agent.Base? session_agent()
		{
			return this.history_manager.session.agent;
		}

		public void register_default_agents ()
		{
			if (!this.history_manager.agent_factories.has_key("chatter")) {
				this.history_manager.agent_factories.set(
					"chatter", new OLLMchat.Chatter.Factory());
			}
		}

		public void setup_chat_widget (
			Gtk.Application application,
			string permission_config_dir
		)
		{
			this.chat_widget = new OLLMchatGtk.ChatWidget(this.history_manager);
			this.history_manager.permission_provider =
				new OLLMchatGtk.Tools.Permission(
					this.chat_widget,
					permission_config_dir) {
					application = application,
				};
			this.chat_widget.error_occurred.connect((error) => {
				GLib.stderr.printf("Error: %s\n", error);
			});
		}

		public void connect_agent_factory_signals ()
		{
			this.history_manager.agent_activated.connect((factory) => {
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
			});
			this.history_manager.agent_deactivated.connect((factory) => {
				factory.deactivate.begin(this, (obj, res) => {
					factory.deactivate.end(res);
				});
			});
			this.history_manager.session_restored.connect((_session) => {
				var factory = this.history_manager.get_active_agent();
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
			});
		}

		public async void activate_session_and_sync_ui ()
		{
			var active_factory = this.history_manager.get_active_agent();
			active_factory.activate.begin(this, (obj, res) => {
				active_factory.activate.end(res);
			});
			yield this.chat_widget.switch_to_session(
				this.history_manager.session);
			GLib.Idle.add(() => {
				this.history_manager.agent_status_change();
				return false;
			});
		}
	}
}
