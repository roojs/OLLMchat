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
	 * Wraps State to handle special root state behavior.
	 * 
	 * TopState represents the root state that cannot be closed.
	 * It manages buffer insertion and mark updates for the Render instance.
	 */
	internal class TopState
	{
		public State state { get; private set; }
		public Render render { get; private set; }
		
		/**
		 * Creates a new TopState instance.
		 * 
		 * @param render Reference to the Render instance
		 */
		public TopState(Render render)
		{
			this.render = render;
			// Create internal State with no tag, no parent
			this.state = new State(null, "", render);
		}
		
		/**
		 * Wraps State.add_text() and updates render's end_mark with state's end_inner.
		 * 
		 * @param text The text to add
		 */
		public void add_text(string text)
		{
			this.state.add_text(text);
			// Update render's end_mark
			if (this.state.end_inner != null) {
				Gtk.TextIter iter;
				this.render.buffer.get_iter_at_mark(out iter, this.state.end_inner);
				this.render.buffer.move_mark(this.render.end_mark, iter);
			}
		}
		
		/**
		 * Wraps State.add_state() and updates render's end_mark with state's end_inner.
		 * 
		 * @param tag The tag name for the new state
		 * @param attributes The attributes string for the tag
		 * @return The newly created State
		 */
		public State add_state(string tag, string attributes)
		{
			var new_state = this.state.add_state(tag, attributes);
			// Update render's end_mark
			if (new_state.end_inner != null) {
				Gtk.TextIter iter;
				this.render.buffer.get_iter_at_mark(out iter, new_state.end_inner);
				this.render.buffer.move_mark(this.render.end_mark, iter);
			}
			// Update render's start_mark if this is the first state
			if (this.state.cn.size == 1 && new_state.start_outer != null) {
				Gtk.TextIter iter;
				this.render.buffer.get_iter_at_mark(out iter, new_state.start_outer);
				this.render.buffer.move_mark(this.render.start_mark, iter);
			}
			return new_state;
		}
		
		/**
		 * No-op - top_state cannot be closed.
		 */
		public void close_state()
		{
			// TopState cannot be closed
		}
	}
}

