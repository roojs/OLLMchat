namespace OLLMvector
{
	public struct SearchResult
	{
		public int64 document_id;
		public float similarity_score;
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
		private Faiss.IndexFlatIP index;
		private uint64 dimension;
		private bool normalized = false;
		
		public Index(uint64 dim) throws Error
		{
			this.dimension = dim;
			if (Faiss.index_flat_ip_new(out this.index, (int64)dim) != 0) {
				throw new GLib.IOError.FAILED("Failed to create FAISS index");
			}
		}
		
	~Index()
	{
		// Disabled explicit free - Vala's free_function in VAPI handles cleanup automatically
		// If we free here, it causes a double-free since VAPI also frees it
		// if (this.index != null) {
		// 	((Faiss.Index)this.index).free();
		// }
	}
		
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
			
			if (Faiss.index_add((Faiss.Index)this.index, (int64)vectors.rows, vectors.data) != 0) {
				throw new GLib.IOError.FAILED("Failed to add vectors to FAISS index");
			}
		}
		
		public SearchResult[] search(float[] query_vector, uint64 k = 5) throws Error
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
			
			if (Faiss.index_search((Faiss.Index)this.index, 1, query_vector, (int64)k, distances, labels) != 0) {
				throw new GLib.IOError.FAILED("Failed to search FAISS index");
			}
			
			var results = new SearchResult[k];
			for (int i = 0; i < k; i++) {
				results[i] = SearchResult() {
					document_id = labels[i],
					similarity_score = distances[i],
					rank = i + 1
				};
			}
			
			return results;
		}
		
		public uint64 get_total_vectors()
		{
			return (uint64)Faiss.index_ntotal((Faiss.Index)this.index);
		}
		
		public void save_to_file(string filename) throws Error
		{
			// TODO: Implement once C API wrapper is available
			throw new GLib.IOError.FAILED("Save not yet implemented - C API wrapper required");
		}
			
		public void load_from_file(string filename) throws Error
		{
			// TODO: Implement once C API wrapper is available
			throw new GLib.IOError.FAILED("Load not yet implemented - C API wrapper required");
		}
	}

}
