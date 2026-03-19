# Vector search results — fix plan (first effort)

**Status:** planning  
**Area:** FAISS / vector search / `libocvector` (and callers)

## Problem (short)

Vector search results are wrong or inconsistent when relying on **in-index filtering** against the persistent FAISS-backed store. This plan describes a **first-effort** workaround: search a **temporary in-memory** index built only from the vectors we care about, then map IDs back to the real database IDs.

*(Expand this section with concrete symptoms, repro, and links to issues/commits when known.)*

---

## Approach — in-memory subset index (keep existing path)

**Do not delete the current filtered-FAISS path yet.** Put **all temp-label → source-id replacement** in **`Index.copy_from`** + **`Index.search`**. In **`Search.execute()`** the only behavioral change is: after the query embedding, **create tmp index**, **`copy_from` → `uint64`**, **`search` on the copy with `selector == null`**; **everything after `faiss_results` stays the same** as today (valid rows, metadata lookup, `SearchResult`, `debug_target`) because `document_id` is already the real vector id.

### 1. New search method (parallel to existing)

- Leave **all existing** post-FAISS code in place (unchanged).
- Implement **`Index.copy_from` (return count)** + **`map`** (label → source id) + **`search()` remap**; **`Search.vala`** diff is only the **two calls** that build the copy + **`search` on `copy` instead of `vector_db.index` + selector**.

### 2. Build a temporary in-memory vector DB

- Create a **fresh, in-memory** FAISS (or same backend) index with the **same dimensionality and metric** as the persistent index.
- **Extract** the candidate vectors from our DB (same source as today’s “what we would filter” scope — document which table/store and embedding field).
- For each vector added to the temp index:
  - Assign a **temporary contiguous ID** (`0 … n-1` or whatever the temp index uses).
  - Maintain a map: **`temp_id → original_id`** (and if needed, the reverse for debugging).

### 3. Search on the in-memory index

- Run the query embedding against this temp index **without** post-hoc ID filtering (the index already *is* the filtered set).
- Retrieve top-`k` (or whatever parameters the current API uses).

### 4. Remap results and continue as before

- **Inside `Index.search`:** replace each hit’s **temp label** with the **source vector id** when **`map.length > 0`**.
- **`Search`:** no separate remap step — same assembly as the IDSelector path.

---

## Concrete code proposals

### `libocvector/Search/Search.vala` — `execute()` diff (rest unchanged)

Replace **only** the block from **`id_array`** through **`vector_db.index.search(..., selector)`** with the tmp-index path below. **Do not** duplicate **`filtered_set`**: keep the **existing** construction in `Search.execute()` (same place as today — after the ID debug lines, before FAISS). That set is for **`debug_target`** and the **`filtered_set.contains`** check when building **`valid_vector_ids`**; on the copy path that check is **redundant** (hits are already from the subset) but **harmless**, so the tail of **`execute()`** can stay one shared block.

**Do not** add a separate `execute_on_copy`. Use the same variable name **`faiss_results`** and the same code from **`valid_vector_ids` through `return search_results`**.

```vala
// after: var query_vector = embed_response.embeddings.get_vector(0);
// … keep: filtered_set loop + debug_ast_path block (unchanged). Omit id_array / IDSelector when using copy path …

if (this.vector_db.index == null) {
	throw new GLib.IOError.FAILED("Vector database index is not initialized");
}

var copy = new OLLMvector.Index.create_tmp_hnsw(this.vector_db.index.dimension);
uint64 copied = copy.copy_from(this.vector_db.index, this.filtered_vector_ids);
if (copied == 0) {
	return new Gee.ArrayList<SearchResult>();
}

uint64 k = this.max_results;
if (k > copied) {
	k = copied;
}

OLLMvector.SearchResult[] faiss_results = copy.search(query_vector, k, null);

/*
 * OLD — replace the block above with:
 *
 * var id_array = new int64[this.filtered_vector_ids.size];
 * for (int i = 0; i < this.filtered_vector_ids.size; i++) {
 *     id_array[i] = this.filtered_vector_ids[i];
 * }
 * Faiss.IDSelector? selector = null;
 * if (Faiss.id_selector_batch_new(out selector, (int64)this.filtered_vector_ids.size, id_array) != 0) {
 *     throw new GLib.IOError.FAILED("Failed to create IDSelector for filtering");
 * }
 * OLLMvector.SearchResult[] faiss_results =
 *     this.vector_db.index.search(query_vector, this.max_results, selector);
 */

// --- same as before from here: valid_vector_ids / metadata_map / SearchResult list / debug_target ---
```

