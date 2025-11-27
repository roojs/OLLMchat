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
		 * @param attributes Optional attributes string for the tag (default: "")
		 */
		public State(
			State? parent, 
			string tag_name, 
			Render render, 
			string attributes = "")
		{
			this.parent = parent;
			this.tag_name = tag_name;
			this.render = render;
			
			// Insert both opening and closing tags together (sets up marks)
			this.insert_tags(attributes);
		}
		
		/**
		 * Adds text directly to the text buffer at the current insertion point.
		 * Escapes markup in the text before inserting.
		 * 
		 * @param text The text to add
		 */
		public void add_text(string text)
		{
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, this.end_inner);
			string escaped_text = GLib.Markup.escape_text(text, -1);
			this.render.buffer.insert(ref iter, escaped_text, -1);
			
			// Update end_inner mark to point after the inserted text
			iter.forward_chars(escaped_text.length);
			this.render.buffer.move_mark(this.end_inner, iter);
		}
		
		/**
		 * Creates a new child state and sets it as the current state on Render.
		 * 
		 * @param tag The tag name for the new state
		 * @param attributes Optional attributes string for the tag (default: "")
		 * @return The newly created State
		 */
		public State add_state(string tag, string attributes = "")
		{
			var new_state = new State(this, tag, this.render, attributes);
			this.cn.add(new_state);
			
			// Update render's current_state
			this.render.current_state = new_state;
			
			return new_state;
		}
		
		/**
		 * Closes this state, pops to parent, and updates Render's current_state.
		 * Tags are already inserted when state is created, so we just update state.
		 */
		public virtual void close_state()
		{
			// Pop to parent
			this.render.current_state = this.parent;
		}
		
		/**
		 * Inserts both opening and closing tags into the buffer at the same time.
		 * This ensures the buffer never has an invalid state with only one tag.
		 * Sets up marks for tag positions.
		 * 
		 * @param attributes The attributes string for the tag
		 */
		protected virtual void insert_tags(string attributes)
		{
			Gtk.TextIter iter;
			
			// Get insertion point from parent's end_inner
			this.render.buffer.get_iter_at_mark(out iter, this.parent.end_inner);
			
			// Create marks for tag positions at insertion point
			this.start_outer = this.render.buffer.create_mark(null, iter, true);
			this.start_inner = this.render.buffer.create_mark(null, iter, true);
			this.end_inner = this.render.buffer.create_mark(null, iter, true);
			this.end_outer = this.render.buffer.create_mark(null, iter, true);
			
			// Build opening tag
			string open_tag = (attributes != "") 
				? "<" + this.tag_name + " " + attributes + ">"
				: "<" + this.tag_name + ">";
			
			// Build closing tag
			string close_tag = "</" + this.tag_name + ">";
			
			// Insert both tags together
			this.render.buffer.insert_markup(ref iter, open_tag + close_tag, -1);
			
			// Update marks:
			// start_outer: already set (before opening tag)
			// start_inner: after opening tag
			this.render.buffer.get_iter_at_mark(out iter, this.start_outer);
			iter.forward_chars(open_tag.length);
			this.render.buffer.move_mark(this.start_inner, iter);
			
			// end_inner: before closing tag (where text will be inserted)
			this.render.buffer.move_mark(this.end_inner, iter);
			
			// end_outer: after closing tag
			iter.forward_chars(close_tag.length);
			this.render.buffer.move_mark(this.end_outer, iter);
		}
		
	}
}

