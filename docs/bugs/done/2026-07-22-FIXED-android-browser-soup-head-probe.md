# 2026-07-22 — Android browser tool fails before WebView load

**Status:** ✅ FIXED — user verified 2026-07-24

## Problem

- 🔷 On device APK, `browser` tool returns `ERROR: Site did not respond`; page never loads.
- 🔷 webkitgtk-android POC on the same phone loads pages fine (System WebView OK).
- Expected: `Browser.load()` reaches `begin_load` / `WebView.load_uri(real_url)`.
- Actual: load stops at Soup HEAD probe; WebView only ever hits `about:blank`.

## Evidence

- ✔️ logcat (`org.roojs.ollmchat.androidpoc`):
  - `Executing tool 'browser'`
  - `lookup_by_name` for `www.google.com` / `www.ikea.com`
  - first address often `Network is unreachable` (likely IPv6), then `TCP connection successful`
  - ~30ms later: `Tool 'browser' threw error: Site did not respond`
  - `WebViewHost` / `WebViewPaint` only: `about:blank` (started/finished) — never the target URL
- ✔️ Chat / ollama HTTPS works; those `Soup.Session`s get  
  `OLLMchat TLS: Soup.Session tls_database=…/files/share/ssl/certs/ca-certificates.crt`
- ✔️ `AndroidToolsRegistration.fill_tools` applies `AndroidConnectionTls` to **web_fetch** and **google_search** only — **not** to anything on `OLLMwebkit.Tool`
- ✔️ `Browser.load()` creates a **local** `new Soup.Session()` for HEAD with **no** `tls_database`  
  (`libocwebkit/Browser.vala` ~289–298); catch maps any error to `"Site did not respond"`
- ℹ️ CA bundle is present on device (`files/share/ssl/certs/ca-certificates.crt`)

## Root cause

- ✔️ Missing piece vs working POC: OLLMchat adds a **libsoup HEAD reachability probe** before `WebView.load_uri`. On Android that probe uses an unconfigured OpenSSL Soup session (no bundled CA), so HTTPS HEAD fails TLS. The tool aborts **before** the System WebView (which uses the platform trust store, as in the POC) ever navigates.

## Proposed fix

- 🔷 **Approved:** same pattern as 2026-07-09 tools TLS — durable `Soup.Session` on `Browser`, apply `AndroidConnectionTls` in `fill_tools()`, use `this.soup` for HEAD probe.
- 🚫 Skip-probe-on-Android (earlier 💩) — not used.

### Edit (`libocwebkit/Browser.vala` + `AndroidToolsRegistration.vala`)

- ✔️ `Browser.soup` created in constructor (timeout + user-agent).
- ✔️ HEAD probe uses `this.soup`.
- ✔️ `fill_tools()`: `AndroidConnectionTls.apply_to_session(browser_tool.stack.primary.soup)`.

## Next

- ⏳ Rebuild APK, reinstall, re-run browser prompt; confirm logcat `tls_database=…` on probe and real URL in `WebViewHost`.
