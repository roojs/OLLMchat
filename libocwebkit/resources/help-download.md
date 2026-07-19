BROWSER TOOL — action download
---
Download a URL through this chat’s browser session (cookies / auth).

Arguments:
  url  {string}  Required. Absolute http(s) URL of the resource to save.

Distinct from fetch (fetch returns page content; download saves the file).

Example:
  {"action": "download", "url": "https://example.com/a.pdf"}

Prefer this over run_command / wget for the same URL when available.
