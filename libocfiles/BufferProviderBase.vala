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

namespace OLLMfiles
{
	/**
	 * Cached file contents with lines array.
	 */
	private class FileCacheEntry : Object
	{
		public string[] lines { get; set; }
		
		public FileCacheEntry(string[] lines)
		{
			this.lines = lines;
		}
	}
	
	/**
	 * Base class for buffer operations with default no-op implementations.
	 * 
	 * Provides a default implementation that does nothing, allowing
	 * libocfiles to work without GTK dependencies. Concrete implementations
	 * (e.g., in liboccoder) can override these methods to provide actual
	 * buffer functionality.
	 */
	public class BufferProviderBase : Object
	{
		/**
		 * Static hashmap mapping file extensions to language identifiers.
		 */
		private static Gee.HashMap<string, string>? extension_map = null;
		
		/**
		 * Cache of file contents (path => FileCacheEntry with lines array).
		 */
		private Gee.HashMap<string, FileCacheEntry> file_cache { 
			get; set; default = new Gee.HashMap<string, FileCacheEntry>(); }
		
		/**
		 * Initialize the extension map with common file extensions.
		 */
		private static void init_extension_map()
		{
			if (extension_map != null) {
				return;
			}
			
			extension_map = new Gee.HashMap<string, string>();
			
			// Vala
			extension_map.set("vala", "vala");
			extension_map.set("vapi", "vala");
			
			// C/C++
			extension_map.set("c", "c");
			extension_map.set("h", "c");
			extension_map.set("cpp", "cpp");
			extension_map.set("cxx", "cpp");
			extension_map.set("cc", "cpp");
			extension_map.set("hpp", "cpp");
			extension_map.set("hxx", "cpp");
			
			// Python
			extension_map.set("py", "python");
			extension_map.set("pyw", "python");
			extension_map.set("pyi", "python");
			
			// JavaScript/TypeScript
			extension_map.set("js", "javascript");
			extension_map.set("jsx", "javascript");
			extension_map.set("mjs", "javascript");
			extension_map.set("ts", "typescript");
			extension_map.set("tsx", "typescript");
			
			// Java
			extension_map.set("java", "java");
			
			// C#
			extension_map.set("cs", "csharp");
			
			// Go
			extension_map.set("go", "go");
			
			// Rust
			extension_map.set("rs", "rust");
			
			// Ruby
			extension_map.set("rb", "ruby");
			extension_map.set("rake", "ruby");
			
			// PHP
			extension_map.set("php", "php");
			extension_map.set("phtml", "php");
			
			// Swift
			extension_map.set("swift", "swift");
			
			// Kotlin
			extension_map.set("kt", "kotlin");
			extension_map.set("kts", "kotlin");
			
			// Scala
			extension_map.set("scala", "scala");
			extension_map.set("sc", "scala");
			
			// R
			extension_map.set("r", "r");
			extension_map.set("R", "r");
			
			// Shell/Bash
			extension_map.set("sh", "sh");
			extension_map.set("bash", "sh");
			extension_map.set("zsh", "sh");
			
			// Perl
			extension_map.set("pl", "perl");
			extension_map.set("pm", "perl");
			
			// Lua
			extension_map.set("lua", "lua");
			
			// Haskell
			extension_map.set("hs", "haskell");
			extension_map.set("lhs", "haskell");
			
			// Erlang
			extension_map.set("erl", "erlang");
			extension_map.set("hrl", "erlang");
			
			// Elixir
			extension_map.set("ex", "elixir");
			extension_map.set("exs", "elixir");
			
			// Clojure
			extension_map.set("clj", "clojure");
			extension_map.set("cljs", "clojure");
			extension_map.set("cljc", "clojure");
			
			// OCaml
			extension_map.set("ml", "ocaml");
			extension_map.set("mli", "ocaml");
			
			// F#
			extension_map.set("fs", "fsharp");
			extension_map.set("fsi", "fsharp");
			extension_map.set("fsx", "fsharp");
			
			// Dart
			extension_map.set("dart", "dart");
			
			// Objective-C
			extension_map.set("m", "objc");
			extension_map.set("mm", "objc");
			extension_map.set("h", "objc"); // Note: .h can be C or ObjC
			
			// SQL
			extension_map.set("sql", "sql");
			
			// HTML/CSS
			extension_map.set("html", "html");
			extension_map.set("htm", "html");
			extension_map.set("css", "css");
			extension_map.set("scss", "css");
			extension_map.set("sass", "css");
			extension_map.set("less", "css");
			
			// XML
			extension_map.set("xml", "xml");
			extension_map.set("xsl", "xml");
			extension_map.set("xslt", "xml");
			
			// JSON
			extension_map.set("json", "json");
			
			// YAML
			extension_map.set("yaml", "yaml");
			extension_map.set("yml", "yaml");
			
			// Markdown
			extension_map.set("md", "markdown");
			extension_map.set("markdown", "markdown");
			
			// Makefile
			extension_map.set("make", "makefile");
			extension_map.set("Makefile", "makefile");
			extension_map.set("mk", "makefile");
		}
		
