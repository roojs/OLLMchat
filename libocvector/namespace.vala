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
 * Vector search and codebase indexing namespace.
 * 
 * The OLLMvector namespace provides semantic codebase search functionality
 * using vector embeddings and FAISS similarity search. It enables finding code
 * elements based on their semantic meaning rather than exact text matches.
 * 
 * == Architecture ==
 * 
 * The library uses a three-layer indexing pipeline:
 * 
 *  1. **Tree Layer**: Parses source code using tree-sitter to extract code elements
 *     (classes, methods, functions, etc.) and creates VectorMetadata objects with
 *     line numbers and documentation ranges.
 * 
 *  2. **Analysis Layer**: Uses LLM to generate one-line descriptions for complex
 *     code elements. Simple elements (enums, basic properties) skip LLM analysis.
 * 
 *  3. **VectorBuilder Layer**: Converts code elements (with descriptions) into
 *     vector embeddings using embedding models, then stores them in FAISS and
 *     metadata in SQLite.
 * 
 * The search process:
 * 
 *  1. Convert search query to vector embedding
 *  2. Perform FAISS similarity search to find similar vectors
 *  3. Lookup metadata (file, line range, element info) from SQLite
 *  4. Extract code snippets from files using buffer system
 *  5. Return formatted results with code citations
 * 
 * == Usage Examples ==
 * 
 * === Setting Up the Database ===
 * 
 * {{{
 * // Register model usage types in config
 * OLLMvector.Database.register_config();
 * OLLMvector.Indexing.Analysis.register_config();
 * 
 * // Setup default model usage if not already configured
 * OLLMvector.Database.setup_embed_usage(config);
 * OLLMvector.Indexing.Analysis.setup_analysis_usage(config);
 * 
 * // Check that required models are available
 * if (!yield OLLMvector.Database.check_required_models_available(config)) {
 *     throw new Error("Required models not available");
 * }
 * 
 * // Create database instance
 * var vector_db = new OLLMvector.Database(
 *     embedding_client,
 *     "/path/to/vector.index",
 *     1024  // embedding dimension
 * );
 * }}}
 * 
 * === Indexing a File ===
 * 
 * {{{
 * // Create indexer with required clients and databases
 * var indexer = new OLLMvector.Indexing.Indexer(
 *     analysis_client,
 *     embed_client,
 *     vector_db,
 *     sql_db,
 *     project_manager
 * );
 * 
 * // Index a file or folder
 * var n = yield indexer.index_filebase(file_or_folder, recurse: true, force: false);
 * }}}
 * 
 * === Performing a Search ===
 * 
 * {{{
 * // Create search instance
 * var search = new OLLMvector.Search.Search(
 *     vector_db,
 *     sql_db,
 *     config,
 *     active_project,
 *     "find authentication logic",
 *     10,  // max_results
 *     new Gee.ArrayList<int>(),  // filtered_vector_ids (empty = search all)
 *     null  // element_type_filter (optional)
 * );
 * 
 * // Execute search
 * var results = yield search.execute();
 * 
 * // Access results
 * foreach (var result in results) {
 *     var file = result.file();
 *     var snippet = result.code_snippet(max_lines: 20);
 *     print(@"Found: $(result.metadata.element_name) in $(file.path)\n");
 * }
 * }}}
 * 
 * === Using Background Scanning ===
 * 
 * {{{
 * // Create background scanner (requires CodebaseSearchTool instance)
 * var scanner = new OLLMvector.BackgroundScan(
 *     codebase_search_tool,
 *     new GitProvider()  // Each thread needs its own instance for thread safety
 * );
 * 
 * // Queue files for indexing (automatically processed in background)
 * scanner.scanFile(file, project);
 * scanner.scanProject(project);
 * 
 * // Monitor progress via signal
 * scanner.scan_update.connect((queue_size, current_file) => {
 *     print(@"Queue: $queue_size, Current: $current_file\n");
 * });
 * }}}
 * 
 * == Best Practices ==
 * 
 *  1. Initialize Database First: Call register_config() and setup methods before creating Database instance
 *  2. Check Models: Always verify required models are available before indexing
 *  3. Incremental Indexing: Use force=false to skip unchanged files (checks last_modified timestamp)
 *  4. Background Processing: Use BackgroundScan for automatic indexing of changed files
 *  5. Filter Results: Use element_type and language filters to narrow search results
 *  6. Thread Safety: Database operations are thread-safe (FAISS via mutex, SQLite in SERIALIZED mode)
 *  7. Error Handling: Always wrap indexing and search operations in try-catch blocks
 */
namespace OLLMvector
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMvector.
	 */
	internal class NamespaceDoc {}
}

