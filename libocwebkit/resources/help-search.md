BROWSER TOOL — action search
---
Open Google with the given search terms and return the results dump.
Under the hood this uses accessibility fill + submit on the search UI when
needed — not a SERP scrape.

Arguments:
  query   {string}   Required. Search terms (not a URL).
  format  {string}   Optional. "a11y" (default), "html", or "markdown".

Example:
  {"action": "search", "query": "Vala WebKitGTK accessibility"}

Then press a result ref from References. Do not invent SERP scraping.
