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

/**
 * Code indexing namespace.
 *
 * The OLLMvector.Indexing namespace provides components for parsing source code,
 * analyzing code elements, and converting them into vector embeddings for semantic search.
 * The indexing pipeline consists of Tree (tree-sitter parsing), Analysis (LLM-based
 * description generation), and VectorBuilder (embedding creation and storage).
 *
 * == Usage Example ==
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
 */
namespace OLLMvector.Indexing
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMvector.Indexing.
	 */
	internal class NamespaceDoc {}
}

