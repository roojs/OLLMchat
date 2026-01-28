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
 * Vector search namespace.
 *
 * The OLLMvector.Search namespace provides semantic codebase search functionality
 * using FAISS vector similarity search. Converts search queries to embeddings,
 * performs similarity search, and returns results with code snippets extracted
 * from source files.
 *
 * == Usage Example ==
 *
 * {{{
 * // Create search instance
 * var search = new OLLMvector.Search.Search(
 *     vector_db,
 *     sql_db,
 *     config,
 *     active_project,
 *     "find authentication logic",
 *     new Gee.ArrayList<int>()  // filtered_vector_ids (empty = search all)
 * ) {
 *     max_results = 20,
 *     element_type_filter = "method",
 *     category_filter = "documentation"
 * };
 * var results = yield search.execute();
 *
 * // Access results
 * foreach (var result in results) {
 *     var file = result.file();
 *     var snippet = result.code_snippet(max_lines: 20);
 *     print(@"Found: $(result.metadata.element_name) in $(file.path)\n");
 * }
 * }}}
 */
namespace OLLMvector.Search
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMvector.Search.
	 */
	internal class NamespaceDoc {}
}

