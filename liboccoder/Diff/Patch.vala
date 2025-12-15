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
 *
 * This code is based on the diff-match-patch library:
 * Copyright 2018 The diff-match-patch Authors.
 * https://github.com/google/diff-match-patch
 * Licensed under the Apache License, Version 2.0
 */

namespace OLLMcoder.Diff
{
	/**
	 * Patch operation types.
	 */
	public enum PatchOperation {
		ADD,      // Pure addition
		REMOVE,   // Pure removal
		REPLACE   // Remove + Add (replacement)
	}
	
	/**
	 * Represents a patch operation with line numbers.
	 * 
	 * Patches can be:
	 * - ADD: Inserts new_lines at start_line
	 * - REMOVE: Removes old_lines starting at start_line
	 * - REPLACE: Removes old_lines and inserts new_lines at start_line
	 */
	public class Patch : Object
	{
		/**
		 * Operation type: ADD, REMOVE, or REPLACE.
		 */
		public PatchOperation operation { get; set; }
		
		/**
		 * Starting line number (1-based) where the patch applies.
		 */
		public int start_line { get; set; }
		
		/**
		 * Lines to remove (empty array for ADD operations).
		 */
		public string[] old_lines { get; set; }
		
		/**
		 * Lines to add (empty array for REMOVE operations).
		 */
		public string[] new_lines { get; set; }
		
		/**
		 * Constructor.
		 * 
		 * @param op Operation type
		 * @param start_line Starting line number (1-based)
		 * @param old_lines Lines to remove
		 * @param new_lines Lines to add
		 */
		public Patch(PatchOperation op, int start_line, string[] old_lines, string[] new_lines)
		{
			this.operation = op;
			this.start_line = start_line;
			this.old_lines = old_lines;
			this.new_lines = new_lines;
		}
	}
}

