# Markdown test data

Used by `tests/test-markdown-doc.sh` for the **document round-trip test**: md → JSON → md, then compare.

## Comparison

The test compares (in `build/tests/markdown-doc-out/`):

- **`xxx-roundtrip-output.md`** — Raw pipeline output. If a `*-roundtrip-output.diff` exists, it is applied before the comparison. No other normalization.
- **against** **`xxx-original.md`** (when no patch) or **`xxx-original-with-patch.md`** (when a patch is applied). Exact copy of the input `*.md`. No fixture: we always compare to the real original; diffs handle accepted differences.

## Fixtures

- **`*.md`** — Input markdown. Each is run through md→JSON→md; the result is compared to a copy of that same file (original).

- **`*-roundtrip-output.diff`** — Optional. Patch applied to `xxx-roundtrip-output.md` before comparing. Use for any accepted round-trip difference (blank lines, table/list format, etc.). Generate with `diff -u` from `build/tests/markdown-doc-out`; see `docs/plans/1.8.3-round-robin-document-issues.md` (Roundtrip diffs).

## Other files in this folder

- **`*-expected.md`** — Not used by the round-trip test (we always compare to the input and use diffs for accepted differences). Left in repo for reference or other uses; the test skips them as inputs.

- **`*-expected.html`**, **`*-expected-trace.txt`** — Used by other tests (HTML output, parser trace), not by the document round-trip test.
