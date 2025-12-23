// C header for FAISS C++ wrapper
// This header is included by Vala-generated C code, so it must be pure C (no C++)

#ifndef FAISS_C_WRAPPER_H
#define FAISS_C_WRAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque pointer types
typedef void* FaissIndex;
typedef void* FaissIndexHNSW;
typedef void* FaissIDSelector;

// Create IndexHNSWFlat
int faiss_IndexHNSWFlat_new(FaissIndexHNSW* index, int64_t d, int64_t M);

// Create IDSelectorBatch
int faiss_IDSelectorBatch_new(FaissIDSelector** selector, int64_t n, const int64_t* ids);

// Free IDSelector
void faiss_IDSelector_free(FaissIDSelector selector);

// Free index
void faiss_Index_free(FaissIndex index);

// Add vectors
int faiss_Index_add(FaissIndex index, int64_t n, const float* x);

// Add vectors with IDs
int faiss_Index_add_with_ids(FaissIndex index, int64_t n, const float* x, const int64_t* xids);

// Search (without filtering)
int faiss_Index_search(FaissIndex index, int64_t n, const float* x, int64_t k, float* distances, int64_t* labels);

// Search with IDSelector (for filtering)
int faiss_Index_search_with_ids(FaissIndex index, int64_t n, const float* x, int64_t k, FaissIDSelector sel, float* distances, int64_t* labels);

// Get dimension
int faiss_Index_d(FaissIndex index);

// Get total vectors
int64_t faiss_Index_ntotal(FaissIndex index);

// Write index to file
int faiss_write_index_fname(FaissIndex index, const char* fname);

// Read index from file
int faiss_read_index_fname(const char* fname, int io_flags, FaissIndex* index);

// Reconstruct vector by ID
int faiss_Index_reconstruct(FaissIndex index, int64_t key, float* recons);

#ifdef __cplusplus
}
#endif

#endif // FAISS_C_WRAPPER_H

