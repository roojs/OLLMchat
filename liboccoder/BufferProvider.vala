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

namespace OLLMcoder
{
	/**
	 * GTK implementation of buffer provider for File operations.
	 */
	public class BufferProvider : OLLMfiles.BufferProviderBase
	{
		public override string? detect_language(OLLMfiles.File file)
		{
			var lang_manager = GtkSource.LanguageManager.get_default();
			var language = lang_manager.guess_language(file.path, null);
			return language?.get_id();
		}
		
		public override void create_buffer(OLLMfiles.File file)
		{
			// Cleanup old buffers before creating new one
			this.cleanup_old_buffers(file);
			
			// Get language object if available
			GtkSource.Language? language = null;
			if (file.language != null && file.language != "") {
				language = GtkSource.LanguageManager.get_default().get_language(file.language);
			}
			
			// Create GtkSourceFileBuffer (extends GtkSource.Buffer directly)
			var buffer = new GtkSourceFileBuffer(file, language);
			file.buffer = buffer;
		}
	}
}
