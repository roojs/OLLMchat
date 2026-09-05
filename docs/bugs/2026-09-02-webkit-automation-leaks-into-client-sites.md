# WebKit automation leaks into client sites

**Status:** ⏳ OPEN — Linux build ✔️ (`webdriver6`); smoke still pending

**Started:** 2026-09-02

**Package:** `libocwebkit` / `ollmchat` browser tool

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Plan: [`WEBKIT-5.0.10-webkit-automation.md`](../plans/WEBKIT-5.0.10-webkit-automation.md)
- ℹ️ [webkitgtk-automation](https://github.com/roojs/webkitgtk-automation) — `docs/consuming.md` + installed `+webdriver6` `-dev`

---

## Problem

🔷 Controlled tool views expose W3C `navigator.webdriver === true`, which sites use as a bot signal. Blocks WEBKIT-5.0.10 smoke on Linux.

---

## Root cause

✔️ Default **Auto** policy advertises automation on controlled views. Hiding is embedder opt-in (`NavigatorWebDriverActivePolicy.DISABLED`).

---

## Fix direction

🔷 Set **Disabled** on automation WebView settings:

| Platform | Status |
| --- | --- |
| Windows / Android | ✔️ `navigator_webdriver_active_policy = DISABLED` |
| Linux | ✔️ `set_navigator_webdriver_active_policy(..., DISABLED)` in `linux/WebViewAuto.vala` + `--pkg=webkitgtk-webdriver` |

**Linux `-dev`:** `+webdriver6` ships fixed vapi (no `partial class Settings`) and header (`#include <webkit/WebKitSettings.h>`). Meson follows [`consuming.md`](file:///home/alan/git/webkitgtk-automation/docs/consuming.md) via vendored `scripts/meson/check-webkit-interactions.sh`.

🚫 Page-JS spoof. 🚫 In-tree vapi forks or C shims in OLLMchat.

---

## Verification

| Check | Status |
| --- | --- |
| Win/Android `navigator.webdriver` hidden | ✔️ |
| `libocwebkit.so` build (Linux) | ✔️ after `+webdriver6` |
| Linux console `navigator.webdriver` | ⏳ smoke |
| WEBKIT-5.0.10 fill/press smoke | ⏳ |

---

## Attempts / changelog

- ✔️ 2026-09-02 — Filed; Win/Android wired; Linux line commented pending `-dev` API.
- ✔️ 2026-09-05 — OLLMchat: `--pkg=webkitgtk-webdriver`, `set_navigator_webdriver_active_policy` in `linux/WebViewAuto.vala`.
- ✔️ 2026-09-05 — Confirmed git `webkitgtk-automation` has fixed vapi/header; installed `webdriver5` `-dev` did not.
- ✔️ 2026-09-05 — Wired Meson to `consuming.md`: vendored `scripts/meson/check-webkit-interactions.sh`, prefer `webkitgtk-6.0-webdriver` then stock.
- ✔️ 2026-09-05 — Installed `+webdriver6`; `libocwebkit.so` builds with navigator-policy call.
- ✔️ 2026-09-05 — Gate hide API on `.so` probe (`navigator-policy`), not distro; `#if HAVE_WEBKIT_NAVIGATOR_WEBDRIVER_POLICY`.
