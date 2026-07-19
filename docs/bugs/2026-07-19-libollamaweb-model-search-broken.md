# libollamaweb Add Model search broken (Desktop + Android)

**Status:** ✔️ Applied — await Desktop/Android UI verify

**Started:** 2026-07-19

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval.

**Related:**

- ℹ️ Prior FIXED case (same surface): [`docs/bugs/done/2026-06-02-FIXED-libollamaweb-add-model-search-spin-no-results.md`](done/2026-06-02-FIXED-libollamaweb-add-model-search-spin-no-results.md)
- ℹ️ Plans: `docs/plans/4.8-ollama-web-live-search.md`, `docs/plans/4.8.1-ollama-web-phase-2-1-add-model.md`
- ✔️ Commit: `ac21b081` — `ollmweb fix` (Parser + initial log)

---

## Problem

🔷 **Add Model** live search via **`libollamaweb`** (ollama.com model catalog) is **completely broken** on **Desktop and Android**.

**Expected:** Typing a query (e.g. `llama`, `qwen`) returns shallow search hits in the pulldown after debounce + network.

**Actual:** Empty results — parser matched no rows after ollama.com dropped `x-test-model`.

---

## Reproduction

### UI

1. Open **Settings → Add Model**.
2. Type a non-empty query (e.g. `llama`).
3. Wait for debounce (~2 s) and network.
4. Observe: no usable model rows (Desktop and Android).

### CLI

```bash
meson test -C build --suite ollamaweb
./build/examples/oc-test-ollamaweb --live llama
./build/examples/oc-test-ollamaweb --session llama
```

**Binary:** `build/examples/oc-test-ollamaweb`  
**Fixtures:** `tests/data/ollamaweb/`

---

## Root cause

✔️ **ollama.com search HTML dropped `x-test-model` on result `<li>`s** (and related test attrs). `Parser.parse_search` matched nothing → empty hit lists on Desktop and Android (same library).

Site build ~`2026-07-17`. New rows are `#searchresults ul[role=list] > li` with `a[href^="/library/"]` (no `x-test-*`).

Secondary: `o=popular` / `o=newest` **303** to unsorted `/search?q=…` — left alone this pass.

---

## Fix applied

✔️ 🔷 User approved HTML parser update (2026-07-19).

`libollamaweb/Search/Parser.vala`:

- `parse_search` also selects `#searchresults ul[role=list] li` that contain `a[href^="/library/"]` (keeps old `li[@x-test-model]`)
- `parse_row` pulls fallback: span before a `Pulls` sibling when `x-test-pull-count` missing
- `row_features` also takes `span.bg-indigo-50` when `x-test-capability` missing

✔️ Search fixtures + goldens refreshed under `tests/data/ollamaweb/search-*` (tags fixtures unchanged).

🚫 No change to double-search / `o=` sort behaviour in this pass.

---

## Evidence after fix

- ✔️ `--live llama` → **hits=20** (slugs, pulls, features)
- ✔️ `--session qwen` → **hits=18**
- ✔️ Offline suite PASS (parse + merge)

---

## Next

1. ⏳ 🔷 Verify **Add Model** UI on Desktop (rebuild app if needed)
2. ⏳ 🔷 Verify on Android
3. ⏳ When ✅: move this log to `docs/bugs/done/` with `FIXED` in the name
