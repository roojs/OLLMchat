# Add Model live search (`libollamaweb`): spinner, no results returned

**Status:** OPEN

**Started:** 2026-06-02

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval.

**Related plans (context only — not a diagnosis):**

- **`docs/plans/4.8-ollama-web-live-search.md`** — replace bundled `ollama-models.json` filter with live ollama.com search via **`libollamaweb`**.
- **`docs/plans/4.8.1-ollama-web-phase-2-1-add-model.md`** — Add Model integration (`SearchResults`, `AddModelDialog`).

---

## Problem

The **Add Model** dialog now uses **`libollamaweb`** live search instead of filtering the bundled model catalog. When the user types a model name, the UI shows a **spinner** (“Searching ollama.com…”) but **no model rows are returned**.

**Expected:** After ~2 s debounce, shallow search hits appear in the pulldown; refine may enrich rows in the background.

**Actual:** Spinner runs; list stays empty — nothing returned to the user.

---

## Reproduction

**CLI first** (see [Debug strategy → Step 0](#step-0--cli-verification-do-this-first)): curl live HTML + `oc-test-ollamaweb` to confirm HTTP and parse before opening the app.

**UI repro:**

1. Open **Settings → Add Model** (or equivalent entry point for `AddModelDialog`).
2. Focus the model search field and type a non-empty query (e.g. `llama`, `qwen`).
3. Wait for debounce (~2 s) and network round-trip.
4. Observe: **“Searching ollama.com…”** spinner; popover/list remains empty.

**Environment notes:** Network access to ollama.com, proxy/firewall, `--debug` stderr, whether `data_dir/ollamaweb-models/` has cached slug JSON from prior runs.

---

## Data flow (for debugging)

```
AddModelDialog.model_pulldown.search_changed
  → SearchResults.queue_search (2 s debounce, loading=true)
  → SearchResults.run_search.begin()
  → OllamaWeb.Search.Session.search(query, Category.NONE)
  → OllamaWeb.Search.Service.search (HTTP: popular + newest, merge)
  → SearchResults.replace_hits → ListModel items_changed
  → SearchablePulldown popup_stack ("loading" vs "list")
```

**Key files:**

- `ollmapp/SettingsDialog/AddModelDialog.vala` — wires `SearchResults` to `SearchablePulldown`
- `libollmchat/Settings/SearchResults.vala` — debounce, `run_search`, `loading` flag
- `libollamaweb/Search/Session.vala` — cache, double search, refine queue
- `libollamaweb/Search/Service.vala` — HTTP fetch + HTML parse
- `ollmapp/SettingsDialog/SearchablePulldown.vala` — spinner vs list stack

---

## Suspected areas (hypotheses only — not verified)

| Area | Why it might matter | CLI 2026-06-02 |
| ---- | ------------------- | -------------- |
| **HTTP / parse failure** | `run_search` catches errors with `GLib.warning` only — user sees empty list, no error UI. | **Ruled out** on dev machine (curl 200, parse 20 hits). |
| **Empty parse result** | ollama.com HTML shape change → zero hits without throwing. | **Ruled out** for `llama`/`qwen` (20 `x-test-model` nodes). |
| **`loading` stuck true** | Spinner never stops if `run_search` never reaches `finally` (less likely with async). | Open — user report says spinner runs (may or may not stop). |
| **`loading` false but empty store** | Search completes with 0 hits or stale `pending_query` mismatch discards results. | Likely if CLI OK but UI empty — **prime suspect**. |
| **Cache / model_dir** | RAM cache hit with bad slug list, or `Model.load` fails silently for every slug. | Test with `oc-test-ollamaweb --session --data-dir …`. |
| **Cancel race** | Each keystroke calls `session.cancel()`; rapid typing could abort before results land (should still eventually succeed after pause). | Open — `queue_search` calls `session.cancel()` on every change. |
| **Popup stack UX** | `search_loading=false` switches to `"list"` child even when store is empty — looks like “nothing returned” after spinner stops. | Open — UX symptom, not root cause. |

---

## Debug strategy (evidence-first)

**Start on the command line** — isolate HTTP + parse from GTK/UI before running the app. Extend **`oc-test-ollamaweb`** (same binary as offline fixtures): **`--live`** runs `Service.search`; **`--session`** runs `Session.search` with `model_dir` (closer to Add Model).

### Step 0 — CLI verification (do this first)

From repo root after `meson compile -C build oc-test-ollamaweb`:

```bash
# 0a. Offline parser baseline (no network)
meson test -C build --suite ollamaweb

# 0b. Live HTTP + parse (Service.search — same double-fetch path as the app)
./build/oc-test-ollamaweb --live llama 2>&1 | head
./build/oc-test-ollamaweb --live qwen 2>&1 | head

# 0c. Session layer (cache, model_dir, refine queue — Add Model uses Session)
./build/oc-test-ollamaweb --session llama
./build/oc-test-ollamaweb --session --data-dir /tmp/ollm-test-models llama
./build/oc-test-ollamaweb --session --refine llama   # also drains refine_queue

# 0d. Optional: curl saved HTML + offline parse (when comparing HTML shape)
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
TMP=$(mktemp -d)
curl -sS -A "$UA" -o "$TMP/popular.html" 'https://ollama.com/search?q=llama'
./build/oc-test-ollamaweb "$TMP/popular.html" | python3 -c "import sys,json; print(len(json.load(sys.stdin)), 'parse-only')"
```

Use **`--debug`** with live/session modes for `GLib.debug()` from `libollamaweb` (query, hit count, `model_dir`).

**Interpretation:**

| CLI outcome | Likely layer |
| ----------- | ------------ |
| `--live` fails / 0 hits | Soup HTTP or `Service.search` — not GTK |
| `--live` OK, `--session` 0 hits | `Session` cache, `model_dir`, or `Model.load` |
| `--session` OK, UI empty | `SearchResults`, debounce/cancel, or GTK list binding |
| Offline parse 0, live HTML has `x-test-model` | Parser XPath regression |

### Step 1 — App / integration (after CLI passes)

1. **Reproduce** in **Settings → Add Model** with the same queries.
2. **Run app with `--debug`**; temporarily enable debug lines in:
   - `SearchResults.run_search` — query, hit count, errors.
   - `OllamaWeb.Search.Session.search` / `Service.search` — HTTP status, parsed slug count.
3. **Check stderr** for `ollama.com search failed:` warnings from `SearchResults`.
4. **Inspect disk cache:** `~/.local/share/ollmchat/ollamaweb-models/` (or app `data_dir`) for `{slug}.json` files after a search.
5. Record each experiment below before proposing a fix.

---

## Attempts / changelog

| Date | Change | Purpose | Result |
| ---- | ------ | ------- | ------ |
| 2026-06-02 | Bug report filed | Capture user report | — |
| 2026-06-02 | `meson test -C build --suite ollamaweb` | Offline parser baseline | **OK** — 2/2 (`test-ollamaweb-parse`, `test-ollamaweb-merge`) |
| 2026-06-02 | curl + offline parse on live HTML (`q=llama`, `q=qwen`) | Parser-only CLI verify | **OK** — see below |
| 2026-06-02 | `oc-test-ollamaweb --live` / `--session` | Same binary; HTTP via Soup + Session path | **OK** — `llama` → 40 hits |

### 2026-06-02 — CLI offline parse on live HTML (this machine)

```
HTTP popular/newest: 200 / 200
popular.html: 81574 bytes, 20 × x-test-model, 1 × id="searchresults"

oc-test-ollamaweb popular.html     → 20 slugs (parse-only on curl snapshot)
oc-test-ollamaweb --merge pop+new  → 40 slugs

Fixture sanity: search-q-gemini.html → 3 slugs (offline goldens still match)
```

**Conclusion from offline parse on live HTML:** Parser extracts models from current ollama.com HTML. **`--live`** / **`--session`** also OK on this machine (`llama` → 40 hits; session `refine_queue=40`). Bug not reproduced at libollamaweb layer — suspect `SearchResults` / GTK if UI still empty.

---

## Conclusions

- **Root cause:** Unknown — **not** at the curl+parser layer on the dev machine (2026-06-02). Suspect app integration: `SearchResults.run_search` / `Session.search` in GTK main loop, `session.cancel()` on each keystroke vs in-flight work, `data_dir` / disk cache, or UI list binding — still unverified.
- **Ruled out (this machine, 2026-06-02):**
  - Offline parser regression (`meson test --suite ollamaweb`).
  - Live ollama.com unreachable or returning non-200 for `/search?q=llama`.
  - Live HTML missing `x-test-model` / `#searchresults` (20 nodes present).
  - `Parser.parse_search` returning zero rows for current live HTML.

**Next step:** Run `oc-test-ollamaweb --live llama` and `--session llama`; if both OK, reproduce in the app with `--debug` on the same queries.
