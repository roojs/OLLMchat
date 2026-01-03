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

namespace OLLMchat.SettingsDialog
{
	/**
	 * Base class for settings dialog pages.
	 * 
	 * Provides common functionality for pages including page name/title
	 * and activation/deactivation methods.
	 * 
	 * @since 1.0
	 */
	public class SettingsPage : Gtk.Box
	{
		/**
		 * Page name (used as ViewStack page name)
		 */
		public string page_name { get; construct; default = ""; }

		/**
		 * Page title (used as ViewStack page title and preferences group title)
		 */
		public string page_title { get; construct; default = ""; }

		/**
		 * Action widget for this page (added to action bar area by SettingsDialog).
		 * 
		 * Should be created in constructor. Can be an empty hidden box for pages
		 * that don't need action widgets.
		 */
		public Gtk.Box action_widget { get; protected set; }

		/**
		 * Default constructor for creating dummy instances.
		 */
		public SettingsPage()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			// Create empty hidden action widget for dummy pages
			this.action_widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				visible = false
			};
		}

		/**
		 * Called when this page is activated (becomes visible).
		 * 
		 * Pages should override this to perform actions when they become active,
		 * such as showing/hiding action bars.
		 */
		public virtual void on_activated()
		{
			// Default implementation does nothing
		}

		/**
		 * Called when this page is deactivated (becomes hidden).
		 * 
		 * Pages should override this to perform cleanup when they become inactive,
		 * such as hiding action bars.
		 */
		public virtual void on_deactivated()
		{
			// Default implementation does nothing
		}
	}
}

