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
	 * Base class for buffer operations with default no-op implementations.
	 * 
	 * Provides a default implementation that creates DummyFileBuffer instances,
	 * allowing libocfiles to work without GTK dependencies. Concrete implementations
	 * (e.g., in liboccoder) can override create_buffer() to provide GTK buffers.
	 */
	public class BufferProviderBase : Object
	{
		/**
		 * Static hashmap mapping file extensions to language identifiers.
		 */
		private static Gee.HashMap<string, string>? extension_map = null;
		
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
		 * Creates a DummyFileBuffer instance and stores it in file.buffer.
		 * Performs buffer cleanup before creating new buffer (keeps top 10 most recent).
		 * 
		 * @param file The file to create a buffer for
		 */
		public virtual void create_buffer(File file) 
		{
			// Cleanup old buffers before creating new one
			this.cleanup_old_buffers(file);
			
			// Create DummyFileBuffer instance
			var buffer = new DummyFileBuffer(file);
			file.buffer = buffer;
		}
		
		/**
		 * Cleanup old buffers to free memory.
		 * 
		 * Keeps buffers for:
		 * - Open files (is_open == true)
		 * - Top 10 most recently used files (by last_viewed)
		 * 
		 * Sets file.buffer = null for all other files.
		 * 
		 * @param current_file The file currently being accessed (always keeps its buffer)
		 */
		protected void cleanup_old_buffers(File current_file)
		{
			var manager = current_file.manager;
			var files_with_buffers = new Gee.ArrayList<File>();
			
			// Collect all files with buffers
			foreach (var file_base in manager.file_cache.values) {
				if (file_base is File) {
					var file = (File) file_base;
					if (file.buffer != null && file != current_file) {
						files_with_buffers.add(file);
					}
				}
			}
			
			// Filter out open files (keep their buffers)
			var not_open_files = new Gee.ArrayList<File>();
			foreach (var file in files_with_buffers) {
				if (!file.is_open) {
					not_open_files.add(file);
				}
			}
			
			// Sort by last_viewed (most recent first)
			not_open_files.sort((a, b) => {
				if (a.last_viewed > b.last_viewed) return -1;
				if (a.last_viewed < b.last_viewed) return 1;
				return 0;
			});
			
			// Keep top 10, clear buffers for the rest
			for (int i = 10; i < not_open_files.size; i++) {
				not_open_files[i].buffer = null;
			}
		}
	}
}
