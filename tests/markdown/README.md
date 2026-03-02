# Markdown test data

Used by `tests/test-markdown-doc.sh` for the **document round-trip test**: md → JSON → md, then compare.

## Comparison

The test compares (in `build/tests/markdown-doc-out/`):

- **`xxx-roundtrip-output.md`** — Raw pipeline output. If a `*-roundtrip-output.diff` exists, it is applied before the comparison. No other normalization.
- **against** **`xxx-original.md`** (when no patch) or **`xxx-original-with-patch.md`** (when a patch is applied). Exact copy of the input `*.md`. No fixture: we always compare to the real original; diffs handle accepted differences.

## Fixtures

- **`*.md`** — Input markdown. Each is run through md→JSON→md; the result is compared to a copy of that same file (original).

- **`*-roundtrip-output.diff`** — Optional. Patch applied to `xxx-roundtrip-output.md` before comparing. The diff is the source of truth for accepted round-trip differences (e.g. formatting, blank lines).

### How to create a `*-roundtrip-output.diff`

When round-trip output differs from the original in acceptable ways, add a diff so the test can apply it and compare. From the project root, with `build` as your build dir:

1. **Generate round-trip output** (run the test once, or manually):
   ```bash
   ./build/oc-markdown-doc-test tests/markdown/BASE.md markdown > build/tests/markdown-doc-out/BASE-roundtrip.md
   ```
   Replace `BASE` with the basename of the `.md` file (e.g. `render-test2`).

2. **Copy to the filename the test patches**:
   ```bash
   cp build/tests/markdown-doc-out/BASE-roundtrip.md build/tests/markdown-doc-out/BASE-roundtrip-output.md
   ```

3. **Create the diff** (roundtrip-output → original). The diff must be from the *roundtrip* content to the *original* so that when `patch` is applied to roundtrip-output, the result matches the original:
   ```bash
   cd build/tests/markdown-doc-out
   diff -u BASE-roundtrip-output.md ../../../tests/markdown/BASE.md > ../../../tests/markdown/BASE-roundtrip-output.diff
   ```

4. **Optional:** Normalize the `+++` path in the diff to the same filename as `---` (so the diff is self-contained):
   ```bash
   sed -i 's|^+++ .*|+++ BASE-roundtrip-output.md|' tests/markdown/BASE-roundtrip-output.diff
   ```

5. Re-run the test: it will apply the diff to `BASE-roundtrip-output.md` and compare against the original.

## Other files in this folder

- **`*-expected.md`** — Not used by the round-trip test (we always compare to the input and use diffs for accepted differences). Left in repo for reference or other uses; the test skips them as inputs.

- **`known-fail-*.md`** — Document known parser limitations (e.g. bold spanning a newline). The round-trip test skips these; they are used for manual verification or when the limitation is fixed. See plan 1.8 (low-priority issues).

- **`*-expected.html`**, **`*-expected-trace.txt`** — Used by other tests (HTML output, parser trace), not by the document round-trip test.
