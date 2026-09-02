# WebKit automation leaks into client sites

**Status:** ⏳ OPEN — OLLMchat implementation ✔️; smoke pending; Linux hide blocked on GTK Settings API (webkitgtk-automation)

**Started:** 2026-09-02

**Package:** `libocwebkit` / `ollmchat` browser tool

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Plan: [`WEBKIT-5.0.10-webkit-automation.md`](../plans/WEBKIT-5.0.10-webkit-automation.md)
- ℹ️ `WebViewAuto`: `libocwebkit/linux/`, `windows/`, `android/`
- ℹ️ webview2-gtk ≥ **0.5.9**: `WebViewSettings.navigator_webdriver_active_policy`
- ℹ️ webkitgtk-android ≥ **0.1.5**: same Vala API (DISABLED no-op on System WebView)
- ℹ️ Linux: [webkitgtk-automation](https://github.com/roojs/webkitgtk-automation) — WebCore `#165269` in `libwebkitgtk-6.0-webdriver4`; **no** public GTK `WebKitSettings` property yet

---

## Problem

🔷 Controlled tool views expose W3C `navigator.webdriver === true`, which sites use as a bot signal. Blocks WEBKIT-5.0.10 smoke.

---

## Fix (app config; libraries do the rest)

🔷 Set on view settings where the Vala property exists:

```vala
this.get_settings().navigator_webdriver_active_policy =
	NavigatorWebDriverActivePolicy.DISABLED;
```

| Layer | Responsibility |
|-------|----------------|
| **OLLMchat** (`WebViewAuto`) | Set policy **Disabled** (Win/Android); link webdriver on Linux |
| **webview2-gtk** ≥ 0.5.9 | DISABLED → `--disable-blink-features=AutomationControlled` at env create |
| **webkitgtk-android** ≥ 0.1.5 | Same property; DISABLED no-op (System WebView already reports false) |
| **libwebkitgtk-6.0-webdriver** | Interactions + WebCore policy; GTK Settings setter still upstream |

🚫 Spoof from page JS.  
🚫 Dummy `webkitgtk-6.0-webdriver` vapis — link via `declare_dependency` + `--pkg=webkitgtk-6.0`.  
🚫 Edit webview2-gtk host C from this repo.

---

## Implementation (OLLMchat — ✔️ except Linux Settings line)

- ✔️ `windows/WebViewAuto.vala` + `android/WebViewAuto.vala`: `navigator_webdriver_active_policy = DISABLED`.
- ✔️ Linux: `webkit_webdriver_dep` in `config/meson.build`; meson targets use it.
- ✔️ Debian / `docs/BUILD.md`: `libwebkitgtk-6.0-webdriver-dev`; Android wrap **v0.1.5**; Windows CI **webview2-gtk 0.5.9**.
- 💤 `linux/WebViewAuto.vala`: policy line **commented** — stock Vala `WebKit.Settings` has no property yet (webkitgtk-automation GTK API pending).

---

## Root cause

✔️ Default **Auto** policy advertises automation on controlled views. Hiding is embedder opt-in (`NavigatorWebDriverActivePolicy.DISABLED`).

---

## Attempts / changelog

- ✔️ 2026-09-02 — Hold until leak addressed; blocks WEBKIT-5.0.10 smoke.
- ✔️ 2026-09-02 — Direction locked: app sets Disabled; libraries own platform mechanism.
- ✔️ 2026-09-02 — Full OLLMchat apply: Win/Android settings, Linux webdriver link, packaging, dependency pins; removed mistaken empty `vapi/webkitgtk-6.0-webdriver.*`.

## Next

⏳ 🔷 Smoke: Win/Android console `navigator.webdriver` → `false`; Linux fill/press smoke (hide still `true` until GTK Settings API).
⏳ 🔷 webkitgtk-automation: expose `navigator_webdriver_active_policy` on GTK `WebKitSettings` (then add same line to `linux/WebViewAuto.vala`).
