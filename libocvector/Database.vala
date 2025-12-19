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
		private uint64 embedding_dimension = 768; // Default for nomic-embed-text
		
		public Database(OLLMchat.Client ollama)
		{
			this.ollama = ollama;
			if (this.ollama.config.model == "") {
				throw new GLib.IOError.FAILED("Ollama client model is not set");
			}
		}
		
		/**
		 * Gets the embedding dimension.
		 * 
		 * @return The embedding dimension, or 0 if not initialized
		 */
		public uint64 get_embedding_dimension()
		{
			return this.embedding_dimension;
		}
		
		/**
		 * Gets the total number of vectors in the index.
		 * 
		 * @return The total vector count, or 0 if index is not initialized
		 */
		public uint64 get_total_vectors()
		{
			if (this.index == null) {
				return 0;
			}
			return this.index.get_total_vectors();
		}
		
		/**
		 * Initializes the index with a given dimension.
		 * 
		 * @param dimension The embedding dimension
		 */
		public void init_index(uint64 dimension) throws GLib.Error
		{
			if (this.index == null) {
				this.embedding_dimension = dimension;
				this.index = new Index(this.embedding_dimension);
			} else if (this.embedding_dimension != dimension) {
				throw new GLib.IOError.FAILED(
					"Dimension mismatch: index has %llu, requested %llu".printf(
						this.embedding_dimension, dimension));
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
				this.embedding_dimension = (uint64)first_response.embeddings[0].size;
				this.index = new Index(this.embedding_dimension);
			}
			
			// Build FloatArray with known width (all vectors have fixed width)
			var vector_batch = FloatArray(this.embedding_dimension);
			
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
			var response = yield this.ollama.embed(query);
			if (response == null || response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get query embed");
			}
			
			// Init index from query embed if not already initialized
			// (This can happen if search is called before add_documents)
			if (this.index == null) {
				this.embedding_dimension = (uint64)response.embeddings[0].size;
				this.index = new Index(this.embedding_dimension);
			}
			
			// Extract the first embed vector and convert to float[]
			var query_embed = this.embed_to_floats(response.embeddings[0]);
			var results = this.index.search(query_embed, k);
			var enhanced_results = new SearchResultWithDocument[results.length];
			
			for (int i = 0; i < results.length; i++) {
				var result = results[i];
				// TODO: lookup metadata from vector_id (result.document_id) to get file_path, line_range, element_info
				// TODO: read code snippet from file_path using line_range when needed
				
				enhanced_results[i] = SearchResultWithDocument() {
					search_result = result,
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
			if (this.index == null && this.embedding_dimension > 0) {
				this.index = new Index(this.embedding_dimension);
			}
			
			if (this.index == null) {
				return;
			}
			
			this.index.load_from_file(filename);
			
			// TODO: load metadata mapping (vector_id -> file_path, line_range, element_info) from database
		}
	}

	
}
