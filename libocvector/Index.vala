namespace OLLMvector
{
	/**
	 * Represents a single search result from FAISS similarity search.
	 * 
	 * Contains the vector ID, distance (similarity score), and rank
	 * (position in results, 1-based).
	 */
	public struct SearchResult
	{
		/**
		 * Vector ID from FAISS index.
		 */
		public int64 document_id;
		/**
		 * Distance/similarity score (lower is better for L2 distance).
		 */
		public float distance;
		/**
		 * Rank in search results (1-based, 1 = most similar).
		 */
		public int rank;
	}
	
	/**
	 * FAISS index wrapper for vector storage and similarity search.
	 * 
	 * Provides thread-safe access to FAISS operations (FAISS itself is not
	 * thread-safe, so all operations are protected by a mutex). Supports both
	 * creating new indexes and loading existing ones from disk.
	 * 
	 * The index uses HNSW (Hierarchical Navigable Small World) algorithm for
	 * efficient approximate nearest neighbor search. New indexes are created
	 * with M=16 for a good balance of speed, recall, and memory usage.
	 * 
	 * == Usage Example ==
	 * 
	 * {{{
	 * // Create or load index
	 * var index = new OLLMvector.Index("/path/to/index.faiss", 1024);
	 * 
	 * // Add vectors
	 * var vectors = new OLLMchat.Response.FloatArray(1024);
	 * vectors.add(vector1);
	 * vectors.add(vector2);
	 * index.add_vectors(vectors);
	 * 
	 * // Search for similar vectors
	 * var results = index.search(query_vector, k: 10);
	 * 
	 * // Save index to disk
	 * index.save_to_file("/path/to/index.faiss");
	 * }}}
	 */
	public class Index : Object
	{
		// Store as generic Index type - works for both creating new indexes (IndexFlatIP) and loading from file
		private Faiss.Index index;
		
		/**
		 * The dimension (width) of vectors in this index.
		 * 
		 * All vectors added to the index must have this dimension.
		 */
		public int dimension { get; internal set; }
		private bool normalized = false;
		private string filename;
		
		/**
		 * For tmp indexes built with @copy_from: FAISS label @i → source index vector_id.
		 * Only indices @i &lt; @get_total_vectors are used; array may be longer if some ids were skipped.
		 * Empty: no remap (normal on-disk index).
		 */
		public int64[] map { get; private set; default = {}; }
		
		// Mutex to protect FAISS operations (FAISS is not thread-safe)
		private GLib.Mutex faiss_mutex = GLib.Mutex();
		
		/**
		 * Constructor.
		 * 
		 * Creates a new index or loads an existing one from disk. If the index
		 * file exists, it will be loaded (dimension comes from the file). If
		 * the file doesn't exist, a new HNSW index will be created with the
		 * specified dimension.
		 * 
		 * @param filename Path to the FAISS index file
		 * @param dim The dimension of vectors (must match if loading existing index)
		 * @throws Error if index file exists but dimension doesn't match, or if index creation/loading fails
		 */
		public Index(string filename, int dim) throws Error
		{
			this.filename = filename;
			
			// Check if index file exists - if so, load it (dimension comes from file)
			var index_file = GLib.File.new_for_path(this.filename);
			if (index_file.query_exists()) {
				// Load existing index
				Faiss.Index loaded_index;
				if (Faiss.read_index_fname(this.filename, 0, out loaded_index) != 0) {
					throw new GLib.IOError.FAILED("Failed to load FAISS index from " + this.filename);
				}
				
				// Get dimension from loaded index (FAISS returns int, cast to int)
				int loaded_dim = Faiss.index_d(loaded_index);
				if (loaded_dim < 0) {
					throw new GLib.IOError.FAILED("Failed to get dimension from loaded FAISS index");
				}
				
				// Verify dimension matches
				if (loaded_dim != dim) {
					throw new GLib.IOError.FAILED(
						"Dimension mismatch: file has %d, requested %d".printf(
							loaded_dim, dim));
				}
				
				this.dimension = loaded_dim;
				this.index = (owned)loaded_index;
				return;
			}
			
			// File doesn't exist - create new HNSW index with provided dimension
			this.dimension = dim;
			
			// Create IndexHNSWFlat with M=16 (good balance of speed/recall/memory)
			// M=16 gives ~6% memory overhead, good performance for 500k vectors
			// Cast to int64 only when calling FAISS API
			Faiss.IndexHNSW hnsw_index;
			if (Faiss.index_hnsw_flat_new(out hnsw_index, (int64)dim, 16) != 0) {
				throw new GLib.IOError.FAILED("Failed to create FAISS HNSW index");
			}
			
			// Use the HNSW index directly - IndexHNSW inherits from Index
			this.index = (owned)hnsw_index;
		}
		
		/**
		 * In-RAM HNSWFlat (M=16), not backed by a file. Use @copy_from then @search; @map holds label→source ids.
		 */
		public Index.create_tmp_hnsw(int dim) throws Error
		{
			Object();
			this.filename = "";
			this.dimension = dim;
			this.normalized = false;
			this.map = {};
			
			Faiss.IndexHNSW hnsw_index;
			if (Faiss.index_hnsw_flat_new(out hnsw_index, (int64)dim, 16) != 0) {
				throw new GLib.IOError.FAILED("Failed to create tmp FAISS HNSW index");
			}
			this.index = (owned)hnsw_index;
		}
		
		/**
		 * Call only on an empty tmp index. Reconstructs vectors from @src for each id in order.
		 *
		 * @return number of vectors added (0 if none)
		 */
		public uint64 copy_from(Index src, Gee.ArrayList<int> source_vector_ids) throws Error
		{
			if (src.dimension != this.dimension) {
				throw new GLib.IOError.FAILED("copy_from: dimension mismatch");
			}
			var batch = new OLLMchat.Response.FloatArray(this.dimension);
			int n_ids = source_vector_ids.size;
			var id_map = new int64[n_ids];
			int t = 0;
			
			foreach (var orig_id in source_vector_ids) {
				float[] row;
				try {
					row = src.reconstruct_vector(orig_id);
				} catch (Error e) {
					GLib.warning("copy_from: skip vector_id %d: %s", orig_id, e.message);
					continue;
				}
				batch.add(row);
				id_map[t] = orig_id;
				t++;
			}
			
			if (t == 0) {
				this.map = {};
				return 0;
			}
			
			this.add_vectors(batch);
			this.map = id_map;
			return (uint64)t;
		}
		
	 
		// Disabled explicit free - Vala's free_function in VAPI handles cleanup automatically
		// If we free here, it causes a double-free since VAPI also frees it
		// if (this.index != null) {
		// 	((Faiss.Index)this.index).free();
		// }
	
		/**
		 * Adds vectors in batch to the FAISS index.
		 * 
		 * All vectors in the FloatArray must have the same dimension as the
		 * index. This method is thread-safe (protected by mutex).
		 * 
		 * @param vectors The FloatArray containing vectors to add
		 * @throws Error if vector dimension doesn't match index dimension, or if FAISS operation fails
		 */
		public void add_vectors(OLLMchat.Response.FloatArray vectors) throws Error
		{
			if (vectors.rows == 0) {
				return;
			}
			
			if (vectors.width != this.dimension) {
				throw new GLib.IOError.FAILED(
					"FloatArray width mismatch: expected " +
					this.dimension.to_string() +
					", got " +
					vectors.width.to_string()
				);
			}
			
			this.faiss_mutex.lock();
			try {
				if (Faiss.index_add(this.index, (int64)vectors.rows, vectors.data) != 0) {
					throw new GLib.IOError.FAILED("Failed to add vectors to FAISS index");
				}
			} finally {
				this.faiss_mutex.unlock();
			}
		}
		
		/**
		 * Search for similar vectors.
		 * 
		 * @param query_vector Query vector
		 * @param k Number of results to return
		 * @param selector Optional IDSelector for filtering (null = search all)
		 * @return Array of SearchResult objects
		 */
		public SearchResult[] search(float[] query_vector, uint64 k = 5, Faiss.IDSelector? selector = null) throws Error
		{
			if (query_vector.length != this.dimension) {
				throw new GLib.IOError.FAILED(
					"Query vector dimension mismatch: expected " +
					this.dimension.to_string() +
					", got " +
					query_vector.length.to_string()
				);
			}
			
			var distances = new float[k];
			var labels = new int64[k];
			
			this.faiss_mutex.lock();
			try {
				if (Faiss.index_search_with_ids(this.index, 1, query_vector, (int64)k, selector, distances, labels) != 0) {
					throw new GLib.IOError.FAILED("Failed to search FAISS index");
				}
			} finally {
				this.faiss_mutex.unlock();
			}
			
			var results = new SearchResult[k];
			for (int i = 0; i < k; i++) {
				results[i] = SearchResult() {
					document_id = labels[i],
					distance = distances[i],
					rank = i + 1
				};
			}
			
			if (this.map.length > 0) {
				int64 nvec = (int64)this.get_total_vectors();
				for (int i = 0; i < results.length; i++) {
					int64 lid = results[i].document_id;
					if (lid < 0 || lid >= nvec) {
						continue;
					}
					results[i].document_id = this.map[lid];
				}
			}
			
			return results;
		}
		
		/**
		 * Gets the total number of vectors in the index.
		 * 
		 * @return The number of vectors currently stored in the index
		 */
		public uint64 get_total_vectors()
		{
			this.faiss_mutex.lock();
			try {
				return (uint64)Faiss.index_ntotal(this.index);
			} finally {
				this.faiss_mutex.unlock();
			}
		}
		
		/**
		 * Reconstruct a vector by its ID.
		 * 
		 * @param vector_id The ID of the vector to reconstruct
		 * @return The reconstructed vector as a float array
		 */
		public float[] reconstruct_vector(int64 vector_id) throws Error
		{
			this.faiss_mutex.lock();
			try {
				uint64 total = (uint64)Faiss.index_ntotal(this.index);
				if (vector_id < 0 || (uint64)vector_id >= total) {
					throw new GLib.IOError.FAILED(
						"Vector ID out of range: %lld (total vectors: %llu)".printf(
							vector_id, total));
				}
				
				var vector = new float[this.dimension];
				if (Faiss.index_reconstruct(this.index, vector_id, vector) != 0) {
					throw new GLib.IOError.FAILED("Failed to reconstruct vector %lld".printf(vector_id));
				}
				
				return vector;
			} finally {
				this.faiss_mutex.unlock();
			}
		}
		
		internal unowned Faiss.Index get_faiss_index()
		{
			return this.index;
		}
		
		/**
		 * Saves the FAISS index to a file.
		 * 
		 * This method is thread-safe and should be used instead of directly
		 * calling Faiss.write_index_fname() on the result of get_faiss_index().
		 * 
		 * @param filename Path to the file where the index should be saved
		 */
		public void save_to_file(string filename) throws Error
		{
			this.faiss_mutex.lock();
			try {
				if (Faiss.write_index_fname(this.index, filename) != 0) {
					throw new GLib.IOError.FAILED("Failed to save FAISS index to " + filename);
				}
			} finally {
				this.faiss_mutex.unlock();
			}
		}
		
		internal void set_faiss_index(owned Faiss.Index new_index)
		{
			// Don't free old index - Vala's ownership system handles it
			// Store loaded index (loaded indexes are generic Index type)
			this.index = (owned)new_index;
		}
		
		internal int get_dimension_from_index() throws Error
		{
			int dim = Faiss.index_d(this.index);
			if (dim < 0) {
				throw new GLib.IOError.FAILED("Failed to get dimension from FAISS index");
			}
			return dim;
		}
	}

}
