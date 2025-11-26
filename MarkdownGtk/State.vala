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

namespace OLLMchat.MarkdownGtk
{
	/**
	 * Represents a single piece of styling in the markdown renderer.
	 * 
	 * Each State represents a single styling element (e.g., italic, bold, paragraph, header).
	 * States manage their own buffer and marks for tag positions.
	 */
	internal class State
	{
		public State? parent { get; private set; }
		public Gee.ArrayList<State> cn { get; private set; default = new Gee.ArrayList<State>(); }
		public StringBuilder buffer { get; private set; default = new StringBuilder(); }
		public Gtk.TextMark? start_outer { get; private set; }
		public Gtk.TextMark? start_inner { get; private set; }
		public Gtk.TextMark? end_inner { get; private set; }
		public Gtk.TextMark? end_outer { get; private set; }
		public string tag_name { get; private set; }
		public Render render { get; private set; }
		
		/**
		 * Creates a new State instance.
		 * 
		 * @param parent The parent state (null for root)
		 * @param tag_name The tag name (e.g., "em", "strong", "h1", "p")
		 * @param render Reference to the top-level Render instance
		 */
		public State(State? parent, string tag_name, Render render)
		{
			this.parent = parent;
			this.tag_name = tag_name;
			this.render = render;
			
			// Create marks for tag positions
			this.create_marks();
			
			// Insert opening tag if tag_name is not empty
			if (this.tag_name != "") {
				this.insert_start_tag();
			}
		}
		
		/**
		 * Creates marks for tracking tag positions in the buffer.
		 */
		private void create_marks()
		{
			Gtk.TextIter iter;
			
			// Get insertion point from parent's end_inner, or use render's end_mark
			if (this.parent != null && this.parent.end_inner != null) {
				this.render.buffer.get_iter_at_mark(out iter, this.parent.end_inner);
			} else if (this.render.end_mark != null) {
				this.render.buffer.get_iter_at_mark(out iter, this.render.end_mark);
			} else {
				this.render.buffer.get_end_iter(out iter);
			}
			
			// Create marks for tag positions
			this.start_outer = this.render.buffer.create_mark(null, iter, true);
			this.start_inner = this.render.buffer.create_mark(null, iter, true);
			this.end_inner = this.render.buffer.create_mark(null, iter, true);
			this.end_outer = this.render.buffer.create_mark(null, iter, true);
		}
		
		/**
		 * Adds text to the current buffer.
		 * 
		 * @param text The text to add
		 */
		public void add_text(string text)
		{
			this.buffer.append(text);
		}
		
		/**
		 * Creates a new child state and sets it as the current state on Render.
		 * 
		 * @param tag The tag name for the new state
		 * @param attributes The attributes string for the tag (e.g., "href=\"...\"")
		 * @return The newly created State
		 */
		public State add_state(string tag, string attributes)
		{
			// Store attributes temporarily - we'll need to pass them to State constructor
			// For now, create state and then set attributes
			var new_state = new StateWithAttributes(this, tag, attributes, this.render);
			this.cn.add(new_state);
			
			// Update render's current_state
			this.render.current_state = new_state;
			
			return new_state;
		}
		
		/**
		 * Closes this state, pops to parent, and updates Render's current_state.
		 */
		public void close_state()
		{
			// Insert accumulated text content first
			if (this.buffer.len > 0) {
				this.insert_content();
			}
			
			// Insert closing tag if tag_name is not empty
			if (this.tag_name != "") {
				this.insert_end_tag();
			}
			
			// Pop to parent or reset to top_state.state
			if (this.parent != null) {
				this.render.current_state = this.parent;
			} else {
				this.render.current_state = this.render.top_state.state;
			}
		}
		
		/**
		 * Inserts the start tag into the buffer.
		 */
		protected virtual void insert_start_tag()
		{
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, this.start_outer);
			
			string tag_str = @"<$(this.tag_name)>";
			
			this.render.buffer.insert_markup(ref iter, tag_str, -1);
			
			// Update start_inner mark to point after the opening tag
			this.render.buffer.get_iter_at_mark(out iter, this.start_outer);
			iter.forward_chars(tag_str.length);
			this.render.buffer.move_mark(this.start_inner, iter);
			this.render.buffer.move_mark(this.end_inner, iter);
		}
		
		/**
		 * Inserts the end tag into the buffer.
		 */
		private void insert_end_tag()
		{
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, this.end_inner);
			
			string tag_str = @"</$(this.tag_name)>";
			this.render.buffer.insert_markup(ref iter, tag_str, -1);
			
			// Update end_outer mark to point after the closing tag
			iter.forward_chars(tag_str.length);
			this.render.buffer.move_mark(this.end_outer, iter);
		}
		
		/**
		 * Inserts the accumulated text content into the buffer.
		 */
		private void insert_content()
		{
			// Insert content before closing tag
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, this.end_inner);
			
			string content = this.buffer.str;
			if (content.length > 0) {
				this.render.buffer.insert(ref iter, content, -1);
				
				// Update end_inner mark to point after the content
				iter.forward_chars(content.length);
				this.render.buffer.move_mark(this.end_inner, iter);
			}
		}
		
		/**
		 * Internal class for states with attributes.
		 */
		private class StateWithAttributes : State
		{
			private string attributes;
			
			public StateWithAttributes(State? parent, string tag_name, string attributes, Render render)
				: base(parent, tag_name, render)
			{
				this.attributes = attributes;
			}
			
			protected override void insert_start_tag()
			{
				Gtk.TextIter iter;
				this.render.buffer.get_iter_at_mark(out iter, this.start_outer);
				
				string tag_str;
				if (this.attributes != "") {
					tag_str = @"<$(this.tag_name) $(this.attributes)>";
				} else {
					tag_str = @"<$(this.tag_name)>";
				}
				
				this.render.buffer.insert_markup(ref iter, tag_str, -1);
				
				// Update start_inner mark to point after the opening tag
				this.render.buffer.get_iter_at_mark(out iter, this.start_outer);
				iter.forward_chars(tag_str.length);
				this.render.buffer.move_mark(this.start_inner, iter);
				this.render.buffer.move_mark(this.end_inner, iter);
			}
		}
	}
}