		/**
		 * Detect programming language from file extension.
		 * 
		 * @param file The file to detect language for
		 * @return Language identifier (e.g., "vala", "python"), or null if not detected
		 */
		public virtual string? detect_language(File file) 
		{ 
			if (file.path == null || file.path == "") {
				return null;
			}
			
			init_extension_map();
			
			// Extract file extension
			var path = file.path;
			var last_dot = path.last_index_of_char('.');
			if (last_dot < 0 || last_dot >= path.length - 1) {
				return null;
			}
			
			var extension = path.substring(last_dot + 1).down();
			return extension_map.get(extension);
		}
		
		/**
		 * Create a buffer for the file.
		 * 
		 * The buffer should be stored on the file object using set_data/get_data.
		 * 
		 * @param file The file to create a buffer for
		 */
		public virtual void create_buffer(File file) 
		{ 
		}
		
		/**
		 * Get lines array from cache or file.
		 * 
		 * @param file_path The path to the file to load
		 * @return Lines array, or empty array if file cannot be read
		 */
		private string[] get_lines(string file_path)
		{
			// Check cache first
			if (this.file_cache.has_key(file_path)) {
				return this.file_cache.get(file_path).lines;
			}
			string[] ret = {}; 
			// Load from file
			try {
				if (!GLib.FileUtils.test(file_path, GLib.FileTest.EXISTS)) {
					return ret;
				}
				
				string contents;
				GLib.FileUtils.get_contents(file_path, out contents);
				
				var lines_array = contents.split("\n");
				var cache_entry = new FileCacheEntry(lines_array);
				this.file_cache.set(file_path, cache_entry);
				return lines_array;
			} catch (GLib.Error e) {
				GLib.debug("BufferProviderBase.get_lines: Failed to read file %s: %s", file_path, e.message);
				return ret;
			}
		}
		
		/**
		 * Get text from the buffer, optionally limited to a line range.
		 * 
		 * Reads file directly from disk if not in cache, and caches the result.
		 * 
		 * @param file The file to get text from
		 * @param start_line Starting line number (0-based, inclusive)
		 * @param end_line Ending line number (0-based, inclusive), or -1 for all lines
		 * @return The buffer text, or empty string if not available
		 */
		public virtual string get_buffer_text(File file, int start_line = 0, int end_line = -1) 
		{
			
			
			var lines = this.get_lines(file.path);
			
			// Handle line range
			start_line = start_line < 0 ? 0 : start_line;
			end_line = end_line == -1 ? lines.length - 1 : (end_line >= lines.length ? lines.length - 1 : end_line);
			
			if (start_line > end_line) {
				return "";
			}
			
			// Extract lines and join
			return string.joinv("\n", lines[start_line:end_line+1]);
		}
		
		/**
		 * Get the total number of lines in the buffer.
		 * 
		 * @param file The file to get line count for
		 * @return Line count, or 0 if not available
		 */
		public virtual int get_buffer_line_count(File file) 
		{ 
			return 0; 
		}
		
		/**
		 * Get the currently selected text and cursor position.
		 * 
		 * @param file The file to get selection from
		 * @param cursor_line Output parameter for cursor line number
		 * @param cursor_offset Output parameter for cursor character offset
		 * @return Selected text, or empty string if nothing is selected
		 */
		public virtual string get_buffer_selection(
			File file, 
			out int cursor_line, 
			out int cursor_offset) 
		{
			cursor_line = 0;
			cursor_offset = 0;
			return "";
		}
		
		/**
		 * Get the content of a specific line.
		 * 
		 * @param file The file to get line from
		 * @param line Line number (0-based)
		 * @return Line content, or empty string if not available
		 */
		public virtual string get_buffer_line(File file, int line) 
		{ 
			return ""; 
		}
		
		/**
		 * Get the current cursor position.
		 * 
		 * @param file The file to get cursor position from
		 * @param line Output parameter for cursor line number
		 * @param offset Output parameter for cursor character offset
		 */
		public virtual void get_buffer_cursor(File file, out int line, out int offset) 
		{
			line = 0;
			offset = 0;
		}
		
		/**
		 * Check if the file has a buffer.
		 * 
		 * @param file The file to check
		 * @return true if buffer exists, false otherwise
		 */
		public virtual bool has_buffer(File file) 
		{ 
			return false; 
		}
	}
}
