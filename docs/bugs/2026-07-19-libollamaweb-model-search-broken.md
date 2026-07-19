# libollamaweb Add Model search broken (Desktop + Android)

**Status:** ⏳ OPEN

**Started:** 2026-07-19

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval.

**Related:**

- ℹ️ Prior FIXED case (same surface): [`docs/bugs/done/2026-06-02-FIXED-libollamaweb-add-model-search-spin-no-results.md`](done/2026-06-02-FIXED-libollamaweb-add-model-search-spin-no-results.md)
- ℹ️ Plans: `docs/plans/4.8-ollama-web-live-search.md`, `docs/plans/4.8.1-ollama-web-phase-2-1-add-model.md`

---

## Problem

🔷 **Add Model** live search via **`libollamaweb`** (ollama.com model catalog) is **completely broken** on **Desktop and Android**.

**Expected:** Typing a query (e.g. `llama`, `qwen`) returns shallow search hits in the pulldown after debounce + network.

**Actual:** Search does not return usable results (Desktop and Android). Exact UI symptom (spinner forever vs empty list vs error) TBD from repro evidence below.

---

## Reproduction

### UI

1. Open **Settings → Add Model**.
2. Type a non-empty query (e.g. `llama`).
3. Wait for debounce (~2 s) and network.
4. Observe: no usable model rows (Desktop and Android).

### CLI first (existing test tooling — do this before UI)

Offline parser / merge suite + live HTTP path already exist — **no new test binary required**.

```bash
# Offline fixtures (no network)
meson test -C build --suite ollamaweb
# or:
./tests/test-ollamaweb-parse.sh build
./tests/test-ollamaweb-merge.sh build

# Live HTTP + parse (Service.search — double-fetch popular+newest)
./build/examples/oc-test-ollamaweb --live llama
./build/examples/oc-test-ollamaweb --live qwen

# Session layer (cache + model_dir — closer to Add Model)
./build/examples/oc-test-ollamaweb --session llama
./build/examples/oc-test-ollamaweb --session --data-dir /tmp/ollm-test-models llama

# Optional: save live HTML and parse offline
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
TMP=$(mktemp -d)
curl -sS -A "$UA" -o "$TMP/popular.html" 'https://ollama.com/search?q=llama&o=popular'
./build/examples/oc-test-ollamaweb "$TMP/popular.html"
```

**Binary:** `build/examples/oc-test-ollamaweb` (also accepts `build/oc-test-ollamaweb`).  
**Source:** `examples/oc-test-ollamaweb.vala`  
**Fixtures:** `tests/data/ollamaweb/`

---

## Data flow

```
AddModelDialog.model_pulldown.search_changed
  → SearchResults.queue_search
  → OllamaWeb.Search.Session.search
  → OllamaWeb.Search.Service.search (HTTP popular + newest, merge)
  → Parser.parse_search (x-test-model / #searchresults)
  → SearchResults.replace_hits → pulldown list
```

**Key files:**

- `libollamaweb/Search/Service.vala` — HTTP + merge
- `libollamaweb/Search/Parser.vala` — HTML → `Model` rows
- `libollamaweb/Search/Client.vala` — Soup fetch
- `libollamaweb/Search/Session.vala` — cache / refine
- `libollmchat/Settings/SearchResults.vala` — UI debounce / loading
- `ollmapp/SettingsDialog/AddModelDialog.vala`

---

## Hypotheses (unverified)

| Area | Why | How to check |
| ---- | --- | ------------ |
| 💩 **ollama.com HTML shape change** | Parser XPath still looks for `x-test-model` / `#searchresults`; site markup may have changed since 2026-06 fix. | `--live` → 0 hits; curl HTML; compare to fixtures |
| 💩 **HTTP / TLS / DNS** | Network fails on device or desktop (Android TLS certs historically flaky). | `--live` error message; curl status |
| 💩 **UI integration only** | CLI returns hits but Add Model list empty (cancel race / loading / store). | CLI OK + UI empty |
| 💩 **Android-specific network** | Desktop CLI OK, Android UI broken. | Same `--live` on desktop vs device logs |

---

## Evidence

### 2026-07-19 — tooling inventory

- ✔️ Existing live/offline CLI: `oc-test-ollamaweb` (`--live`, `--session`, fixture parse, `--merge`)
- ✔️ Offline suite: `tests/test-ollamaweb-parse.sh`, `tests/test-ollamaweb-merge.sh` / meson `--suite ollamaweb`
- ✔️ Offline fixtures still parse (old markup with `x-test-model`)

### 2026-07-19 — live CLI (Desktop)

- ✔️ `./build/examples/oc-test-ollamaweb --live llama` → **`hits=0`**, stdout `[]` (exit 0 — no network throw)
- ✔️ curl without `-L`: `GET /search?q=llama&o=popular` → **HTTP 303** `Location: /search?q=llama` (empty body)
- ✔️ curl with `-L`: final **HTTP 200**, ~79 KB HTML, `url_effective=https://ollama.com/search?q=llama`
- ✔️ Live HTML: `#searchresults` present, `ul[role=list]` present, **20** `/library/…` links
- ✔️ Live HTML: **`x-test-model` count = 0** (attribute removed site-wide on search rows)
- ✔️ Offline parse of saved live HTML → `[]` (same as `--live`)
- ℹ️ Site build header: `x-build-time: 2026-07-17T21:35:46-07:00` (markup change ~2 days before this log)

### New search row shape (live 2026-07-19)

```html
<ul role="list" class="grid grid-cols-1">
  <li class="flex items-baseline border-b border-neutral-200 py-6">
    <a href="/library/llama3.1" class="group w-full">
      <div class="flex flex-col mb-1" title="llama3.1">
        <h2 …><span>llama3.1</span></h2>
        <p class="max-w-lg …">Llama 3.1 is …</p>
      </div>
      … feature / size spans …
    </a>
  </li>
  …
</ul>
```

Parser still selects: `//*[@id='searchresults']//li[@x-test-model] | //ul[@role='list']/li[@x-test-model]` → **zero nodes**.

### Secondary: sort query param

- ℹ️ `o=popular` / `o=newest` now **303** to the unsorted `/search?q=…` URL (sort UI still exists as form `name="o"`). Double-search popular+newest may both land on the **same** HTML until path/query is updated — merge still OK once parse works, but popular/newest ordering may be lost.

---

## Root cause

✔️ **ollama.com search HTML dropped `x-test-model` on result `<li>`s** (and related test attrs). `Parser.parse_search` matches nothing → empty hit lists on Desktop and Android (same library). Not an Android-only or UI-only bug.

---

## Proposed fix

💩 Update `libollamaweb/Search/Parser.vala` `parse_search` / `parse_row` to the new markup (e.g. `#searchresults ul[role=list] > li` + `a[href^="/library/"]` / title / description), refresh `tests/data/ollamaweb/` fixtures from live HTML, re-run offline suite + `--live`.

💩 Separately: decide whether to keep double-search if `o=` no longer changes the page (or adapt to whatever sort query the site accepts now).

**No code changes until fix direction is approved.**

---

## Next

1. ⏳ 🔷 Approve parser update approach (selectors above) vs alternatives
2. ⏳ 💩 Draft Remove/Replace/Add for `Parser.vala` + fixture refresh
3. ⏳ 🔷 Verify `--live llama` returns hits; then Add Model UI on Desktop + Android
