[CCode (cprefix = "faiss_", cheader_filename = "faiss/c_api/IndexFlat_c.h,faiss/c_api/Index_c.h,faiss/c_api/AuxIndexStructures_c.h")]
namespace Faiss {
    [CCode (cname = "FaissIndex")]
    [SimpleType]
    struct Index : void* {}
    
    [CCode (cname = "FaissIndexFlat")]
    [SimpleType]
    struct IndexFlat : void* {}
    
    [CCode (cname = "FaissIndexFlatIP")]
    [SimpleType]
    struct IndexFlatIP : void* {}
    
    [CCode (cname = "FaissIndexIDMap")]
    [SimpleType]
    struct IndexIDMap : void* {}
    
    [CCode (cname = "faiss_IndexFlatIP_new")]
    int index_flat_ip_new(out IndexFlatIP index, uint64 d);
    
    [CCode (cname = "faiss_Index_free")]
    void index_free(Index index);
    
    [CCode (cname = "faiss_Index_add")]
    int index_add(Index index, long n, [CCode (array_length = false)] float* x);
    
    [CCode (cname = "faiss_Index_add_with_ids")]
    int index_add_with_ids(Index index, long n, [CCode (array_length = false)] float* x, [CCode (array_length = false)] long* xids);
    
    [CCode (cname = "faiss_Index_search")]
    int index_search(Index index, long n, [CCode (array_length = false)] float* x, long k, [CCode (array_length = false)] float* distances, [CCode (array_length = false)] long* labels);
    
    [CCode (cname = "faiss_Index_d")]
    uint64 index_d(Index index);
    
    [CCode (cname = "faiss_Index_ntotal")]
    uint64 index_ntotal(Index index);
    
    [CCode (cname = "faiss_Index_write")]
    int index_write(Index index, string fname);
    
    [CCode (cname = "faiss_Index_read")]
    int index_read(Index index, string fname);
}