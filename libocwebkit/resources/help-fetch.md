BROWSER TOOL — action fetch
---
Open a URL in this chat’s browser and return the page dump.

Arguments:
  url     {string}   Required. Absolute http(s) URL.
  format  {string}   Optional. "a11y" (default), "html", or "markdown".

When to use:
  You have a concrete URL that is not already a press-ref on the current page.

Example:
  {"action": "fetch", "url": "https://example.com/docs", "format": "a11y"}

After the dump, use press / fill from References for further navigation.
