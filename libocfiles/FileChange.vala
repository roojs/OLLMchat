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

namespace OLLMfiles
{
	/**
	 * Represents a single edit operation with range and replacement.
	 * 
	 * Line numbers are 1-based (inclusive start, exclusive end).
	 */
	public class FileChange : Object
	{
		/**
		 * Starting line number (1-based, inclusive).
		 */
		public int start { get; set; default = -1; }
		
		/**
		 * Ending line number (1-based, exclusive).
		 */
		public int end { get; set; default = -1; }
		
		/**
		 * Replacement text to insert at the specified range.
		 */
		public string replacement { get; set; default = ""; }
		
		/**
		 * Old lines that were replaced (for reference/debugging).
		 */
		public Gee.ArrayList<string> old_lines { get; set; default = new Gee.ArrayList<string>(); }
	}
}

