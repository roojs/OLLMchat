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
		public virtual void add(string text)
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
		 * Starts/initializes the parser for a new block.
		 * 
		 * Resets the parser's internal state. Should be called when beginning a new content block.
		 */
		public void start()
		{
			this.parser.start();
		}
		
		// Callback methods for parser - all must be implemented by subclasses
		
		public abstract void on_text(string text);
		public abstract void on_em(bool is_start);
		public abstract void on_strong(bool is_start);
		public abstract void on_code_span(bool is_start);
		public abstract void on_del(bool is_start);
		public abstract void on_other(bool is_start, string tag_name);
		public abstract void on_html(bool is_start, string tag, string attributes);
		
		// Block-level callbacks (can have default empty implementations)
		public virtual void on_h(bool is_start, uint level) {}
		public virtual void on_p(bool is_start) {}
		public virtual void on_ul(bool is_start, bool is_tight, char mark) {}
		public virtual void on_ol(bool is_start, uint start, bool is_tight, char mark_delimiter) {}
		public virtual void on_li(bool is_start, bool is_task, char task_mark, uint task_mark_offset) {}
		public virtual void on_code(bool is_start, string? lang, char fence_char) {}
		public virtual void on_quote(bool is_start) {}
		public virtual void on_hr() {}
		public virtual void on_a(bool is_start, string href, string title, bool is_autolink) {}
		public virtual void on_img(string src, string? title) {}
		public virtual void on_br() {}
		public virtual void on_softbr() {}
		public virtual void on_entity(string text) {}
		public virtual void on_u(bool is_start) {}
	}
}

