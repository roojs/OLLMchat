namespace VectorSearch
{
    public class Index : Object
    {
        private Faiss.IndexFlatIP index;
        private uint64 dimension;
        private bool normalized = false;
        
        public Index(uint64 dim) throws Error
        {
            this.dimension = dim;
            int result = Faiss.index_flat_ip_new(out this.index, dim);
            if (result != 0) {
                throw new Error.FAILED("Failed to create FAISS index");
            }
        }
        
        ~Index()
        {
            if (this.index != null) {
                Faiss.index_free(this.index);
            }
        }
        
        public void add_vectors(float[][] vectors) throws Error
        {
            if (vectors.length == 0) {
                return;
            }
            
            // Flatten 2D array to 1D
            var flat_vectors = new float[vectors.length * this.dimension];
            for (int i = 0; i < vectors.length; i++) {
                if (vectors[i].length != this.dimension) {
                    throw new Error.FAILED("Vector dimension mismatch: expected " + this.dimension.to_string() + ", got " + vectors[i].length.to_string());
                }
                for (int j = 0; j < this.dimension; j++) {
                    flat_vectors[i * this.dimension + j] = vectors[i][j];
                }
            }
            
            int result = Faiss.index_add(this.index, vectors.length, flat_vectors);
            if (result != 0) {
                throw new Error.FAILED("Failed to add vectors to FAISS index");
            }
        }
        
        public SearchResult[] search(float[] query_vector, uint64 k = 5) throws Error
        {
            if (query_vector.length != this.dimension) {
                throw new Error.FAILED("Query vector dimension mismatch: expected " + this.dimension.to_string() + ", got " + query_vector.length.to_string());
            }
            
            var distances = new float[k];
            var labels = new long[k];
            
            int result = Faiss.index_search(this.index, 1, query_vector, k, distances, labels);
            if (result != 0) {
                throw new Error.FAILED("Failed to search FAISS index");
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
            return Faiss.index_ntotal(this.index);
        }
        
        public void save_to_file(string filename) throws Error
        {
            int result = Faiss.index_write(this.index, filename);
            if (result != 0) {
                throw new Error.FAILED("Failed to save index to " + filename);
            }
        }
        
        public void load_from_file(string filename) throws Error
        {
            int result = Faiss.index_read(this.index, filename);
            if (result != 0) {
                throw new Error.FAILED("Failed to load index from " + filename);
            }
        }
    }

    public struct SearchResult
    {
        public long document_id;
        public float similarity_score;
        public int rank;
    }
}