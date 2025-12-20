namespace OLLMvector
{
	public struct SearchResultWithDocument
	{
		public SearchResult search_result;
		public string document_text;
	}
	
	public class Database : Object
	{
			
		private Index? index = null;
		private OLLMchat.Client ollama;
		// TODO: needs to store metadata mapping: vector_id -> (file_path, start_line, end_line, element_type, element_name)
		// Code snippets will be read from filesystem when needed, not stored here
		
		public Database(OLLMchat.Client ollama)
		{
			this.ollama = ollama;
			if (this.ollama.config.model == "") {
				throw new GLib.IOError.FAILED("Ollama client model is not set");
			}
		}
		
		/**
		 * The embedding dimension.
		 */
		public uint64 dimension {
			get { return this.index == null ? 0 : this.index.dimension; }
		}
		
		/**
		 * The total number of vectors in the index.
		 */
		public uint64 vector_count {
			get { return this.index == null ? 0 : this.index.get_total_vectors(); }
		}
		
		/**
		 * Initializes the index with a given dimension.
		 * 
		 * @param dimension The embedding dimension
		 */
		public void init_index(uint64 dim) throws GLib.Error
		{
			if (this.index == null) {
				this.index = new Index(dim);
			}
			
			if (this.index.dimension != dim) {
				throw new GLib.IOError.FAILED(
					"Dimension mismatch: index has %llu, requested %llu".printf(
						this.index.dimension, dim));
			}
		}
		
		/**
		 * Adds vectors in batch to the FAISS index.
		 * 
		 * @param vectors The FloatArray containing vectors to add
		 */
		public void add_vectors_batch(FloatArray vectors) throws GLib.Error
		{
			if (this.index == null) {
				throw new GLib.IOError.FAILED("Index not initialized. Call init_index() first.");
			}
			this.index.add_vectors(vectors);
		}
		
		private float[] embed_to_floats(Gee.ArrayList<double?> embed) throws Error
		{
			var float_array = new float[embed.size];
			for (int i = 0; i < embed.size; i++) {
				var val = embed[i];
				if (val == null) {
					throw new GLib.IOError.FAILED("Null value in embed vector");
				}
				float_array[i] = (float)val;
			}
			return float_array;
		}

		public async void add_documents(string[] texts) throws Error
		{
			// Init index from first embed to get dimension
			if (texts.length == 0) {
				return;
			}
			
			var first_response = yield this.ollama.embed(texts[0]);
			if (first_response == null || first_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get embed for first document");
			}
			
			// Init index from first embed to get dimension
			if (this.index == null) {
				this.index = new Index((uint64)first_response.embeddings[0].size);
			}
			
			// Build FloatArray with known width (all vectors have fixed width)
			var vector_batch = FloatArray(this.dimension);
			
			// Add first vector
			vector_batch.add(this.embed_to_floats(first_response.embeddings[0]));
			// TODO: store metadata (file_path, line_range, element_info) for vector_id = 0
			
			// Add remaining vectors
			for (int i = 1; i < texts.length; i++) {
				var response = yield this.ollama.embed(texts[i]);
				if (response == null || response.embeddings.size == 0) {
					throw new GLib.IOError.FAILED("Failed to get embed for document " + i.to_string());
				}
				
				vector_batch.add(this.embed_to_floats(response.embeddings[0]));
				// TODO: store metadata (file_path, line_range, element_info) for vector_id = i
			}
			
			this.index.add_vectors(vector_batch);
			print("Added " + texts.length.to_string() + " documents to vector database\n");
		}
		
		public async SearchResultWithDocument[] search(string query, uint64 k = 5) throws Error
		{
			GLib.debug("Sending search query to embedder: %s", query);
			var response = yield this.ollama.embed(query);
			if (response == null || response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get query embed");
			}
			
			// Init index from query embed if not already initialized
			// (This can happen if search is called before add_documents)
			if (this.index == null) {
				this.index = new Index((uint64)response.embeddings[0].size);
			}
			
			// Extract the first embed vector and convert to float[]
			var results = this.index.search(
				this.embed_to_floats(response.embeddings[0]),
				k
			);
			var enhanced_results = new SearchResultWithDocument[results.length];
			
			for (int i = 0; i < results.length; i++) {
				// TODO: lookup metadata from vector_id (results[i].document_id) to get file_path, line_range, element_info
				// TODO: read code snippet from file_path using line_range when needed
				
				enhanced_results[i] = SearchResultWithDocument() {
					search_result = results[i],
					document_text = "" // TODO: will be populated from file_path + line_range lookup
				};
			}
			
			return enhanced_results;
		}
		
		public void save_index(string filename) throws Error
		{
			if (this.index == null) {
				return;
			}
			
			this.index.save_to_file(filename);
			
			// TODO: save metadata mapping (vector_id -> file_path, line_range, element_info) to database
		}
		
		public void load_index(string filename) throws Error
		{
			// TODO: Need to know dimension to create index before loading
			// This will need to be updated when load_from_file is implemented
			if (this.index == null) {
				throw new GLib.IOError.FAILED("Cannot load index: dimension unknown. Call init_index() first.");
			}
			
			this.index.load_from_file(filename);
			
			// TODO: load metadata mapping (vector_id -> file_path, line_range, element_info) from database
		}
	}

	
}
