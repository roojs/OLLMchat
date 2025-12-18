// Minimal C wrapper for FAISS C++ API
// Since libfaiss-dev doesn't include the C API wrapper implementation,
// we create our own minimal wrapper that directly uses the C++ API

#include <faiss/IndexFlat.h>
#include <faiss/index_io.h>
#include <cstdint>

extern "C" {

// Opaque pointer type
typedef void* FaissIndex;
typedef void* FaissIndexFlatIP;

// Create IndexFlatIP
int faiss_IndexFlatIP_new_with(FaissIndexFlatIP* index, int64_t d) {
    try {
        *index = new faiss::IndexFlatIP((faiss::idx_t)d);
        return 0;
    } catch (...) {
        return -1;
    }
}

// Free index
void faiss_Index_free(FaissIndex index) {
    if (index) {
        delete static_cast<faiss::Index*>(index);
    }
}

// Add vectors
int faiss_Index_add(FaissIndex index, int64_t n, const float* x) {
    try {
        static_cast<faiss::Index*>(index)->add((faiss::idx_t)n, x);
        return 0;
    } catch (...) {
        return -1;
    }
}

// Add vectors with IDs
int faiss_Index_add_with_ids(FaissIndex index, int64_t n, const float* x, const int64_t* xids) {
    try {
        static_cast<faiss::Index*>(index)->add_with_ids((faiss::idx_t)n, x, xids);
        return 0;
    } catch (...) {
        return -1;
    }
}

// Search
int faiss_Index_search(FaissIndex index, int64_t n, const float* x, int64_t k, float* distances, int64_t* labels) {
    try {
        static_cast<faiss::Index*>(index)->search((faiss::idx_t)n, x, (faiss::idx_t)k, distances, labels);
        return 0;
    } catch (...) {
        return -1;
    }
}

// Get dimension
int faiss_Index_d(FaissIndex index) {
    return static_cast<faiss::Index*>(index)->d;
}

// Get total vectors
int64_t faiss_Index_ntotal(FaissIndex index) {
    return static_cast<faiss::Index*>(index)->ntotal;
}

// Write index to file
int faiss_write_index_fname(FaissIndex index, const char* fname) {
    try {
        faiss::write_index(static_cast<faiss::Index*>(index), fname);
        return 0;
    } catch (...) {
        return -1;
    }
}

// Read index from file
int faiss_read_index_fname(const char* fname, int io_flags, FaissIndex* index) {
    try {
        *index = faiss::read_index(fname, io_flags);
        return 0;
    } catch (...) {
        return -1;
    }
}

} // extern "C"
