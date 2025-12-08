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

namespace MarkdownGtk
{
	/**
	 * Represents a single piece of styling in the markdown renderer.
	 * 
	 * Each State represents a single styling element (e.g., italic, bold, paragraph, header).
	 * States manage their own buffer and marks for tag positions.
	 */
	public class State
	{
		internal static uint tag_counter = 0;
		
		public State? parent { get; private set; }
		public Gee.ArrayList<State> cn { get; private set; default = new Gee.ArrayList<State>(); }
		protected Gtk.TextMark? start { public get; set; default = null; }
		protected Gtk.TextMark? end { get; set; default = null; }
		public Gtk.TextTag? style { get; protected set; default = null; }
		public Render render { get; private set; }
		
		/**
		 * Creates a new State instance.
		 * 
		 * @param parent The parent state (null for root)
		 * @param render Reference to the top-level Render instance
		 */
		public State(
			State? parent, 
			Render render)
		{
			this.parent = parent;
			this.render = render;
			
			// Skip tag and mark creation for TopState (parent == null)
			// TopState will initialize these in start()
			if (parent == null) {
				// TopState - will be initialized later (properties default to null)
				return;
			}
		 
			// Initialize tag and marks from parent's end mark
			this.initialize_from_parent(parent);
		}
		
		/**
		 * Initializes this state's tag and marks.
		 * Can be called from State constructor or from Render for TopState.
		 * 
		 * @param insertion_point The TextMark to use as the insertion point for marks
		 */
		internal void initialize_tag_and_marks(Gtk.TextMark insertion_point)
		{
			// Generate unique tag name and create TextTag
			this.style = this.render.current_buffer.create_tag("style-%u".printf(tag_counter++), null);
			
			// Create marks at insertion point
			Gtk.TextIter iter;
			this.render.current_buffer.get_iter_at_mark(out iter, insertion_point);
			
			this.start = this.render.current_buffer.create_mark(null, iter, true);
			this.end = this.render.current_buffer.create_mark(null, iter, true);
		}
		
		/**
		 * Initializes this state's tag and marks from parent's end mark.
		 * Used by regular State instances (not TopState).
		 */
		private void initialize_from_parent(State parent)
		{
			this.initialize_tag_and_marks(parent.end);
		}
		
		/**
		 * Updates this state's end range to match the child's end and applies this state's tag.
		 * Also recursively updates parent states.
		 * 
		 * @param child The child state whose range should be included
		 */
		protected virtual void update_ranges_from(State child)
		{
			Gtk.TextIter child_end, this_start, this_end;
			
			// Get child's end position
			this.render.current_buffer.get_iter_at_mark(out child_end, child.end);
			
			// Update end mark to match child's end
			this.render.current_buffer.move_mark(this.end, child_end);
			
			// Get this state's range
			this.render.current_buffer.get_iter_at_mark(out this_start, this.start);
			this.render.current_buffer.get_iter_at_mark(out this_end, this.end);
			
			// Apply this state's tag to its own range
			this.render.current_buffer.apply_tag(this.style, this_start, this_end);
			
			// Recursively update parent
			if (this.parent != null) {
				this.parent.update_ranges_from(this);
			}
		}
		
		/**
		 * Adds text directly to the text buffer at the current insertion point.
		 * Inserts plain text and applies the TextTag to the inserted range.
		 * 
		 * @param text The text to add
		 */
		public void add_text(string text)
		{
			Gtk.TextIter start_iter, end_iter;
		 // Validate UTF-8
		 

			// Get start position from mark (before insertion)
			this.render.current_buffer.get_iter_at_mark(out start_iter, this.end);
			
			// Insert plain text (no escaping needed - TextBuffer handles it)
			// After insert, start_iter is updated to point after the inserted text
			this.render.current_buffer.insert(ref start_iter, text, -1);
			
			// Get the start position again from the mark (which hasn't moved yet)
			// This ensures we have a valid iter for the start of the inserted range
			this.render.current_buffer.get_iter_at_mark(out end_iter, this.end);
			
			// Apply this state's tag to the inserted text range
			this.render.current_buffer.apply_tag(this.style, end_iter, start_iter);
			
			// Update end mark to point after the inserted text
			this.render.current_buffer.move_mark(this.end, start_iter);
			
			// Update parent ranges and apply parent tags
			if (this.parent != null) {
				this.parent.update_ranges_from(this);
			}
		}
		
		/**
		 * Creates a new child state and sets it as the current state on Render.
		 * 
		 * @return The newly created State
		 */
		public State add_state()
		{
			var new_state = new State(this, this.render);
			this.cn.add(new_state);
			
			// Update render's current_state
			this.render.current_state = new_state;
			
			return new_state;
		}
		
		/**
		 * Closes this state, pops to parent, and updates Render's current_state.
		 */
		public virtual void close_state()
		{
			// Pop to parent
			this.render.current_state = this.parent;
		}
		
	}
}

