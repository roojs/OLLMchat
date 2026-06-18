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
	 * Agent picker for the chat header ({@link Gtk.DropDown} is sealed).
	 *
	 * Construct builds the shell and row factory. Call {@link wire} from
	 * initialize_client after agent factories are registered.
	 */
	public class AgentDropdown : Gtk.Box
	{
		public ChatUserInterface host { get; construct; }

		private Gtk.DropDown dropdown;
		private Gtk.SignalListItemFactory list_factory;

		public uint selected {
			get { return this.dropdown.selected; }
			set { this.dropdown.selected = value; }
		}

		/**
		 * Session restore: return true if this handler sets {@link selected}
		 * (e.g. after async project restore); false to apply index immediately.
		 */
		public signal bool session_selection (
			OLLMchat.History.SessionBase session,
			uint agent_index
		);

		public AgentDropdown (ChatUserInterface host)
		{
			Object(host: host);

			this.list_factory = new Gtk.SignalListItemFactory();
			this.list_factory.setup.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null) {
					return;
				}

				var label = new Gtk.Label("") {
					halign = Gtk.Align.START
				};
				list_item.set_data<Gtk.Label>("label", label);
				list_item.child = label;
			});

			this.list_factory.bind.connect((item) => {
				var list_item = item as Gtk.ListItem;
				if (list_item == null || list_item.item == null) {
					return;
				}
				var agent_factory = list_item.item as OLLMchat.Agent.Factory;
				var label = list_item.get_data<Gtk.Label>("label");
				if (label == null) {
					return;
				}
				label.label = agent_factory.title;
				label.tooltip_text = agent_factory.long_title;
			});

			this.dropdown = new Gtk.DropDown(null, null) {
				hexpand = false
			};
			this.dropdown.set_factory(this.list_factory);
			this.dropdown.set_list_factory(this.list_factory);
			this.append(this.dropdown);
			this.hexpand = false;
		}

		public void wire ()
		{
			var agent_store = new GLib.ListStore(typeof(OLLMchat.Agent.Factory));

			uint selected_index = 0;
			uint i = 0;
			foreach (var factory in this.host.history_manager.agent_factories.values) {
				agent_store.append(factory);
				if (factory.name == this.host.history_manager.session.agent_name) {
					selected_index = i;
				}
				i++;
			}

			this.dropdown.model = agent_store;

			this.dropdown.notify["selected"].connect(() => {
				if (this.dropdown.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}

				var factory = (this.dropdown.model as GLib.ListStore)
					.get_item(this.dropdown.selected)
					as OLLMchat.Agent.Factory;
				this.dropdown.tooltip_text = factory.long_title;

				try {
					if (this.host.history_manager.session.fid == null
					    || this.host.history_manager.session.fid == "") {
						this.host.history_manager.session.activate_agent(
							factory.name);
						return;
					}
					this.host.history_manager.activate_agent(
						this.host.history_manager.session.fid, factory.name);
				} catch (GLib.Error e) {
					GLib.warning(
						"Failed to activate agent '%s': %s",
						factory.name, e.message);
				}
			});

			this.dropdown.selected = selected_index;

			this.host.history_manager.session_activated.connect((session) => {
				var store = this.dropdown.model as GLib.ListStore;
				if (store == null) {
					return;
				}
				var factory = this.host.history_manager.get_active_agent();
				factory.activate.begin(this.host, (obj, res) => {
					factory.activate.end(res);
				});
				uint agent_index = 0;
				for (uint j = 0; j < store.get_n_items(); j++) {
					if (((OLLMchat.Agent.Factory) store.get_item(j)).name
					    == session.agent_name) {
						agent_index = j;
						break;
					}
				}
				if (this.session_selection(session, agent_index)) {
					return;
				}
				this.selected = agent_index;
			});
		}
	}
}
