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
	 * Extends State to handle special root state behavior.
	 * 
	 * TopState represents the root state that cannot be closed.
	 * It manages buffer insertion and mark updates for the Render instance.
	 */
	internal class TopState : State
	{
		/**
		 * Creates a new TopState instance.
		 * 
		 * @param render Reference to the Render instance
		 */
		public TopState(Render render)
			: base(null, "", render)
		{
		}
		
		protected override void insert_tags(string attributes)
		{
			Gtk.TextIter iter;
			
			// Get insertion point from render's start_mark (for top state)
			this.render.buffer.get_iter_at_mark(out iter, this.render.start_mark);
			
			// Create marks for tag positions at start point (but don't insert tags)
			this.start_outer = this.render.buffer.create_mark(null, iter, true);
			this.start_inner = this.render.buffer.create_mark(null, iter, true);
			this.end_inner = this.render.buffer.create_mark(null, iter, true);
			this.end_outer = this.render.buffer.create_mark(null, iter, true);
		}
		
		public override void close_state()
		{
			// TopState cannot be closed - reset to top_state
			this.render.current_state = this.render.top_state;
		}
		
		/**
		 * Wraps State.add_text() and updates render's end_mark with state's end_inner.
		 * Also keeps all marks up to date.
		 * 
		 * @param text The text to add
		 */
		public new void add_text(string text)
		{
			base.add_text(text);
			// Update render's end_mark and keep all marks up to date
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, this.end_inner);
			this.render.buffer.move_mark(this.render.end_mark, iter);
			// Keep other marks up to date (end_outer same as end_inner for top state)
			this.render.buffer.move_mark(this.end_outer, iter);
		}
		
		/**
		 * Wraps State.add_state() and updates render's end_mark with state's end_inner.
		 * Also keeps all marks up to date.
		 * 
		 * @param tag The tag name for the new state
		 * @param attributes The attributes string for the tag
		 * @return The newly created State
		 */
		public new State add_state(string tag, string attributes = "")
		{
			var new_state = base.add_state(tag, attributes);
			// Update render's end_mark
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, new_state.end_inner);
			this.render.buffer.move_mark(this.render.end_mark, iter);
			// Update render's start_mark if this is the first state
			if (this.cn.size == 1) {
				this.render.buffer.get_iter_at_mark(out iter, new_state.start_outer);
				this.render.buffer.move_mark(this.render.start_mark, iter);
			}
			// Keep all marks up to date for top state
			this.render.buffer.get_iter_at_mark(out iter, new_state.end_inner);
			this.render.buffer.move_mark(this.end_inner, iter);
			this.render.buffer.move_mark(this.end_outer, iter);
			return new_state;
		}
	}
}

