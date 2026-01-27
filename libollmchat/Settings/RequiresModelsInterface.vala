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

namespace OLLMchat.Settings
{
	/**
	 * Interface for tool configs that require models to be available at startup.
	 * 
	 * Tool configs that implement this interface must provide a list of
	 * ModelUsage objects that need to be available before the app can proceed.
	 * 
	 * @since 1.0
	 */
	public interface RequiresModelsInterface : Object
	{
		/**
		 * Returns a list of ModelUsage objects that must be available at startup.
		 * 
		 * Any ModelUsage objects returned from this method will be checked and
		 * auto-pulled if missing. Return an empty list if no models are required.
		 * 
		 * @return List of required ModelUsage objects
		 */
		public abstract Gee.ArrayList<ModelUsage> required_models();
	}
}
