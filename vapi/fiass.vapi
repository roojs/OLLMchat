[CCode (cheader_filename = "faiss/c_api/IndexFlat_c.h,faiss/c_api/Index_c.h,faiss/c_api/index_io_c.h")]
namespace Faiss {
    [CCode (cname = "FaissIndex", has_type_id = false, free_function = "faiss_Index_free")]
    [Compact]
    [SimpleType]
    public class Index {
        // Method to explicitly free the index (useful when free_function isn't available)
        [CCode (cname = "faiss_Index_free")]
        public void free();
    }
    
    [CCode (cname = "FaissIndexFlat", has_type_id = false)]
    [Compact]
    [SimpleType]
    public class IndexFlat : Index {}
    
    [CCode (cname = "FaissIndexFlatIP", has_type_id = false)]
    [Compact]
    [SimpleType]
    public class IndexFlatIP : Index {}
    
    [CCode (cname = "FaissIndexIDMap", has_type_id = false)]
    [Compact]
    [SimpleType]
    public class IndexIDMap : Index {}
    
    [CCode (cname = "faiss_IndexFlatIP_new_with")]
    int index_flat_ip_new(out IndexFlatIP index, int64 d);
    
    [CCode (cname = "faiss_Index_add")]
    int index_add(Index index, int64 n, [CCode (array_length = false)] float* x);
    
    [CCode (cname = "faiss_Index_add_with_ids")]
    int index_add_with_ids(Index index, int64 n, [CCode (array_length = false)] float* x, [CCode (array_length = false)] int64* xids);
    
    [CCode (cname = "faiss_Index_search")]
    int index_search(Index index, int64 n, [CCode (array_length = false)] float* x, int64 k, [CCode (array_length = false)] float* distances, [CCode (array_length = false)] int64* labels);
    
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