[CCode (cheader_filename = "faiss_c_wrapper.h")]
namespace Faiss {
    [CCode (cname = "FaissIndex", has_type_id = false, free_function = "faiss_Index_free")]
    [Compact]
    [SimpleType]
    public class Index {
        // Method to explicitly free the index (useful when free_function isn't available)
        [CCode (cname = "faiss_Index_free")]
        public void free();
    }
    
    [CCode (cname = "FaissIndexHNSW", has_type_id = false)]
    [Compact]
    [SimpleType]
    public class IndexHNSW : Index {}
    
    [CCode (cname = "FaissIDSelector", has_type_id = false, free_function = "faiss_IDSelector_free")]
    [Compact]
    [SimpleType]
    public class IDSelector {
        [CCode (cname = "faiss_IDSelector_free")]
        public void free();
    }
    
    [CCode (cname = "faiss_IndexHNSWFlat_new")]
    int index_hnsw_flat_new(out IndexHNSW index, int64 d, int64 M);
    
    [CCode (cname = "faiss_IDSelectorBatch_new")]
    int id_selector_batch_new(out IDSelector selector, int64 n, [CCode (array_length = false)] int64* ids);
    
    [CCode (cname = "faiss_Index_add")]
    int index_add(Index index, int64 n, [CCode (array_length = false)] float* x);
    
    [CCode (cname = "faiss_Index_add_with_ids")]
    int index_add_with_ids(Index index, int64 n, [CCode (array_length = false)] float* x, [CCode (array_length = false)] int64* xids);
    
    [CCode (cname = "faiss_Index_search")]
    int index_search(Index index, int64 n, [CCode (array_length = false)] float* x, int64 k, [CCode (array_length = false)] float* distances, [CCode (array_length = false)] int64* labels);
    
    [CCode (cname = "faiss_Index_search_with_ids")]
    int index_search_with_ids(Index index, int64 n, [CCode (array_length = false)] float* x, int64 k, IDSelector? sel, [CCode (array_length = false)] float* distances, [CCode (array_length = false)] int64* labels);
    
    [CCode (cname = "faiss_Index_d")]
    int index_d(Index index);
    
    [CCode (cname = "faiss_Index_ntotal")]
    int64 index_ntotal(Index index);
    
    [CCode (cname = "faiss_write_index_fname")]
    int write_index_fname(Index index, string fname);
    
    [CCode (cname = "faiss_read_index_fname")]
    int read_index_fname(string fname, int io_flags, out Index index);
    
    [CCode (cname = "faiss_Index_reconstruct")]
    int index_reconstruct(Index index, int64 key, [CCode (array_length = false)] float* recons);
}
