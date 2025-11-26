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
	 * Parser for markdown text that calls specific callbacks on Render.
	 * 
	 * This is a placeholder implementation. Full parser implementation
	 * will be specified in a separate plan.
	 */
	internal class Parser
	{
		private Render renderer;
		
		/**
		 * Creates a new Parser instance.
		 * 
		 * @param renderer The Render instance to call callbacks on
		 */
		public Parser(Render renderer)
		{
			this.renderer = renderer;
		}
		
		/**
		 * Parses text and calls specific callbacks on Render.
		 * 
		 * @param text The markdown text to parse
		 */
		public void add(string text)
		{
			// Placeholder implementation - full parser will be implemented later
			// For now, just pass text through as plain text
			if (text.length > 0) {
				this.renderer.on_text(text);
			}
		}
	}
}

