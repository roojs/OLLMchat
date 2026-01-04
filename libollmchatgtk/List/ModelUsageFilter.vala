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

namespace OLLMchatGtk.List
{
	/**
	 * Filter for ModelUsage objects by connection URL.
	 * 
	 * Filters ModelUsage items to only show those matching a specific connection URL.
	 * Can be used with Gtk.FilterListModel to filter a ConnectionModels list.
	 * 
	 * @since 1.0
	 */
	public class ModelUsageFilter : Gtk.Filter
	{
		/**
		 * The connection URL to filter by.
		 * When set, only ModelUsage items with matching connection will pass the filter.
		 */
		public string connection_url { get; set; default = ""; }
		
		/**
		 * Constructor.
		 * 
		 * @param connection_url The connection URL to filter by (empty string matches all)
		 */
		public ModelUsageFilter(string connection_url = "")
		{
			Object(connection_url: connection_url);
			
			// Notify filter when connection_url changes
			this.notify["connection-url"].connect(() => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}
		
		/**
		 * Filter match implementation.
		 * 
		 * @param item The item to check
		 * @return true if the item matches the filter, false otherwise
		 */
		public override bool match(Object? item)
		{
			if (this.connection_url == "") {
				return true; // Empty string matches all
			}
			
			var model_usage = item as OLLMchat.Settings.ModelUsage;
			if (model_usage == null) {
				return false;
			}
			
			return model_usage.connection == this.connection_url;
		}
	}
}

