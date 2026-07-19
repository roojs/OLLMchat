BROWSER TOOL — action search
---
Open Google (v1 only) with the given search URL and return the results dump.
Under the hood this uses accessibility fill + submit on the search UI when
needed — not a SERP scrape.

Arguments:
  url     {string}   Required. Google search URL including the query
                     (e.g. https://www.google.com/search?q=Vala+WebKitGTK).
  format  {string}   Optional. "a11y" (default), "html", or "markdown".

Example:
  {"action": "search",
   "url": "https://www.google.com/search?q=Vala+WebKitGTK+accessibility"}

Then press a result ref from References. Do not invent SERP scraping.
