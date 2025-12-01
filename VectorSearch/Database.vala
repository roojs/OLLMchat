namespace VectorSearch
{
	public class Database : Object
	{
		private Index? index = null;
		private OLLMchat.Ollama.Client ollama;
		private Gee.ArrayList<string> documents;
		private uint64 embedding_dimension;
		
		public Database(OLLMchat.Ollama.Client ollama)
		{
			this.ollama = ollama;
			this.documents = new Gee.ArrayList<string>();
			this.embedding_dimension = 768; // Default for nomic-embed-text
		}
		
		public async void initialize() throws Error
		{
			if (this.ollama.model == "") {
				throw new Error.FAILED("Ollama client model is not set");
			}
			
			// Test embedding to get dimension
			var test_embedding = yield this.ollama.embed("test");
			if (test_embedding == null) {
				throw new Error.FAILED("Failed to get test embedding from Ollama");
			}
			
			this.embedding_dimension = test_embedding.length;
			this.index = new Index(this.embedding_dimension);
		}
		
		public async void add_documents(string[] texts) throws Error
		{
			if (this.index == null) {
				throw new Error.FAILED("Database not initialized");
			}
			
			float[][] embeddings = new float[texts.length];
			
			for (int i = 0; i < texts.length; i++) {
				var embedding = yield this.ollama.embed(texts[i]);
				if (embedding == null) {
					throw new Error.FAILED("Failed to get embedding for document " + i.to_string());
				}
				embeddings[i] = embedding;
				this.documents.add(texts[i]);
			}
			
			this.index.add_vectors(embeddings);
			print("Added " + texts.length.to_string() + " documents to vector database\n");
		}
		
		public async SearchResultWithDocument[] search(string query, uint64 k = 5) throws Error
		{
			if (this.index == null) {
				throw new Error.FAILED("Database not initialized");
			}
			
			var query_embedding = yield this.ollama.embed(query);
			if (query_embedding == null) {
				throw new Error.FAILED("Failed to get query embedding");
			}
			
			var results = this.index.search(query_embedding, k);
			var enhanced_results = new SearchResultWithDocument[results.length];
			
			for (int i = 0; i < results.length; i++) {
				var result = results[i];
				string document_text = ((int)result.document_id < this.documents.size) ? this.documents[(int)result.document_id] : "Unknown document";
				
				enhanced_results[i] = SearchResultWithDocument() {
					search_result = result,
					document_text = document_text
				};
			}
			
			return enhanced_results;
		}
		
		public void save_index(string filename) throws Error
		{
			if (this.index != null) {
				this.index.save_to_file(filename);
				
				// Save documents
				var file = GLib.File.new_for_path(filename + ".documents");
				var dos = new GLib.DataOutputStream(file.create(GLib.FileCreateFlags.REPLACE));
				
				foreach (var doc in this.documents) {
					dos.put_string(doc + "\n");
				}
			}
		}
		
		public void load_index(string filename) throws Error
		{
			if (this.index == null && this.embedding_dimension > 0) {
				this.index = new Index(this.embedding_dimension);
			}
			
			if (this.index != null) {
				this.index.load_from_file(filename);
				
				// Load documents
				var documents_file = filename + ".documents";
				var file = GLib.File.new_for_path(documents_file);
				if (file.query_exists()) {
					this.documents.clear();
					string content;
					try {
						GLib.FileUtils.get_contents(documents_file, out content);
						var lines = content.split("\n");
						foreach (var line in lines) {
							if (line != "") {
								this.documents.add(line);
							}
						}
					} catch (GLib.FileError e) {
						// If file read fails, documents list remains empty
					}
				}
			}
		}
	}

	public struct SearchResultWithDocument
	{
		public SearchResult search_result;
		public string document_text;
	}
}
