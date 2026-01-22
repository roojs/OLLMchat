/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * WITHOUT ANY WARRANTY; without even the implied warranty of
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
	 * History browser widget that displays a list of past chat sessions.
	 * 
	 * Uses Gtk.ListView to display sessions with title, model, reply count, and date.
	 * Automatically updates when new sessions are added via Manager signals.
	 * 
	 * @since 1.0
	 */
	public class HistoryBrowser : Gtk.Box
	{
		private OLLMchat.History.Manager manager;
		private Gtk.SortListModel sorted_store;
		private Gtk.ListView list_view;
		public Gtk.ScrolledWindow scrolled_window { get; set; }
		private bool changing_selection = false;
		private bool is_loading = false;
		
		/**
		 * Signal emitted when a session is selected.
		 * 
		 * @param session The selected SessionBase object (Session or SessionPlaceholder)
		 * @since 1.0
		 */
		public signal void session_selected(OLLMchat.History.SessionBase session);
		
		/**
		 * Signal emitted when a chat is deleted.
		 * 
		 * @param session_id The session ID that was deleted
		 * @since 1.0
		 */
		public signal void chat_deleted(string session_id);
		
		/**
		 * Creates a new HistoryBrowser instance.
		 * 
		 * @param manager The History Manager instance to use
		 * @since 1.0
		 */
		public HistoryBrowser(OLLMchat.History.Manager manager)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.manager = manager;
			
			// Use manager.sessions directly as ListModel (SessionList implements GLib.ListModel)
			// Create SortListModel that wraps manager.sessions and sorts by updated_at_timestamp DESC
			this.sorted_store = new Gtk.SortListModel(this.manager.sessions,
				new Gtk.CustomSorter((a, b) => {
					var aa = a as OLLMchat.History.SessionBase;
					var bb = b as OLLMchat.History.SessionBase;
					if (aa.updated_at_timestamp == bb.updated_at_timestamp) {
						return Gtk.Ordering.EQUAL;
					}
					return aa.updated_at_timestamp > bb.updated_at_timestamp ? 
						Gtk.Ordering.SMALLER : Gtk.Ordering.LARGER;
				})
			);
			
			// Create ListView with selection model using the sorted store
			var selection_model = new Gtk.SingleSelection(this.sorted_store) {
				autoselect = false,
				can_unselect = true,
				selected = Gtk.INVALID_LIST_POSITION
			};
			this.list_view = new Gtk.ListView(selection_model, null);
			
			// Create row factory
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((item) => {
				this.on_setup_row(item as Gtk.ListItem);
			});
			factory.bind.connect((item) => {
				this.on_bind_row(item as Gtk.ListItem);
			});
			
			this.list_view.factory = factory;
			
			// Connect selection changed signal
			selection_model.selection_changed.connect(() => {
				if (this.changing_selection) {
					return;
				}
				var position = selection_model.selected;
				if (position != Gtk.INVALID_LIST_POSITION) {
					// Use sorted_store to get the item at the selected position
					var session = this.sorted_store.get_item(position) as OLLMchat.History.SessionBase;
					
					this.session_selected(session);
					
				}
			});
			
			// Create ScrolledWindow and add ListView to it
			this.scrolled_window = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true
			};
			this.scrolled_window.set_child(this.list_view);
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			
			// Add ScrolledWindow to this Box
			this.append(this.scrolled_window);
			
			// Connect to sorted_store's items_changed signal (for selection/scrolling when new sessions are added)
			// Since sessions are sorted by updated_at_timestamp DESC, new sessions appear at position 0
			this.sorted_store.items_changed.connect(this.on_items_changed);
			
			// Load sessions asynchronously
			this.load_sessions_async.begin();
		}
		
		/**
		 * Setup callback for row factory - creates the widget structure.
		 */
		private void on_setup_row(Gtk.ListItem item)
		{
			var list_item = item as Gtk.ListItem;
			if (list_item == null) {
				return;
			}
			
			// Create vertical box for the row
			var row_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8
			};
			
			// Title label (primary text) - using body text size instead of title-4
			var title_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END,
				css_classes = {"body", "list-chat-title"}
			};
			
			// Secondary line box (horizontal)
			var secondary_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			
			// Model and reply count label (left side, small, grey)
			var info_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				hexpand = false,  // Don't expand - only take needed space
				css_classes = {"list-chat-model", "caption", "dim-label"}
			};
			
			// Create unread label (visibility controlled by property binding)
			var unread_label = new Gtk.Label("unread") {
				halign = Gtk.Align.START,
				hexpand = false,  // Don't expand - only take needed space
				css_classes = {"list-chat-unread", "caption"}
			};
			
			// Spinner widget for running state (between info and date)
			var spinner = new Gtk.Spinner() {
				halign = Gtk.Align.CENTER,
				visible = false,  // Hidden by default
				spinning = false,
				hexpand = false  // Don't expand
			};
			
			// Spacer to push date to the right
			var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true  // Expand to fill available space
			};
			
			// Date label (right side, small, grey)
			var date_label = new Gtk.Label("") {
				halign = Gtk.Align.END,
				hexpand = false,  // Don't expand - only take needed space
				css_classes = {"list-chat-date", "caption", "dim-label"}
			};
			
			secondary_box.append(info_label);
			secondary_box.append(unread_label);  // Add unread label after info_label
			secondary_box.append(spinner);  // Add spinner after unread_label
			secondary_box.append(spacer);  // Spacer pushes date to the right
			secondary_box.append(date_label);
			
			row_box.append(title_label);
			row_box.append(secondary_box);
			
			// Store widget references
			list_item.set_data<Gtk.Box>("row_box", row_box);
			list_item.set_data<Gtk.Label>("title_label", title_label);
			list_item.set_data<Gtk.Label>("info_label", info_label);
			list_item.set_data<Gtk.Label>("date_label", date_label);
			list_item.set_data<Gtk.Label>("unread_label", unread_label);
			list_item.set_data<Gtk.Spinner>("spinner", spinner);  // Store spinner reference
			
			list_item.child = row_box;
		}
		
		/**
		 * Bind callback for row factory - binds widget properties to SessionBase properties.
		 */
		private void on_bind_row(Gtk.ListItem item)
		{
			var list_item = item as Gtk.ListItem;
			if (list_item == null || list_item.item == null) {
				return;
			}
			
			var session = list_item.item as OLLMchat.History.SessionBase;
			if (session == null) {
				return;
			}
			
			// Retrieve widgets
			var row_box = list_item.get_data<Gtk.Box>("row_box");
			var title_label = list_item.get_data<Gtk.Label>("title_label");
			var info_label = list_item.get_data<Gtk.Label>("info_label");
			var date_label = list_item.get_data<Gtk.Label>("date_label");
			var unread_label = list_item.get_data<Gtk.Label>("unread_label");
			var spinner = list_item.get_data<Gtk.Spinner>("spinner");
			
			if (row_box == null || title_label == null || info_label == null || 
			    date_label == null || unread_label == null || spinner == null) {
				return;
			}
			
			// Bind properties using SYNC_CREATE to set initial values
			session.bind_property("display_title", title_label, "label", BindingFlags.SYNC_CREATE);
			session.bind_property("display_title", title_label, "tooltip-text", BindingFlags.SYNC_CREATE);
			session.bind_property("display_info", info_label, "label", BindingFlags.SYNC_CREATE);
			session.bind_property("display_date", date_label, "label", BindingFlags.SYNC_CREATE);
			
			// Bind css_classes to row_box widget classes
			session.bind_property("css_classes", row_box, "css-classes", BindingFlags.SYNC_CREATE);
			
			// Bind has_unread to unread_label visibility (replaces CSS visibility which GTK doesn't support)
			session.bind_property("has_unread", unread_label, "visible", BindingFlags.SYNC_CREATE);
			
			// Bind is_running to spinner visibility and spinning state
			session.bind_property("is_running", spinner, "visible", BindingFlags.SYNC_CREATE);
			session.bind_property("is_running", spinner, "spinning", BindingFlags.SYNC_CREATE);
		}
		
		
		/**
		 * Load sessions asynchronously from manager.
		 */
		private async void load_sessions_async()
		{
			SourceFunc callback = load_sessions_async.callback;
			
			// Set loading flag to prevent on_items_changed from selecting items during initial load
			this.is_loading = true;
			
			// Use Idle to defer loading to avoid blocking UI
			Idle.add(() => {
				// Load sessions from database (populates manager.sessions directly)
				this.manager.load_sessions();
				
				// Sessions are now in manager.sessions, which is used directly by the ListView
				// No need to copy - SessionList implements ListModel
				
				// Explicitly set selection to invalid to ensure nothing is selected on initial load
				this.changing_selection = true;
				var selection = this.list_view.model as Gtk.SingleSelection;
				selection.selected = Gtk.INVALID_LIST_POSITION;
				this.changing_selection = false;
				
				// Clear loading flag after initial load is complete
				this.is_loading = false;
				
				callback();
				return false;
			});
			
			yield;
		}
		
		/**
		 * Handler for sorted_store's items_changed signal.
		 * 
		 * Called when items are added, removed, or changed in the sorted list.
		 * When a new session is added at position 0 (after sorting by updated_at_timestamp DESC),
		 * we select it and scroll to top.
		 * 
		 * @param position The position where the change occurred
		 * @param removed The number of items removed
		 * @param added The number of items added
		 */
		private void on_items_changed(uint position, uint removed, uint added)
		{
			// Don't auto-select during initial load - we want no selection on startup
			if (this.is_loading) {
				return;
			}
			
			// Only handle additions at position 0 (new sessions appear at top after sorting)
			if (position != 0 || added == 0) {
				return;
			}
			
			// Use Idle to defer selection, giving time for title to be set
			Idle.add(() => {
				// Set selection to the new session (at position 0)
				this.changing_selection = true;
				var selection = this.list_view.model as Gtk.SingleSelection;
				selection.selected = 0;
				
				// Scroll to top
				this.scrolled_window.vadjustment.value = 0;
				
				this.changing_selection = false;
				return false;
			});
		}
	}
}

