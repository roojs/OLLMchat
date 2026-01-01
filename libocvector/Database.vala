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
	 * // Register and setup model usage
	 * OLLMvector.Database.register_config();
	 * OLLMvector.Database.setup_embed_usage(config);
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
		 * Registers the embed ModelUsage type in Config2.
		 * 
		 * This should be called before loading config to register
		 * "ocvector.embed" as a ModelUsage type for deserialization.
		 */
		public static void register_config()
		{
			OLLMchat.Settings.Config2.register_type("ocvector.embed", typeof(OLLMchat.Settings.ModelUsage));
		}
		
		/**
		 * Sets up the embed ModelUsage entry in Config2.
		 * 
		 * Creates a ModelUsage entry for "ocvector.embed" in the config's usage map
		 * if it doesn't already exist. Uses the default connection and "bge-m3:latest" model.
		 * This should be called when setting up the codebase search tool.
		 * 
		 * @param config The Config2 instance to update
		 */
		public static void setup_embed_usage(OLLMchat.Settings.Config2 config)
		{
			// Only create if it doesn't already exist
			if (config.usage.has_key("ocvector.embed")) {
				return;
			}
			
			var default_connection = config.get_default_connection();
			if (default_connection == null) {
				GLib.warning("No default connection found, cannot setup embed usage");
				return;
			}
			
			var embed_usage = new OLLMchat.Settings.ModelUsage() {
				connection = default_connection.url,
				model = "bge-m3:latest",
				options = new OLLMchat.Call.Options() {
					temperature = 0.0,
					num_ctx = 2048
				}
			};
			
			config.usage.set("ocvector.embed", embed_usage);
		}
		
		/**
		 * Checks if the required models for codebase search are available on the server.
		 * 
		 * Verifies that both the embedding model (from ocvector.embed) and analysis model
		 * (from ocvector.analysis) are available on the server. This should be called before
		 * initializing the codebase search tool.
		 * 
		 * @param config The Config2 instance containing model usage configuration
		 * @return true if both models are available, false otherwise
		 */
		public static async bool check_required_models_available(OLLMchat.Settings.Config2 config)
		{
			// Check if embed usage exists
			if (!config.usage.has_key("ocvector.embed")) {
				return false;
			}
			
			// Check if analysis usage exists
			if (!config.usage.has_key("ocvector.analysis")) {
				return false;
			}
			
			var embed_usage = config.usage.get("ocvector.embed") as OLLMchat.Settings.ModelUsage;
			var analysis_usage = config.usage.get("ocvector.analysis") as OLLMchat.Settings.ModelUsage;
			
			if (embed_usage == null || analysis_usage == null) {
				return false;
			}
			
			// Get connection for embed model
			var embed_connection = config.connections.get(embed_usage.connection);
			if (embed_connection == null) {
				return false;
			}
			
			// Get connection for analysis model
			var analysis_connection = config.connections.get(analysis_usage.connection);
			if (analysis_connection == null) {
				return false;
			}
			
			// Create test client for embed connection
			var embed_client = new OLLMchat.Client(embed_connection);
			
			// Get list of models from embed connection (populates available_models)
 			try {
				yield embed_client.models();
				
				// Check if embed model is in available_models HashMap
				if (!embed_client.available_models.has_key(embed_usage.model)) {
					return false;
				}
				
				// Check if connections are the same - if so, reuse the same client
				if (embed_usage.connection == analysis_usage.connection) {
					// Same connection, check analysis model in the same available_models
					return embed_client.available_models.has_key(analysis_usage.model);
				}
			} catch (GLib.Error e) {
				return false;
			}
			
			// Different connection, fetch models from analysis connection
			var analysis_client = new OLLMchat.Client(analysis_connection);
			
			try {
				yield analysis_client.models();
				return analysis_client.available_models.has_key(analysis_usage.model);
			} catch (GLib.Error e) {
				return false;
			}
			
			// will not get here..
			
		}
		
		/**
		 * Gets the embedding dimension from the client by doing a test embed.
		 * 
		 * @param ollama The OLLMchat client for embeddings
		 * @return The embedding dimension
		 */
		public static async uint64 get_embedding_dimension(OLLMchat.Client ollama) throws GLib.Error
		{
			if (ollama.model == "") {
				throw new GLib.IOError.FAILED("Ollama client model is not set");
			}
			
			var test_response = yield ollama.embed("test");
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
			if (this.ollama.model == "") {
				throw new GLib.IOError.FAILED("Ollama client model is not set");
			}
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
			
			var first_response = yield this.ollama.embed(texts[0]);
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
