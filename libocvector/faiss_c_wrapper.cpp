// Minimal C wrapper for FAISS C++ API
// Since libfaiss-dev doesn't include the C API wrapper implementation,
// we create our own minimal wrapper that directly uses the C++ API

#include <faiss/IndexFlat.h>
#include <faiss/index_io.h>
#include <cstdint>
#include <cstdio>
#include <exception>

extern "C" {

// Opaque pointer type
typedef void* FaissIndex;
typedef void* FaissIndexFlatIP;

// Create IndexFlatIP
int faiss_IndexFlatIP_new_with(
    FaissIndexFlatIP* index,
    int64_t d
) {
    if (!index) {
        fprintf(stderr, "[FAISS] faiss_IndexFlatIP_new_with: index pointer is null\n");
        return -1;
    }
    if (d <= 0) {
        fprintf(stderr, "[FAISS] faiss_IndexFlatIP_new_with: invalid dimension %ld\n", d);
        return -1;
    }
    try {
        *index = new faiss::IndexFlatIP((faiss::idx_t)d);
        fprintf(stderr, "[FAISS] faiss_IndexFlatIP_new_with: created index with dimension %ld\n", d);
        return 0;
    } catch (const std::exception& e) {
        fprintf(stderr, "[FAISS] faiss_IndexFlatIP_new_with: exception: %s\n", e.what());
        return -1;
    } catch (...) {
        fprintf(stderr, "[FAISS] faiss_IndexFlatIP_new_with: unknown exception\n");
        return -1;
    }
}

// Free index
void faiss_Index_free(FaissIndex index) {
    if (index) {
        fprintf(stderr, "[FAISS] faiss_Index_free: freeing index\n");
        delete static_cast<faiss::Index*>(index);
    } else {
        fprintf(stderr, "[FAISS] faiss_Index_free: index is null, nothing to free\n");
    }
}

// Add vectors
int faiss_Index_add(
    FaissIndex index,
    int64_t n,
    const float* x
) {
    if (!index) {
        fprintf(stderr, "[FAISS] faiss_Index_add: index is null\n");
        return -1;
    }
    if (!x) {
        fprintf(stderr, "[FAISS] faiss_Index_add: x pointer is null\n");
        return -1;
    }
    if (n <= 0) {
        fprintf(stderr, "[FAISS] faiss_Index_add: invalid n=%ld\n", n);
        return -1;
    }
    try {
        static_cast<faiss::Index*>(index)->add((faiss::idx_t)n, x);
        fprintf(stderr, "[FAISS] faiss_Index_add: added %ld vectors\n", n);
        return 0;
    } catch (const std::exception& e) {
        fprintf(stderr, "[FAISS] faiss_Index_add: exception: %s\n", e.what());
        return -1;
    } catch (...) {
        fprintf(stderr, "[FAISS] faiss_Index_add: unknown exception\n");
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
        fprintf(stderr, "[FAISS] faiss_Index_add_with_ids: index is null\n");
        return -1;
    }
    if (!x) {
        fprintf(stderr, "[FAISS] faiss_Index_add_with_ids: x pointer is null\n");
        return -1;
    }
    if (!xids) {
        fprintf(stderr, "[FAISS] faiss_Index_add_with_ids: xids pointer is null\n");
        return -1;
    }
    if (n <= 0) {
        fprintf(stderr, "[FAISS] faiss_Index_add_with_ids: invalid n=%ld\n", n);
        return -1;
    }
    try {
        static_cast<faiss::Index*>(index)->add_with_ids((faiss::idx_t)n, x, xids);
        fprintf(stderr, "[FAISS] faiss_Index_add_with_ids: added %ld vectors with IDs\n", n);
        return 0;
    } catch (const std::exception& e) {
        fprintf(stderr, "[FAISS] faiss_Index_add_with_ids: exception: %s\n", e.what());
        return -1;
    } catch (...) {
        fprintf(stderr, "[FAISS] faiss_Index_add_with_ids: unknown exception\n");
        return -1;
    }
}

// Search
int faiss_Index_search(
    FaissIndex index,
    int64_t n,
    const float* x,
    int64_t k,
    float* distances,
    int64_t* labels
) {
    fprintf(stderr, "[FAISS] faiss_Index_search: called with n=%ld, k=%ld\n", n, k);
    
    if (!index) {
        fprintf(stderr, "[FAISS] faiss_Index_search: index is null\n");
        return -1;
    }
    if (!x) {
        fprintf(stderr, "[FAISS] faiss_Index_search: x pointer is null\n");
        return -1;
    }
    if (!distances) {
        fprintf(stderr, "[FAISS] faiss_Index_search: distances pointer is null\n");
        return -1;
    }
    if (!labels) {
        fprintf(stderr, "[FAISS] faiss_Index_search: labels pointer is null\n");
        return -1;
    }
    if (n <= 0) {
        fprintf(stderr, "[FAISS] faiss_Index_search: invalid n=%ld\n", n);
        return -1;
    }
    if (k <= 0) {
        fprintf(stderr, "[FAISS] faiss_Index_search: invalid k=%ld\n", k);
        return -1;
    }
    
    // Check index state
    faiss::Index* idx = static_cast<faiss::Index*>(index);
    fprintf(stderr, "[FAISS] faiss_Index_search: index dimension=%d, ntotal=%ld\n", idx->d, idx->ntotal);
    
    if (idx->ntotal == 0) {
        fprintf(stderr, "[FAISS] faiss_Index_search: warning - index is empty (ntotal=0)\n");
    }
    
    try {
        fprintf(stderr, "[FAISS] faiss_Index_search: calling FAISS search...\n");
        idx->search(
            (faiss::idx_t)n,
            x,
            (faiss::idx_t)k,
            distances,
            labels
        );
        fprintf(stderr, "[FAISS] faiss_Index_search: search completed successfully\n");
        return 0;
    } catch (const std::exception& e) {
        fprintf(stderr, "[FAISS] faiss_Index_search: exception: %s\n", e.what());
        return -1;
    } catch (...) {
        fprintf(stderr, "[FAISS] faiss_Index_search: unknown exception\n");
        return -1;
    }
}

// Get dimension
int faiss_Index_d(FaissIndex index) {
    if (!index) {
        fprintf(stderr, "[FAISS] faiss_Index_d: index is null\n");
        return -1;
    }
    int d = static_cast<faiss::Index*>(index)->d;
    fprintf(stderr, "[FAISS] faiss_Index_d: dimension=%d\n", d);
    return d;
}

// Get total vectors
int64_t faiss_Index_ntotal(FaissIndex index) {
    if (!index) {
        fprintf(stderr, "[FAISS] faiss_Index_ntotal: index is null\n");
        return -1;
    }
    int64_t ntotal = static_cast<faiss::Index*>(index)->ntotal;
    fprintf(stderr, "[FAISS] faiss_Index_ntotal: ntotal=%ld\n", ntotal);
    return ntotal;
}

// Write index to file
int faiss_write_index_fname(
    FaissIndex index,
    const char* fname
) {
    if (!index) {
        fprintf(stderr, "[FAISS] faiss_write_index_fname: index is null\n");
        return -1;
    }
    if (!fname) {
        fprintf(stderr, "[FAISS] faiss_write_index_fname: fname is null\n");
        return -1;
    }
    try {
        fprintf(stderr, "[FAISS] faiss_write_index_fname: writing to %s\n", fname);
        faiss::write_index(static_cast<faiss::Index*>(index), fname);
        fprintf(stderr, "[FAISS] faiss_write_index_fname: write completed\n");
        return 0;
    } catch (const std::exception& e) {
        fprintf(stderr, "[FAISS] faiss_write_index_fname: exception: %s\n", e.what());
        return -1;
    } catch (...) {
        fprintf(stderr, "[FAISS] faiss_write_index_fname: unknown exception\n");
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
        fprintf(stderr, "[FAISS] faiss_read_index_fname: fname is null\n");
        return -1;
    }
    if (!index) {
        fprintf(stderr, "[FAISS] faiss_read_index_fname: index pointer is null\n");
        return -1;
    }
    try {
        fprintf(stderr, "[FAISS] faiss_read_index_fname: reading from %s\n", fname);
        *index = faiss::read_index(fname, io_flags);
        fprintf(stderr, "[FAISS] faiss_read_index_fname: read completed\n");
        return 0;
    } catch (const std::exception& e) {
        fprintf(stderr, "[FAISS] faiss_read_index_fname: exception: %s\n", e.what());
        return -1;
    } catch (...) {
        fprintf(stderr, "[FAISS] faiss_read_index_fname: unknown exception\n");
        return -1;
    }
}

} // extern "C"
