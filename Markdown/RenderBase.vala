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

namespace OLLMchat.Markdown
{
	/**
	 * Base abstract class for renderers that use the Parser.
	 * 
	 * Provides parser setup and callback interface without requiring
	 * buffer or mark functionality. Subclasses implement the callback
	 * methods to handle parsed content.
	 */
	public abstract class RenderBase : Object
	{
		public Parser parser { get; private set; }
		
		/**
		 * Creates a new RenderBase instance.
		 */
		protected RenderBase()
		{
			// Create parser instance
			this.parser = new Parser(this);
		}
		
		/**
		 * Main method: adds text to be parsed and rendered.
		 * 
		 * @param text The markdown text to process
		 */
		public void add(string text)
		{
			this.parser.add(text);
		}
		
		/**
		 * Finalizes the current chunk. Call this before starting a new chunk with add_start
		 * to ensure all pending content is processed.
		 */
		public void flush()
		{
			this.parser.flush();
		}
		
		/**
		 * Starts a new chunk of content. This resets the parser's internal state and
		 * should be called when beginning a new content block.
		 * 
		 * @param text The markdown text to process
		 * @param is_end_of_chunks If true, format markers at the end are treated as definitive
		 */
		public void add_start(string text, bool is_end_of_chunks = false)
		{
			this.parser.add_start(text, is_end_of_chunks);
		}
		
		// Callback methods for parser - all must be implemented by subclasses
		
		public abstract void on_text(string text);
		public abstract void on_em();
		public abstract void on_strong();
		public abstract void on_code_span();
		public abstract void on_del();
		public abstract void on_other(string tag_name);
		public abstract void on_html(string tag, string attributes);
		public abstract void on_end();
		
		// Block-level callbacks (can have default empty implementations)
		internal virtual void on_h(uint level) {}
		internal virtual void on_p() {}
		internal virtual void on_ul(bool is_tight, char mark) {}
		internal virtual void on_ol(uint start, bool is_tight, char mark_delimiter) {}
		internal virtual void on_li(bool is_task, char task_mark, uint task_mark_offset) {}
		internal virtual void on_code(string? lang, char fence_char) {}
		internal virtual void on_quote() {}
		internal virtual void on_hr() {}
		internal virtual void on_a(string href, string title, bool is_autolink) {}
		internal virtual void on_img(string src, string? title) {}
		internal virtual void on_br() {}
		internal virtual void on_softbr() {}
		public virtual void on_entity(string text) {}
		internal virtual void on_u() {}
	}
}

