BROWSER TOOL — action download
---
Download a URL through this chat’s browser session (cookies / auth).
Saves under the platform Downloads folder. User must Allow via the
permission bar (session remembers Allow for that URL).

Arguments:
  url  {string}  Required. Absolute http(s) URL of the resource to save.

Distinct from fetch (fetch returns page content; download saves the file).

Example:
  {"action": "download", "url": "https://example.com/a.pdf"}

Prefer this over run_command / wget for the same URL when available.
If the same URL is already downloading, a second call does not start again.
