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
 * File and project management namespace.
 * 
 * The OLLMfiles namespace provides file and project management functionality
 * without GTK/git dependencies. This allows the core file system operations
 * to be used in both GUI and non-GUI contexts.
 * 
 * == Core Components ==
 * 
 * === Buffer System ===
 * 
 * The buffer system provides a unified interface for accessing file contents,
 * whether in GUI contexts (using GTK SourceView buffers) or non-GUI contexts
 * (using in-memory buffers).
 * 
 *  * FileBuffer: Interface for file buffer operations
 *  * DummyFileBuffer: In-memory buffer implementation for non-GTK contexts
 *  * BufferProviderBase: Base implementation for non-GTK contexts
 * 
 * === File System ===
 * 
 *  * FileBase: Base class for File and Folder objects
 *  * File: Represents a file in the project
 *  * Folder: Represents a folder/directory in the project
 *  * FileAlias: Represents an alias/symlink to a file or folder
 * 
 * === Project Management ===
 * 
 *  * ProjectManager: Manages projects, files, and folders
 *  * ProjectList: Manages list of projects
 *  * ProjectFiles: Manages files within a project
 *  * ProjectFile: Represents a file within a project context
 * 
 * == Architecture Benefits ==
 * 
 *  * Unified Interface: Same API for GTK and non-GTK contexts
 *  * Type Safety: No set_data/get_data - buffers are properly typed
 *  * Separation of Concerns: GUI code in liboccoder, non-GUI code in libocfiles
 *  * Memory Management: Automatic cleanup of old buffers
 *  * File Tracking: Automatic last_viewed timestamp updates
 *  * Backup System: Automatic backups for database files
 * 
 * == Usage Examples ==
 * 
 * === Reading a File ===
 * 
 * {{{
 * file.manager.buffer_provider.create_buffer(file);
 * var contents = yield file.buffer.read_async();
 * 
 * // Or use convenience method
 * var contents2 = file.get_contents();
 * }}}
 * 
 * === Reading Line Range ===
 * 
 * {{{
 * // User provides 1-based line numbers: lines 10-20
 * int start = 10 - 1;  // Convert to 0-based: 9
 * int end = 20 - 1;    // Convert to 0-based: 19
 * 
 * file.manager.buffer_provider.create_buffer(file);
 * if (!file.buffer.is_loaded) {
 *     yield file.buffer.read_async();
 * }
 * 
 * // Get line range
 * var snippet = file.buffer.get_text(start, end);
 * }}}
 * 
 * === Writing a File ===
 * 
 * {{{
 * file.manager.buffer_provider.create_buffer(file);
 * yield file.buffer.write(new_contents);
 * }}}
 * 
 * == Best Practices ==
 * 
 *  1. Create Buffer First: Call create_buffer() before using buffer methods (no null check needed)
 *  2. Load Before Access: Ensure buffer is loaded (is_loaded == true) before using get_text() or get_line()
 *  3. Use read_async() First: Call read_async() before accessing buffer contents to ensure data is current
 *  4. Handle Errors: Always wrap buffer operations in try-catch blocks
 *  5. Convert Line Numbers: Remember to convert between 1-based (user input) and 0-based (buffer API)
 *  6. Sort Edits: When using apply_edits(), sort changes descending by start line
 *  7. Buffer Cleanup: Don't manually set file.buffer = null unless necessary (cleanup is automatic)
 */
namespace OLLMfiles
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMfiles.
	 */
	internal class NamespaceDoc {}
}

