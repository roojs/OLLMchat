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

/**
 * GTK-based code editor components namespace.
 * 
 * The OLLMcoder namespace provides GTK-based code editor components that extend
 * the functionality provided by OLLMfiles with GUI-specific features.
 * 
 * == Core Components ==
 * 
 * === Buffer System ===
 * 
 *  * GtkSourceFileBuffer: GTK SourceView buffer implementation for GUI contexts
 *  * BufferProvider: GTK implementation for GUI contexts
 * 
 * === UI Components ===
 * 
 *  * SourceView: GTK SourceView widget wrapper for displaying and editing code
 *  * FileDropdown: Dropdown widget for selecting files
 *  * ProjectDropdown: Dropdown widget for selecting projects
 *  * SearchableDropdown: Base class for searchable dropdown widgets
 * 
 * === Git Integration ===
 * 
 *  * GitProvider: GTK implementation of git operations
 * 
 * === Code Assistant ===
 * 
 *  * CodeAssistant: Code assistant functionality
 *  * CodeAssistantProvider: Provider for code assistant services
 * 
 * == Buffer System ==
 * 
 * The buffer system in OLLMcoder extends the base buffer system from OLLMfiles
 * with GTK-specific features:
 * 
 * === GtkSourceFileBuffer ===
 * 
 * GTK SourceView buffer implementation that:
 * 
 *  * Extends GtkSource.Buffer directly
 *  * Provides syntax highlighting via GtkSource.Language
 *  * Tracks file modification time and auto-reloads if file changed on disk
 *  * Supports cursor position and text selection
 *  * Integrates with GTK SourceView widgets
 * 
 * === BufferProvider ===
 * 
 * GTK implementation that:
 * 
 *  * Uses GtkSource.LanguageManager to detect language
 *  * Creates GtkSourceFileBuffer instances
 *  * Performs same buffer cleanup as BufferProviderBase
 * 
 * == When to Use ==
 * 
 * Use OLLMcoder components when:
 * 
 *  * Working in GUI context (GTK application)
 *  * Need syntax highlighting
 *  * Need cursor position tracking
 *  * Need text selection support
 *  * Working with SourceView widgets
 *  * Need auto-reload when file changes on disk
 * 
 * == Usage Examples ==
 * 
 * === Working with GTK Buffers ===
 * 
 * {{{
 * // Cast to GtkSourceFileBuffer for GTK-specific features
 * if (file.buffer is GtkSourceFileBuffer) {
 *     var gtk_buffer = (GtkSourceFileBuffer) file.buffer;
 *     
 *     // Access underlying GtkSource.Buffer
 *     var source_buffer = (GtkSource.Buffer) gtk_buffer;
 *     
 *     // Use GTK-specific features
 *     source_buffer.set_highlight_syntax(true);
 *     
 *     // Sync to file (for auto-save)
 *     yield gtk_buffer.sync_to_file();
 * }
 * }}}
 * 
 * == Architecture ==
 * 
 * OLLMcoder extends OLLMfiles with GUI-specific functionality while maintaining
 * the same unified interface. This allows code to work seamlessly in both GUI
 * and non-GUI contexts, with the appropriate buffer implementation selected
 * automatically based on the BufferProvider in use.
 */
namespace OLLMcoder
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMcoder.
	 */
	internal class NamespaceDoc {}
}

