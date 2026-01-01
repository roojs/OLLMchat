// Minimal C wrapper for FAISS C++ API
// Since libfaiss-dev doesn't include the C API wrapper implementation,
// we create our own minimal wrapper that directly uses the C++ API

#include <faiss/IndexHNSW.h>
#include <faiss/impl/IDSelector.h>
#include <faiss/impl/HNSW.h>
#include <faiss/index_io.h>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <vector>
#include <glib.h>

extern "C" {

// Opaque pointer types
typedef void* FaissIndex;
typedef void* FaissIndexHNSW;
typedef void* FaissIDSelector;

// Create IndexHNSWFlat
int faiss_IndexHNSWFlat_new(
    FaissIndexHNSW* index,
    int64_t d,
    int64_t M
) {
    if (!index) {
        g_debug("[FAISS] faiss_IndexHNSWFlat_new: index pointer is null");
        return -1;
    }
    if (d <= 0) {
        g_debug("[FAISS] faiss_IndexHNSWFlat_new: invalid dimension %ld", d);
        return -1;
    }
    if (M <= 0) {
        g_debug("[FAISS] faiss_IndexHNSWFlat_new: invalid M %ld (using default 32)", M);
        M = 32;
    }
    try {
        faiss::IndexHNSWFlat* hnsw_index = new faiss::IndexHNSWFlat((faiss::idx_t)d, (int)M);
        // Set default parameters
        hnsw_index->hnsw.efConstruction = 64;
        hnsw_index->hnsw.efSearch = 32;
        *index = hnsw_index;
        g_debug("[FAISS] faiss_IndexHNSWFlat_new: created HNSW index with dimension %ld, M=%ld", d, M);
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_IndexHNSWFlat_new: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_IndexHNSWFlat_new: unknown exception");
        return -1;
    }
}

// Create IDSelectorBatch for filtering by vector IDs
int faiss_IDSelectorBatch_new(
    FaissIDSelector** selector,
    int64_t n,
    const int64_t* ids
) {
    if (!selector) {
        g_debug("[FAISS] faiss_IDSelectorBatch_new: selector pointer is null");
        return -1;
    }
    if (n < 0) {
        g_debug("[FAISS] faiss_IDSelectorBatch_new: invalid n=%ld", n);
        return -1;
    }
    if (n == 0) {
        // Empty selector - return null (will search all)
        *selector = nullptr;
        return 0;
    }
    if (!ids) {
        g_debug("[FAISS] faiss_IDSelectorBatch_new: ids pointer is null");
        return -1;
    }
    try {
        // IDSelectorBatch constructor takes (size_t n, const idx_t* ids)
        faiss::IDSelectorBatch* sel = new faiss::IDSelectorBatch((size_t)n, ids);
        // selector is FaissIDSelector** which is void***, so *selector is void**
        // We need to assign the void* to what *selector points to
        void** sel_ptr = reinterpret_cast<void**>(selector);
        *sel_ptr = static_cast<void*>(sel);
        g_debug("[FAISS] faiss_IDSelectorBatch_new: created IDSelector with %ld IDs", n);
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_IDSelectorBatch_new: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_IDSelectorBatch_new: unknown exception");
        return -1;
    }
}

// Free IDSelector
void faiss_IDSelector_free(FaissIDSelector selector) {
    if (selector) {
        delete static_cast<faiss::IDSelector*>(selector);
    }
}

// Free index
void faiss_Index_free(FaissIndex index) {
    if (index) {
        g_debug("[FAISS] faiss_Index_free: freeing index");
        delete static_cast<faiss::Index*>(index);
    } else {
        g_debug("[FAISS] faiss_Index_free: index is null, nothing to free");
    }
}

// Add vectors
int faiss_Index_add(
    FaissIndex index,
    int64_t n,
    const float* x
) {
    if (!index) {
        g_debug("[FAISS] faiss_Index_add: index is null");
        return -1;
    }
    if (!x) {
        g_debug("[FAISS] faiss_Index_add: x pointer is null");
        return -1;
    }
    if (n <= 0) {
        g_debug("[FAISS] faiss_Index_add: invalid n=%ld", n);
        return -1;
    }
    try {
        static_cast<faiss::Index*>(index)->add((faiss::idx_t)n, x);
        g_debug("[FAISS] faiss_Index_add: added %ld vectors", n);
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_Index_add: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_Index_add: unknown exception");
        return -1;
    }
}

// Add vectors with IDs
int faiss_Index_add_with_ids(
    FaissIndex index,
    int64_t n,
    const float* x,
    const int64_t* xids
) {
    if (!index) {
        g_debug("[FAISS] faiss_Index_add_with_ids: index is null");
        return -1;
    }
    if (!x) {
        g_debug("[FAISS] faiss_Index_add_with_ids: x pointer is null");
        return -1;
    }
    if (!xids) {
        g_debug("[FAISS] faiss_Index_add_with_ids: xids pointer is null");
        return -1;
    }
    if (n <= 0) {
        g_debug("[FAISS] faiss_Index_add_with_ids: invalid n=%ld", n);
        return -1;
    }
    try {
        static_cast<faiss::Index*>(index)->add_with_ids((faiss::idx_t)n, x, xids);
        g_debug("[FAISS] faiss_Index_add_with_ids: added %ld vectors with IDs", n);
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_Index_add_with_ids: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_Index_add_with_ids: unknown exception");
        return -1;
    }
}

// Search (without filtering)
int faiss_Index_search(
    FaissIndex index,
    int64_t n,
    const float* x,
    int64_t k,
    float* distances,
    int64_t* labels
) {
    g_debug("[FAISS] faiss_Index_search: called with n=%ld, k=%ld", n, k);
    
    if (!index) {
        g_debug("[FAISS] faiss_Index_search: index is null");
        return -1;
    }
    if (!x) {
        g_debug("[FAISS] faiss_Index_search: x pointer is null");
        return -1;
    }
    if (!distances) {
        g_debug("[FAISS] faiss_Index_search: distances pointer is null");
        return -1;
    }
    if (!labels) {
        g_debug("[FAISS] faiss_Index_search: labels pointer is null");
        return -1;
    }
    if (n <= 0) {
        g_debug("[FAISS] faiss_Index_search: invalid n=%ld", n);
        return -1;
    }
    if (k <= 0) {
        g_debug("[FAISS] faiss_Index_search: invalid k=%ld", k);
        return -1;
    }
    
    // Check index state
    faiss::Index* idx = static_cast<faiss::Index*>(index);
    g_debug("[FAISS] faiss_Index_search: index dimension=%d, ntotal=%ld", idx->d, idx->ntotal);
    
    if (idx->ntotal == 0) {
        g_debug("[FAISS] faiss_Index_search: warning - index is empty (ntotal=0)");
    }
    
    try {
        g_debug("[FAISS] faiss_Index_search: calling FAISS search...");
        idx->search(
            (faiss::idx_t)n,
            x,
            (faiss::idx_t)k,
            distances,
            labels
        );
        g_debug("[FAISS] faiss_Index_search: search completed successfully");
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_Index_search: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_Index_search: unknown exception");
        return -1;
    }
}

// Search with IDSelector (for filtering)
int faiss_Index_search_with_ids(
    FaissIndex index,
    int64_t n,
    const float* x,
    int64_t k,
    FaissIDSelector sel,
    float* distances,
    int64_t* labels
) {
    g_debug("[FAISS] faiss_Index_search_with_ids: called with n=%ld, k=%ld, selector=%s", 
        n, k, sel ? "set" : "null");
    
    if (!index) {
        g_debug("[FAISS] faiss_Index_search_with_ids: index is null");
        return -1;
    }
    if (!x) {
        g_debug("[FAISS] faiss_Index_search_with_ids: x pointer is null");
        return -1;
    }
    if (!distances) {
        g_debug("[FAISS] faiss_Index_search_with_ids: distances pointer is null");
        return -1;
    }
    if (!labels) {
        g_debug("[FAISS] faiss_Index_search_with_ids: labels pointer is null");
        return -1;
    }
    if (n <= 0) {
        g_debug("[FAISS] faiss_Index_search_with_ids: invalid n=%ld", n);
        return -1;
    }
    if (k <= 0) {
        g_debug("[FAISS] faiss_Index_search_with_ids: invalid k=%ld", k);
        return -1;
    }
    
    faiss::Index* idx = static_cast<faiss::Index*>(index);
    
    // If no selector, use regular search
    if (!sel) {
        return faiss_Index_search(index, n, x, k, distances, labels);
    }
    
    try {
        const faiss::IDSelector* selector = static_cast<const faiss::IDSelector*>(sel);
        
        // Check if this is an HNSW index - it needs SearchParametersHNSW
        faiss::IndexHNSW* hnsw_idx = dynamic_cast<faiss::IndexHNSW*>(idx);
        if (hnsw_idx) {
            faiss::SearchParametersHNSW params;
            params.sel = const_cast<faiss::IDSelector*>(selector);
            idx->search(
                (faiss::idx_t)n,
                x,
                (faiss::idx_t)k,
                distances,
                labels,
                &params
            );
        } else {
            // For other index types, use base SearchParameters
            faiss::SearchParameters params;
            params.sel = const_cast<faiss::IDSelector*>(selector);
            idx->search(
                (faiss::idx_t)n,
                x,
                (faiss::idx_t)k,
                distances,
                labels,
                &params
            );
        }
        g_debug("[FAISS] faiss_Index_search_with_ids: search completed successfully");
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_Index_search_with_ids: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_Index_search_with_ids: unknown exception");
        return -1;
    }
}

// Get dimension
int faiss_Index_d(FaissIndex index) {
    if (!index) {
        g_debug("[FAISS] faiss_Index_d: index is null");
        return -1;
    }
    int d = static_cast<faiss::Index*>(index)->d;
    g_debug("[FAISS] faiss_Index_d: dimension=%d", d);
    return d;
}

// Get total vectors
int64_t faiss_Index_ntotal(FaissIndex index) {
    if (!index) {
        g_debug("[FAISS] faiss_Index_ntotal: index is null");
        return -1;
    }
    int64_t ntotal = static_cast<faiss::Index*>(index)->ntotal;
    g_debug("[FAISS] faiss_Index_ntotal: ntotal=%ld", ntotal);
    return ntotal;
}

// Write index to file
int faiss_write_index_fname(
    FaissIndex index,
    const char* fname
) {
    if (!index) {
        g_debug("[FAISS] faiss_write_index_fname: index is null");
        return -1;
    }
    if (!fname) {
        g_debug("[FAISS] faiss_write_index_fname: fname is null");
        return -1;
    }
    try {
        g_debug("[FAISS] faiss_write_index_fname: writing to %s", fname);
        faiss::write_index(static_cast<faiss::Index*>(index), fname);
        g_debug("[FAISS] faiss_write_index_fname: write completed");
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_write_index_fname: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_write_index_fname: unknown exception");
        return -1;
    }
}

// Read index from file
int faiss_read_index_fname(
    const char* fname,
    int io_flags,
    FaissIndex* index
) {
    if (!fname) {
        g_debug("[FAISS] faiss_read_index_fname: fname is null");
        return -1;
    }
    if (!index) {
        g_debug("[FAISS] faiss_read_index_fname: index pointer is null");
        return -1;
    }
    try {
        g_debug("[FAISS] faiss_read_index_fname: reading from %s", fname);
        *index = faiss::read_index(fname, io_flags);
        g_debug("[FAISS] faiss_read_index_fname: read completed");
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_read_index_fname: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_read_index_fname: unknown exception");
        return -1;
    }
}

// Reconstruct vector by ID
int faiss_Index_reconstruct(
    FaissIndex index,
    int64_t key,
    float* recons
) {
    if (!index) {
        g_debug("[FAISS] faiss_Index_reconstruct: index is null");
        return -1;
    }
    if (!recons) {
        g_debug("[FAISS] faiss_Index_reconstruct: recons pointer is null");
        return -1;
    }
    if (key < 0) {
        g_debug("[FAISS] faiss_Index_reconstruct: invalid key=%ld", key);
        return -1;
    }
    try {
        faiss::Index* idx = static_cast<faiss::Index*>(index);
        if (key >= idx->ntotal) {
            g_debug("[FAISS] faiss_Index_reconstruct: key %ld >= ntotal %ld", key, idx->ntotal);
            return -1;
        }
        idx->reconstruct((faiss::idx_t)key, recons);
        return 0;
    } catch (const std::exception& e) {
        g_debug("[FAISS] faiss_Index_reconstruct: exception: %s", e.what());
        return -1;
    } catch (...) {
        g_debug("[FAISS] faiss_Index_reconstruct: unknown exception");
        return -1;
    }
}

} // extern "C"
