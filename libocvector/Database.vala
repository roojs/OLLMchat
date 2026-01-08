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
	 * // Get dimension first, then create database
	 * var temp_db = new OLLMvector.Database(config, "/path/to/index.faiss", OLLMvector.Database.DISABLE_INDEX);
	 * var dimension = yield temp_db.embed_dimension();
	 * var db = new OLLMvector.Database(config, "/path/to/index.faiss", dimension);
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
	public class Database : VectorBase
	{
		/**
		 * Sentinel value to indicate index should not be created in constructor.
		 * Use this when creating a temporary Database instance just to check dimension.
		 */
		public const int DISABLE_INDEX = -1;
		
		internal Index? index = null;
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
		 * Constructor.
		 * 
		 * @param config The Config2 instance containing tool configuration
		 * @param filename Path to the FAISS index file
		 * @param dimension The embedding dimension (use embed_dimension() to obtain this), or DISABLE_INDEX to skip index creation
		 */
		public Database(OLLMchat.Settings.Config2 config, string filename, int dimension) throws GLib.Error
		{
			base(config);
			this.filename = filename;
			
			// Index constructor will load from file if it exists, or create new if it doesn't
			if (dimension == DISABLE_INDEX) {
				return;
			}
			this.index = new Index(this.filename, dimension);
		}
		
		/**
		 * Gets the embedding dimension by doing a test embed.
		 * 
		 * Uses the base class connection method to get the embedding connection and model.
		 * This is an instance method that can be called when dimension is not yet known.
		 * 
		 * @return The embedding dimension
		 */
		public async int embed_dimension() throws GLib.Error
		{
			var connection = yield this.connection("embed");
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			var embed_call = new OLLMchat.Call.Embed(
				connection,
				tool_config.embed.model,
				tool_config.embed.options
			) {
				input = "test"
			};
			
			var test_response = yield embed_call.exec_embed();
			if (test_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get test embedding to determine dimension");
			}
			
			return (int)test_response.embeddings[0].size;
		}
		
		/**
		 * The embedding dimension.
		 */
		public int dimension {
			get { return this.index.dimension; }
		}
		
		/**
		 * The total number of vectors in the index.
		 */
		public uint64 vector_count {
			get { return this.index.get_total_vectors(); }
		}
		
		
		/**
		 * Adds vectors in batch to the FAISS index.
		 * 
		 * @param vectors The FloatArray containing vectors to add
		 */
		public void add_vectors_batch(FloatArray vectors) throws GLib.Error
		{
			// Check dimension matches
			if (this.index.dimension != vectors.width) {
				throw new GLib.IOError.FAILED(
					"Dimension mismatch: index has %d, requested %d".printf(
						this.index.dimension,
						vectors.width
					)
				);
			}
			
			this.index.add_vectors(vectors);
		}
		
		private float[] embed_to_floats(Gee.ArrayList<double?> embed) throws Error
		{
			var float_array = new float[embed.size];
			for (int i = 0; i < embed.size; i++) {
				var val = embed.get(i);
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
			
			var connection = yield this.connection("embed");
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			var embed_call = new OLLMchat.Call.Embed(
				connection,
				tool_config.embed.model,
				tool_config.embed.options
			) {
				input = texts[0]
			};
			
			var first_response = yield embed_call.exec_embed();
			if (first_response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get embed for first document");
			}
			
			// Check dimension matches
			if (this.index.dimension != (int)first_response.embeddings[0].size) {
				throw new GLib.IOError.FAILED(
					"Dimension mismatch: index has %d, requested %d".printf(
						this.index.dimension,
						(int)first_response.embeddings[0].size
					)
				);
			}
			
			// Build FloatArray with known width (all vectors have fixed width)
			var vector_batch = FloatArray(this.dimension);
			
			// Add first vector
			vector_batch.add(this.embed_to_floats(first_response.embeddings[0]));
			// TODO: store metadata (file_path, line_range, element_info) for vector_id = 0
			
			// Add remaining vectors
			for (int i = 1; i < texts.length; i++) {
				embed_call = new OLLMchat.Call.Embed(
					connection,
					tool_config.embed.model,
					tool_config.embed.options
				) {
					input = texts[i]
				};
				var response = yield embed_call.exec_embed();
				if (response.embeddings.size == 0) {
					throw new GLib.IOError.FAILED(
						"Failed to get embed for document " + i.to_string()
					);
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
			
			var connection = yield this.connection("embed");
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			var embed_call = new OLLMchat.Call.Embed(
				connection,
				tool_config.embed.model,
				tool_config.embed.options
			) {
				input = query
			};
			
			var response = yield embed_call.exec_embed();
			if (response.embeddings.size == 0) {
				throw new GLib.IOError.FAILED("Failed to get query embed");
			}
			
			// Check dimension matches
			if (this.index.dimension != (int)response.embeddings[0].size) {
				throw new GLib.IOError.FAILED(
					"Dimension mismatch: index has %d, requested %d".printf(
						this.index.dimension,
						(int)response.embeddings[0].size
					)
				);
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
		
		/**
		 * Saves the index to the file specified in constructor.
		 */
		public void save_index() throws Error
		{
			// Use Index.save_to_file() which handles thread-safety
			this.index.save_to_file(this.filename);
			
			// TODO: save metadata mapping (vector_id -> file_path, line_range, element_info) to database
		}
		
		
	}

	
}
