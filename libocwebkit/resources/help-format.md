BROWSER TOOL — argument format
---
Output format for page-bearing actions (fetch, search, press, whereami).

Values:
  a11y      (default) — accessibility markdown: Content + References.
                        Required for press/fill navigation.
  html      — page HTML after load (no press-refs).
  markdown  — HTML converted to Markdown (may be large/noisy).

Press and fill need an a11y dump with References from a prior a11y reply
(or call whereami/fetch/search/press with format "a11y" first).
