namespace OLLMvector
{
	public struct SearchResult
	{
		public int64 document_id;
		public float distance;
		public int rank;
	}
	
	public struct FloatArray
	{
		public float[] data;
		public uint64 width;
		public int rows;
		
		public FloatArray(uint64 width)
		{
			this.data = {};
			this.width = width;
			this.rows = 0;
		}
		
		public void add(float[] vector) throws Error
		{
			if (vector.length != this.width) {
				throw new GLib.IOError.FAILED(
					"Vector width mismatch: expected " +
					this.width.to_string() +
					", got " +
					vector.length.to_string()
				);
			}
				
			// Resize array to accommodate new vector
			int current_size = this.data.length;
			this.data.resize(current_size + (int)this.width);
			
			// Copy vector data to the end of the flat array
			for (int i = 0; i < this.width; i++) {
				this.data[current_size + i] = vector[i];
			}	
			
			this.rows++;
		}
		
		
		public float[] get_vector(int index) throws Error
		{
			if (index < 0 || index >= this.rows) {
				throw new GLib.IOError.FAILED("Vector index out of range");
			}
			
			var vector = new float[this.width];
			int offset = index * (int)this.width;
			for (int i = 0; i < this.width; i++) {
				vector[i] = this.data[offset + i];
			}
			return vector;
		}
		
	}

	public class Index : Object
	{
		// Store as generic Index type - works for both creating new indexes (IndexFlatIP) and loading from file
		private Faiss.Index index;
		public uint64 dimension { get; internal set; }
		private bool normalized = false;
		private string filename;
		
		// Mutex to protect FAISS operations (FAISS is not thread-safe)
		private GLib.Mutex faiss_mutex = GLib.Mutex();
		
		public Index(string filename, uint64 dim) throws Error
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
				
				// Get dimension from loaded index
				int loaded_dim = Faiss.index_d(loaded_index);
				if (loaded_dim < 0) {
					throw new GLib.IOError.FAILED("Failed to get dimension from loaded FAISS index");
				}
				
				// Verify dimension matches
				if ((uint64)loaded_dim != dim) {
					throw new GLib.IOError.FAILED(
						"Dimension mismatch: file has %llu, requested %llu".printf(
							(uint64)loaded_dim, dim));
				}
				
				this.dimension = (uint64)loaded_dim;
				this.index = (owned)loaded_index;
				return;
			}
			
			// File doesn't exist - create new HNSW index with provided dimension
			this.dimension = dim;
			
			// Create IndexHNSWFlat with M=16 (good balance of speed/recall/memory)
			// M=16 gives ~6% memory overhead, good performance for 500k vectors
			Faiss.IndexHNSW hnsw_index;
			if (Faiss.index_hnsw_flat_new(out hnsw_index, (int64)dim, 16) != 0) {
				throw new GLib.IOError.FAILED("Failed to create FAISS HNSW index");
			}
			
			// Use the HNSW index directly - IndexHNSW inherits from Index
			this.index = (owned)hnsw_index;
		}
		
	 
		// Disabled explicit free - Vala's free_function in VAPI handles cleanup automatically
		// If we free here, it causes a double-free since VAPI also frees it
		// if (this.index != null) {
		// 	((Faiss.Index)this.index).free();
		// }
	
		
		public void add_vectors(FloatArray vectors) throws Error
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
			
			if (Faiss.index_add(this.index, (int64)vectors.rows, vectors.data) != 0) {
				throw new GLib.IOError.FAILED("Failed to add vectors to FAISS index");
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
			
			if (Faiss.index_search_with_ids(this.index, 1, query_vector, (int64)k, selector, distances, labels) != 0) {
				throw new GLib.IOError.FAILED("Failed to search FAISS index");
			}
			
			var results = new SearchResult[k];
			for (int i = 0; i < k; i++) {
				results[i] = SearchResult() {
					document_id = labels[i],
					distance = distances[i],
					rank = i + 1
				};
			}
			
			return results;
		}
		
		public uint64 get_total_vectors()
		{
			return (uint64)Faiss.index_ntotal(this.index);
		}
		
		/**
		 * Reconstruct a vector by its ID.
		 * 
		 * @param vector_id The ID of the vector to reconstruct
		 * @return The reconstructed vector as a float array
		 */
		public float[] reconstruct_vector(int64 vector_id) throws Error
		{
			if (vector_id < 0 || (uint64)vector_id >= this.get_total_vectors()) {
				throw new GLib.IOError.FAILED(
					"Vector ID out of range: %lld (total vectors: %llu)".printf(
						vector_id, this.get_total_vectors()));
			}
			
			var vector = new float[this.dimension];
			if (Faiss.index_reconstruct(this.index, vector_id, vector) != 0) {
				throw new GLib.IOError.FAILED("Failed to reconstruct vector %lld".printf(vector_id));
			}
			
			return vector;
		}
		
		internal unowned Faiss.Index get_faiss_index()
		{
			return this.index;
		}
		
		internal void set_faiss_index(owned Faiss.Index new_index)
		{
			// Don't free old index - Vala's ownership system handles it
			// Store loaded index (loaded indexes are generic Index type)
			this.index = (owned)new_index;
		}
		
		internal uint64 get_dimension_from_index() throws Error
		{
			int dim = Faiss.index_d(this.index);
			if (dim < 0) {
				throw new GLib.IOError.FAILED("Failed to get dimension from FAISS index");
			}
			return (uint64)dim;
		}
	}

}
