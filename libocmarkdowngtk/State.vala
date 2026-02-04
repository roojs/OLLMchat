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
		 * Creates a new State, optionally reusing an existing tag for the same range.
		 *
		 * @param parent Parent state (null for root)
		 * @param render Render instance
		 * @param use_tag If non-null, use this tag instead of creating a new one (marks only)
		 */
		public State(State? parent, Render render, Gtk.TextTag? use_tag = null)
		{
			this.parent = parent;
			this.render = render;
			
			// Skip tag and mark creation for TopState (parent == null)
			// TopState will initialize these in start()
			if (parent == null) {
				// TopState - will be initialized later (properties default to null)
				return;
			}
			this.init_from_parent(parent, use_tag);
		}
		
		/**
		 * Initializes this state's tag and marks in the given buffer.
		 * Used by State (from parent's buffer), TopState.initialize(), and TopState.initialize_for_buffer() (table cells).
		 *
		 * @param buffer The buffer to create tag and marks in
		 * @param insertion_point The TextMark to use as the insertion point for marks
		 * @param use_style If non-null, use this tag; otherwise create a new one
		 */
		internal void init_tags_and_marks(Gtk.TextBuffer buffer, Gtk.TextMark insertion_point, Gtk.TextTag? use_style = null)
		{
			this.style = (use_style != null) ? use_style :
				 buffer.create_tag("style-%u".printf(tag_counter++), null);
			Gtk.TextIter iter;
			buffer.get_iter_at_mark(out iter, insertion_point);
			this.start = buffer.create_mark(null, iter, true);
			this.end = buffer.create_mark(null, iter, true);
		}
		
		private void init_from_parent(State parent, Gtk.TextTag? use_tag = null)
		{
			this.init_tags_and_marks(parent.end.get_buffer(), parent.end, use_tag);
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

			var buf = this.render.current_buffer;
			buf.get_iter_at_mark(out start_iter, this.end);
			buf.insert(ref start_iter, text, -1);
			buf.get_iter_at_mark(out end_iter, this.end);
			buf.apply_tag(this.style, end_iter, start_iter);
			buf.move_mark(this.end, start_iter);

			// Update parent ranges and apply parent tags
			if (this.parent != null) {
				this.parent.update_ranges_from(this);
			}
		}
		
		/**
		 * Creates a child state. If use_tag is non-null, the child reuses that tag for styling.
		 *
		 * @param use_tag Optional existing tag to apply (e.g. shared "link" tag)
		 * @return The new child state
		 */
		public State add_state(Gtk.TextTag? use_tag = null)
		{
			var new_state = new State(this, this.render, use_tag);
			this.cn.add(new_state);
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
		
		/**
		 * Copies style properties from this state to the target state.
		 * Used to restore default formatting when new textviews are created.
		 * 
		 * @param target The target state to copy style properties to
		 */
		public void copy_style_to(State target)
		{
			if (this.style == null || target.style == null) {
				return;
			}
			
			// Copy foreground color using rgba (readable property)
			if (this.style.foreground_set) {
				target.style.foreground_rgba = this.style.foreground_rgba;
			}
			
			// Copy Pango style (italic, etc.)
			if (this.style.style_set) {
				target.style.style = this.style.style;
			}
			
			// Copy other text tag properties as needed
			// (weight, scale, etc. can be added if needed in the future)
		}
		
	}
}

