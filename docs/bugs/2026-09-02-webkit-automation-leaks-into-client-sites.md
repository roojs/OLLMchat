# WebKit automation leaks into client sites

**Status:** ⏳ ON HOLD — blocks WEBKIT-5.0.10 smoke / sign-off until fixed

**Started:** 2026-09-02

**Package:** `libocwebkit` / `ollmchat` browser tool

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Plan (code landed, smoke blocked): [`WEBKIT-5.0.10-webkit-automation.md`](../plans/WEBKIT-5.0.10-webkit-automation.md)
- ℹ️ `WebViewAuto` (all platforms): `libocwebkit/linux/WebViewAuto.vala`, `windows/`, `android/`
- ℹ️ Plan intent: only primary `WebView` is `is_controlled_by_automation = true`; do **not** spoof `navigator.webdriver`

---

## Problem

🔷 After WEBKIT-5.0.10 wire-up, **automation state leaks into sites the user browses** (“client sites”) — not confined to the tool-controlled primary browser session.

🔷 User report 2026-09-02: treat this as **on hold** until automation is scoped so normal browsing / visited pages are not affected.

⏳ Exact observable on sites (e.g. `navigator.webdriver`, bot challenges, inspector/CDP exposure) — **needs capture** before proposing fences.

---

## Evidence

- ✔️ `WebViewAuto` ctor calls `WebContext.get_default()` then `context.set_automation_allowed(true)` — process-wide default context, not a dedicated automation-only context.
- ✔️ Same ctor sets `is_controlled_by_automation: true`, `network_session: context.get_network_session_for_automation()`, `enable_developer_extras = true`.
- ✔️ `WebDriver.prepare()` sets `WEBKIT_INSPECTOR_SERVER` on loopback before any WebView — env is process-wide.
- ✔️ `BrowserStack` attaches `WebDriver` when constructed; `Tool` lazily creates stack on first use — automation may be live even when user is not actively using the browser tool.

---

## Expected vs actual

| | Expected | Actual |
|---|----------|--------|
| Automation scope | Only the primary tool `WebView` / automation session | ⏳ Leaks into client sites (user report) |
| Site fingerprint | No automation signals on normal user browsing | ⏳ TBD — measure on target sites |
| Inspector | Loopback-only, not visible to remote origins | ⏳ TBD — confirm no remote exposure |

---

## Root cause

⏳ **Hypothesis:** `set_automation_allowed(true)` on **`WebContext.get_default()`** plus process-wide `WEBKIT_INSPECTOR_SERVER` applies automation plumbing beyond the single `is_controlled_by_automation` view. May also affect any other WebKit view sharing that context.

🚫 Not proposing code fences until device/browser repro confirms what sites see.

---

## Proposed fix direction

⏳ Deferred — likely needs **isolated `WebContext`** (not `get_default()`), and/or **lazy** `prepare()` + `set_automation_allowed` only while the browser tool session is active. Confirm with user before fences.

---

## Attempts / changelog

- ✔️ 2026-09-02 — User: on hold until automation leak into client sites is solved; blocks WEBKIT-5.0.10 smoke.

## Next

⏳ 🔷 Repro on a real site (note what the page sees), then propose verbatim fences in this file.
