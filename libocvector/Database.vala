namespace OLLMvector
{
	public struct SearchResultWithDocument
	{
		public SearchResult search_result;
		public string document_text;
	}
	
	/**
	 * Vector database with embedding generation and FAISS storage.
	 * 
	 * Manages the complete vector database lifecycle: embedding generation,
	 * vector storage in FAISS, and similarity search. Integrates with OLLMchat
	 * for embedding generation and automatically manages the FAISS index.
	 * 
	 * The database requires configuration of model usage types before use:
	 * - "ocvector.embed": Embedding model for converting text to vectors
	 * 
	 * == Usage Example ==
	 * 
	 * {{{
	 * // Register tool config type
	 * OLLMvector.Tool.CodebaseSearchTool.register_config();
	 * OLLMvector.Tool.CodebaseSearchTool.setup_tool_config(config);
	 * 
	 * // Get embedding dimension
	 * var dimension = yield OLLMvector.Database.get_embedding_dimension(embedding_client);
	 * 
	 * // Create database
	 * var db = new OLLMvector.Database(embedding_client, "/path/to/index.faiss", dimension);
	 * 
	 * // Add documents (automatically generates embeddings)
	 * yield db.add_documents({"document 1", "document 2"});
	 * 
	 * // Search
	 * var results = yield db.search("query text", k: 10);
	 * 
	 * // Save index
	 * db.save_index();
	 * }}}
	 */
	public class Database : Object
	{
			
		internal Index? index = null;
		private OLLMchat.Client ollama;
		private string filename;
		// TODO: needs to store metadata mapping: vector_id -> (file_path, start_line, end_line, element_type, element_name)
		// Code snippets will be read from filesystem when needed, not stored here
		
		
		
		/**
		 * Checks if the required models for codebase search are available on the server.
		 * 
		 * Verifies that both the embedding model and analysis model are available on the server.
		 * Reads from CodebaseSearchToolConfig in tools map, or falls back to usage map for
		 * backward compatibility. This should be called before initializing the codebase search tool.
		 * 
		 * @param config The Config2 instance containing model usage configuration
		 * @return true if both models are available, false otherwise
		 */
		public static async bool check_required_models_available(OLLMchat.Settings.Config2 config)
		{
			// Inline validation logic
			if (!config.tools.has_key("codebase_search")) {
				return false;
			}
			var tool_config = config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			if (!tool_config.enabled) {
				return false;
			}
			// Validate both embed and analysis
			if (!(yield tool_config.embed.verify_model(config))) {
				return false;
			}
			if (!(yield tool_config.analysis.verify_model(config))) {
				return false;
			}
			return true;
		}
		
		/**
		 * Gets the embedding dimension from the client by doing a test embed.
		 * 
		 * @param ollama The OLLMchat client for embeddings
		 * @return The embedding dimension
		 */
		public static async uint64 get_embedding_dimension(OLLMchat.Client ollama) throws GLib.Error
		{
			// Phase 3: model is not on Client, need to get model from config
			var model = ollama.config.get_default_model();
			if (model == "") {
				throw new GLib.IOError.FAILED("No default model configured for embeddings");
			}
			var test_response = yield ollama.embed(model, "test");
			if (test_response == null || test_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get test embedding to determine dimension");
			}
			
			return (uint64)test_response.embeddings[0].size;
		}
		
		/**
		 * Constructor.
		 * 
		 * @param ollama The OLLMchat client for embeddings
		 * @param filename Path to the FAISS index file
		 * @param dimension The embedding dimension (use get_dimension() to obtain this)
		 */
		public Database(OLLMchat.Client ollama, string filename, uint64 dimension) throws GLib.Error
		{
			this.ollama = ollama;
			// Phase 3: model is not on Client, embed() gets model from config
			this.filename = filename;
			
			// Create Index immediately with the provided dimension
			// Index constructor will load from file if it exists, or create new if it doesn't
			this.index = new Index(this.filename, dimension);
		}
		
		/**
		 * The embedding dimension.
		 */
		public uint64 dimension {
			get { return this.index.dimension; }
		}
		
		/**
		 * The total number of vectors in the index.
		 */
		public uint64 vector_count {
			get { return this.index.get_total_vectors(); }
		}
		
		private void ensure_index(uint64 dim) throws GLib.Error
		{
			// Index should always exist after constructor, but check dimension matches
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
			// Auto-initialize index if needed (dimension comes from vectors.width)
			this.ensure_index(vectors.width);
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
			
			var model = this.ollama.config.get_default_model();
			if (model == "") {
				throw new GLib.IOError.FAILED("No default model configured for embeddings");
			}
			var first_response = yield this.ollama.embed(model, texts[0]);
			if (first_response == null || first_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get embed for first document");
			}
			
			// Ensure index is initialized with correct dimension
			this.ensure_index((uint64)first_response.embeddings[0].size);
			
			// Build FloatArray with known width (all vectors have fixed width)
			var vector_batch = FloatArray(this.dimension);
			
			// Add first vector
			vector_batch.add(this.embed_to_floats(first_response.embeddings[0]));
			// TODO: store metadata (file_path, line_range, element_info) for vector_id = 0
			
			// Add remaining vectors
			for (int i = 1; i < texts.length; i++) {
				var response = yield this.ollama.embed(model, texts[i]);
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
			var model = this.ollama.config.get_default_model();
			if (model == "") {
				throw new GLib.IOError.FAILED("No default model configured for embeddings");
			}
			var response = yield this.ollama.embed(model, query);
			if (response == null || response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get query embed");
			}
			
			// Ensure index is initialized with correct dimension
			// (This can happen if search is called before add_documents)
			this.ensure_index((uint64)response.embeddings[0].size);
			
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
		
		/**
		 * Saves the index to the file specified in constructor.
		 */
		public void save_index() throws Error
		{
			if (this.index == null) {
				return;
			}
			
			// Use Index.save_to_file() which handles thread-safety
			this.index.save_to_file(this.filename);
			
			// TODO: save metadata mapping (vector_id -> file_path, line_range, element_info) to database
		}
		
		
	}

	
}
