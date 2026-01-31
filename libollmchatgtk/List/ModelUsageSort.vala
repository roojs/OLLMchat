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

namespace OLLMchatGtk.List
{
	/**
	 * Sorter for ModelUsage objects by model family name.
	 * 
	 * Sorts ModelUsage items by extracting the family name from prefixed model names.
	 * For example, "user/llama3" -> "llama3", otherwise uses the full name.
	 * Performs case-insensitive alphabetical sorting.
	 * 
	 * Can be used with Gtk.SortListModel to sort a ConnectionModels list.
	 * 
	 * @since 1.0
	 */
	public class ModelUsageSort : Gtk.Sorter
	{
		/**
		 * Constructor.
		 */
		public ModelUsageSort()
		{
			Object();
		}
		
		/**
		 * Compare two items for sorting by display name (base + size + [variant] + optional ctx).
		 * 
		 * @param a First item to compare
		 * @param b Second item to compare
		 * @return Ordering indicating the relationship between a and b
		 */
		public override Gtk.Ordering compare(Object? a, Object? b)
		{
			var model_usage_a = a as OLLMchat.Settings.ModelUsage;
			var model_usage_b = b as OLLMchat.Settings.ModelUsage;
			
			if (model_usage_a == null || model_usage_b == null) {
				return Gtk.Ordering.EQUAL;
			}
			// Same (connection, model) means same model – equal for matching (e.g. find_position)
			if (model_usage_a.connection == model_usage_b.connection
				 && model_usage_a.model == model_usage_b.model) {
				return Gtk.Ordering.EQUAL;
			}
			int cmp = strcmp(
				model_usage_a.display_name_with_size().down(),
				model_usage_b.display_name_with_size().down()
			);
			if (cmp < 0) {
				return Gtk.Ordering.SMALLER;
			} else if (cmp > 0) {
				return Gtk.Ordering.LARGER;
			} else {
				return Gtk.Ordering.EQUAL;
			}
		}
	}
}

