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

namespace OLLMchatGtk
{
	/**
	 * Manager for clipboard metadata.
	 * 
	 * Stores a ClipboardMetadata interface instance that can be set by
	 * libraries with file editing capabilities (e.g., occoder).
	 * Provides static access for both SourceView (to store) and ChatInput (to retrieve).
	 */
	public class ClipboardManager : Object
	{
		/**
		 * Static clipboard metadata instance.
		 * Set by libraries that provide file editing capabilities (e.g., occoder).
		 */
		public static ClipboardMetadata? metadata { get; set; default = null; }
	}
}

