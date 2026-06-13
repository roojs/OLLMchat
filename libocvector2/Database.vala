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
	public class Database : VectorBase
	{
		internal Index? index = null;
		private string filename;

		public static async bool check_required_models_available (OLLMchat.Settings.Config2 config)
		{
			if (!config.tools.has_key ("codebase_search")) {
				return false;
			}
			var tool_config = config.tools.get ("codebase_search") as VectorToolConfig;
			if (tool_config == null || !tool_config.enabled) {
				return false;
			}
			if (!(yield tool_config.embed.verify_model (config))) {
				return false;
			}
			if (!(yield tool_config.analysis.verify_model (config))) {
				return false;
			}
			return true;
		}

		public Database (OLLMchat.Settings.Config2 config, string filename, int dimension) throws GLib.Error
		{
			base (config);
			this.filename = filename;
			if (dimension == 0) {
				return;
			}
			this.index = new Index (this.filename, dimension);
		}

		public int dimension {
			get {
				if (this.index == null) {
					return 0;
				}
				return this.index.dimension;
			}
		}

		public int64 vector_count {
			get {
				if (this.index == null) {
					return 0;
				}
				return (int64) this.index.get_total_vectors ();
			}
		}

		public async int embed_dimension () throws GLib.Error
		{
			var test = yield this.embed ("test");
			if (test.length == 0) {
				throw new GLib.IOError.FAILED ("Failed to get test embedding to determine dimension");
			}
			return test.length;
		}

		public async float[] embed (string text) throws GLib.Error
		{
			var embeddings = yield this.embed_to_float_array ({ text });
			if (embeddings.rows == 0) {
				throw new GLib.IOError.FAILED ("Failed to get embedding");
			}
			return embeddings.get_vector (0);
		}

		public async OLLMchat.Response.FloatArray embed_to_float_array (string[] texts) throws GLib.Error
		{
			if (texts.length == 0) {
				return new OLLMchat.Response.FloatArray (0);
			}

			var connection = yield this.connection ("embed", true);
			var tool_config = this.config.tools.get ("codebase_search") as VectorToolConfig;
			var model_name = yield tool_config.embed.model_obj.customize (connection, tool_config.embed.options);
			var call = new OLLMchat.Call.Embeddings (connection, model_name) {
				input = texts,
				dimensions = -1
			};
			var response = yield call.exec_embedding ();
			if (response.embeddings.rows == 0) {
				throw new GLib.IOError.FAILED ("Failed to get embeddings");
			}
			if (response.embeddings.rows != texts.length) {
				throw new GLib.IOError.FAILED ("Embedding count mismatch");
			}
			return response.embeddings;
		}

		public int64[] add_vectors (OLLMchat.Response.FloatArray vectors) throws GLib.Error
		{
			if (this.index == null) {
				throw new GLib.IOError.FAILED ("Vector database index is not initialized");
			}
			int64 start_id = this.vector_count;
			this.index.add_vectors (vectors);
			var ids = new int64[vectors.rows];
			for (int i = 0; i < vectors.rows; i++) {
				ids[i] = start_id + i;
			}
			return ids;
		}

		public void add_vectors_batch (OLLMchat.Response.FloatArray vectors) throws GLib.Error
		{
			this.add_vectors (vectors);
		}

		public async FaissHit[] search (
			string query,
			uint64 k,
			int64[]? filter_vector_ids = null
		) throws GLib.Error
		{
			if (this.index == null) {
				throw new GLib.IOError.FAILED ("Vector database index is not initialized");
			}

			var query_vector = yield this.embed (query);

			if (filter_vector_ids == null || filter_vector_ids.length == 0) {
				return this.index.search (query_vector, k);
			}

			var filtered = new Gee.ArrayList<int> ();
			foreach (var vid in filter_vector_ids) {
				filtered.add ((int) vid);
			}

			var copy = new Index.create_tmp_hnsw (this.index.dimension);
			uint64 copied = copy.copy_from (this.index, filtered);
			if (copied == 0) {
				return new FaissHit[0];
			}

			uint64 search_k = k;
			if (search_k > copied) {
				search_k = copied;
			}

			return copy.search (query_vector, search_k, null);
		}

		public float[] reconstruct_vector (int64 vector_id) throws GLib.Error
		{
			if (this.index == null) {
				throw new GLib.IOError.FAILED ("Vector database index is not initialized");
			}
			return this.index.reconstruct_vector (vector_id);
		}

		public void save_index () throws GLib.Error
		{
			if (this.index == null) {
				return;
			}
			this.index.save_to_file (this.filename);
		}

		public void reset_index () throws GLib.Error
		{
			if (this.index == null) {
				return;
			}
			var dim = this.index.dimension;
			var index_file = GLib.File.new_for_path (this.filename);
			if (index_file.query_exists ()) {
				index_file.delete ();
			}
			this.index = new Index (this.filename, dim);
		}
	}
}
