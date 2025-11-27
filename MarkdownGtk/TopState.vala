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
	public class TopState : State
	{
		/**
		 * Creates a new TopState instance.
		 * 
		 * @param render Reference to the Render instance
		 */
		public TopState(Render render) 
		{
			base(null, render);
		}
		
		public override void close_state()
		{
			// TopState cannot be closed - reset to top_state
			this.render.current_state = this.render.top_state;
		}
		
		/**
		 * Wraps State.add_text() and updates render's end_mark with state's end.
		 * 
		 * @param text The text to add
		 */
		public new void add_text(string text)
		{
			base.add_text(text);
			// Update render's end_mark
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, this.end);
			this.render.buffer.move_mark(this.render.end_mark, iter);
		}
		
		/**
		 * Wraps State.add_state() and updates render's end_mark with state's end.
		 * 
		 * @return The newly created State
		 */
		public new State add_state()
		{
			var new_state = base.add_state();
			// Update render's end_mark
			Gtk.TextIter iter;
			this.render.buffer.get_iter_at_mark(out iter, new_state.end);
			this.render.buffer.move_mark(this.render.end_mark, iter);
			// Update render's start_mark if this is the first state
			if (this.cn.size == 1) {
				this.render.buffer.get_iter_at_mark(out iter, new_state.start);
				this.render.buffer.move_mark(this.render.start_mark, iter);
			}
			return new_state;
		}
	}
}