### `libocvector/Index.vala` — tmp index + `copy_from` + `map` + `search` remap

```vala
/**
 * `map[i]` = source index vector_id for FAISS label `i` (only `i < get_total_vectors()` used).
 * May be longer than `ntotal` when `copy_from` skips some ids; `search()` remaps using `get_total_vectors()` as the label bound.
 * Empty `{}`: no remap (normal on-disk index). Initialize to `{}` in every constructor.
 */
public int64[] map { get; private set; default = {}; }
```

```vala
/**
 * Call only on an empty tmp index. For each id in @source_vector_ids, reconstruct from @src,
 * `add_vectors` in order (FAISS labels 0,1,…), then set `this.map[i]` = source id for label @i.
 */
/** @return number of vectors added (0 if none); use for `k = min(max_results, copied)` — no `get_total_vectors()` needed */
public uint64 copy_from(OLLMvector.Index src, Gee.ArrayList<int> source_vector_ids) throws GLib.Error
{
	if (src.dimension != this.dimension) {
		throw new GLib.IOError.FAILED("copy_from: dimension mismatch");
	}
	var batch = new OLLMchat.Response.FloatArray(this.dimension);
	int n_ids = source_vector_ids.size;
	var map = new int64[n_ids];
	int t = 0;

	foreach (var orig_id in source_vector_ids) {
		float[] row;
		try {
			row = src.reconstruct_vector(orig_id);
		} catch (GLib.Error e) {
			GLib.warning("copy_from: skip vector_id %d: %s", orig_id, e.message);
			continue;
		}
		batch.add(row);
		map[t] = orig_id;
		t++;
	}

	if (t == 0) {
		this.map = {};
		return 0;
	}

	this.add_vectors(batch);
	this.map = map;
	return (uint64)t;
}
```

```vala
public SearchResult[] search(float[] query_vector, uint64 k = 5, Faiss.IDSelector? selector = null) throws Error
{
	/* existing: distances[], labels[], index_search_with_ids, build results[] */

	if (this.map.length > 0) {
		int64 nvec = (int64)this.get_total_vectors();
		for (int i = 0; i < results.length; i++) {
			int64 lid = results[i].document_id;
			if (lid < 0 || lid >= nvec) {
				continue;
			}
			results[i].document_id = this.map[lid];
		}
	}

	return results;
}
```

```vala
/**
 * In-RAM HNSWFlat (M=16). `map` is `{}` until `copy_from` fills it.
 */
public Index.create_tmp_hnsw(int dim) throws GLib.Error
{
	Object();
	this.filename = "";
	this.dimension = dim;
	this.normalized = false;
	this.map = {};

	Faiss.IndexHNSW hnsw_index;
	if (Faiss.index_hnsw_flat_new(out hnsw_index, (int64)dim, 16) != 0) {
		throw new GLib.IOError.FAILED("Failed to create tmp FAISS HNSW index");
	}
	this.index = (owned)hnsw_index;
}
```

```vala
// Search: create tmp, copied = copy_from(...), k = min(max_results, copied), faiss_results = copy.search(..., k, null)
// faiss_results[].document_id are source ids — same downstream code as IDSelector path
```

### `libocvector/faiss_c_wrapper.*` — no change required

```c
// existing index_search_with_ids(..., sel=NULL) is enough for subset search
```

---

## Checklist

- [ ] In `Search.execute()`: splice **create tmp + `copy_from` (use return) + `copy.search`**; keep **one** post-`faiss_results` pipeline.
- [ ] Implement `Index.create_tmp_hnsw`, **`copy_from` → `uint64`**, **`map`** (empty = no remap), and **`search()` remap** when **`map.length > 0`**.
- [ ] Add tests or a small CLI/script to compare old vs new on sample data.
- [ ] Roll back by uncommenting the old `execute()` block if needed (no caller flags).
- [ ] Document performance characteristics and limits in this file or `docs/plans/`.

---

## Related

- `docs/plans/2.20.10-faiss-vector-dump-compare.md` — FAISS dump/compare work (if applicable to debugging this issue).
