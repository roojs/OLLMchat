# Ollama.com HTML fixtures (`libollamaweb`)

Offline HTML snapshots for parser tests. **No network** in CI.

## Files

| HTML | Source URL |
|------|------------|
| `search-popular.html` | `https://ollama.com/search` (fixture only; app does not search with empty `q`) |
| `search-newest.html` | `https://ollama.com/search?o=newest` (fixture only) |
| `search-double-merge.expected.json` | Merged output of popular + newest (`oc-test-ollamaweb --merge`) |
| `search-q-gemini.html` | `https://ollama.com/search?q=gemini` |
| `search-c-embedding.html` | `https://ollama.com/search?c=embedding` |
| `tags-library-gemma3.html` | Library tags page |
| `tags-derivative-sample.html` | Namespaced derivative tags page |

Golden JSON: `*.expected.json` next to each HTML file (compact JSON, no pretty-print).

## Regenerate goldens

From build dir after `meson compile -C build oc-test-ollamaweb`:

```bash
./examples/oc-test-ollamaweb --write-golden tests/data/ollamaweb/*.html
./examples/oc-test-ollamaweb --tags --write-golden tests/data/ollamaweb/tags-*.html
./examples/oc-test-ollamaweb --merge --write-golden \
  tests/data/ollamaweb/search-popular.html \
  tests/data/ollamaweb/search-newest.html
```

## Tests

```bash
meson test -C build --suite ollamaweb
```

Runs `test-ollamaweb-parse.sh` (per-fixture parse) and `test-ollamaweb-merge.sh` (double-search merge).
