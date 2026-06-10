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

namespace OLLMvector2
{
	/**
	 * One FAISS hit joined with its SQL metadata row.
	 */
	public class SearchHit : Object
	{
		public FaissHit faiss { get; construct; }
		public SQT.VectorMetadata metadata { get; construct; }

		public SearchHit (FaissHit faiss, SQT.VectorMetadata metadata)
		{
			Object (faiss: faiss, metadata: metadata);
		}
	}

	/**
	 * Semantic vector search — returns metadata hits without file snippets.
	 */
	public class Search : VectorBase
	{
		private Database vector_db;
		private SQ.Database sql_db;

		public string query { get; set; default = ""; }
		public uint64 max_results { get; set; default = 10; }

		public Search (
			Database vector_db,
			SQ.Database sql_db,
			OLLMchat.Settings.Config2 config
		)
		{
			base (config);
			this.vector_db = vector_db;
			this.sql_db = sql_db;
		}

		/**
		 * Resolve vector_ids for the given opaque file_ids.
		 */
		public static int64[] vector_ids_for_file_ids (
			SQ.Database sql_db,
			int64[] file_ids
		)
		{
			if (file_ids.length == 0) {
				return new int64[0];
			}

			var id_list = new Gee.ArrayList<string> ();
			foreach (var fid in file_ids) {
				id_list.add (fid.to_string ());
			}

			var rows = new Gee.ArrayList<SQT.VectorMetadata> ();
			SQT.VectorMetadata.query (sql_db).select (
				"WHERE file_id IN (" + string.joinv (",", id_list.to_array ()) + ")",
				rows
			);

			var result = new int64[rows.size];
			for (int i = 0; i < rows.size; i++) {
				result[i] = rows.get (i).vector_id;
			}
			return result;
		}

		public async Gee.ArrayList<SearchHit> execute (
			int64[]? filter_vector_ids = null
		) throws GLib.Error
		{
			var normalized_query = this.normalize_query (this.query);
			if (normalized_query == "") {
				return new Gee.ArrayList<SearchHit> ();
			}

			var faiss_results = yield this.vector_db.search (
				normalized_query,
				this.max_results,
				filter_vector_ids
			);

			if (faiss_results.length == 0) {
				return new Gee.ArrayList<SearchHit> ();
			}

			var vector_ids = new int64[faiss_results.length];
			for (int i = 0; i < faiss_results.length; i++) {
				vector_ids[i] = faiss_results[i].vector_id;
			}

			var metadata_list = SQT.VectorMetadata.lookup_vectors (this.sql_db, vector_ids);
			var metadata_map = new Gee.HashMap<int, SQT.VectorMetadata> ();
			foreach (var metadata in metadata_list) {
				metadata_map.set ((int) metadata.vector_id, metadata);
			}

			var hits = new Gee.ArrayList<SearchHit> ();
			foreach (var faiss_hit in faiss_results) {
				if (faiss_hit.vector_id == -1) {
					continue;
				}
				if (!metadata_map.has_key ((int) faiss_hit.vector_id)) {
					continue;
				}
				hits.add (new SearchHit (faiss_hit, metadata_map.get ((int) faiss_hit.vector_id)));
			}

			return hits;
		}

		private string normalize_query (string query_text)
		{
			var normalized = query_text.strip ();
			normalized = normalized.replace ("\n", " ").replace ("\t", " ");
			while (normalized.contains ("  ")) {
				normalized = normalized.replace ("  ", " ");
			}
			return normalized.strip ();
		}
	}
}
