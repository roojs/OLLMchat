# Android browser stays on Loading and times out

**Status:** ✅ FIXED — user closed 2026-09-27 (page loads)

## Problem

- **🔷** Tablet (SM-X406B), `org.roojs.ollmchat.androidpoc`, Just Ask chat.
- **🔷** Browser pane stays on the gray **Loading…** mask. No page appears.
- **🔷** Prompt: find the latest blog post on roojs.com. Tool call `browser` `fetch` `https://roojs.com`.
- **🔷** Expected: System WebView loads the page and the tool returns an a11y dump.
- **🔷** Actual: after 120s, `ERROR: Page load timed out`. The model retries the same fetch.

## Evidence

- **✔️** logcat (`--pid` of `org.roojs.ollmchat.androidpoc`, 2026-09-27 ~12:09–12:18):
  - `Executing tool 'browser'`
  - within a few milliseconds: `wka_widget_bounds_xywh: assertion 'GTK_IS_WIDGET (widget)' failed` twice
  - Soup `GSocketClient: TCP connection successful` to the target (HEAD probe)
  - 120s later: `Tool 'browser' threw error: Page load timed out`
- **✔️** Same pair of assertions on every fetch (`https://roojs.com` and a later Google search). No `WebViewHost` navigation lines.
- **✔️** `Browser.load` shows **Loading…** then calls `load_uri`. `WebView.load_uri` returns without `wka_host_create_with_xywh` / `wka_host_navigate` when `wka_widget_bounds_xywh` is false (`subprojects/webkitgtk-android` `WebView.vala` `load_uri`).
- **✔️** APK `lastUpdateTime=2026-09-27 12:04:42`. Device `libwebkitgtk-android-1.so` BuildID `09380433f4f460573b0f34a92913e95a226ece4b` matches the local unstripped library.
- **ℹ️** That library was built from `subprojects/webkitgtk-android` at `3ecd0d3` (`v0.1.3`). `android/pixiewood-wraps/webkitgtk-android/webkitgtk-android.wrap` says `revision = v0.1.5`.
- **🚫** Bumping that pin is not the fix. `v0.1.3..v0.1.5` does not change `wka_widget_bounds_xywh` or `load_uri`.
- **🚫** Not the 2026-07-22 Soup HEAD TLS failure (`Site did not respond`). The HEAD connection succeeds. The timeout is the WebView settle wait.
- **⏳** Debugger did not catch the pointer. `lldb-server` from `/data/local/tmp` exited 139. Attach via `run-as` stopped the process, then the breakpoint session was aborted before a hit. The app process exited and was relaunched.

## Root cause

- **✔️** The Android WebView host is never created. `load_uri` bails out because `wka_widget_bounds_xywh(host_area)` fails `GTK_IS_WIDGET`. `load_changed` never fires, so `Browser.load` waits out `timeout_seconds` (120) and throws `Page load timed out`. The freeze overlay stays on **Loading…** until that return.
- **✔️** `host_area` is null. In v0.1.3 it is assigned only inside `public WebView()`. `OLLMwebkit.WebViewAuto` chains with `Object(network_session: …)`, so that body never runs.
- **✔️** The two assertions are the two `load_uri` calls in `Browser.load`: `about:blank`, then the real URL. Both pass the null `host_area`.
- **✔️** v0.1.5 (`793f95e`) already builds the overlay in `construct`, which does run for `Object()`. The wrap pins that tag. The APK was compiled from the leftover v0.1.3 checkout. `wka_widget_bounds_xywh` and `load_uri` themselves did not change.

## Proposed fix

- **🔷** Build from the pinned checkout `subprojects/webkitgtk-android` at `v0.1.5`. Do not add a null guard that skips navigation.

## Attempts

- **✔️** Screenshot and logcat on the live tablet session.
- **✔️** Compared device `.so` to the local build (same BuildID).
- **💩** lldb breakpoint on `wka_widget_bounds_xywh` — no hit captured. Relaunch left the app on the Agent Pi chat, not the Just Ask thread.
- **✔️** `subprojects/webkitgtk-android` checked out at `v0.1.5` (`793f95e`). Chat POC APK rebuilt and installed on SM-S9380 and SM-X406B (`lastUpdateTime=2026-09-27 19:21`).
- **✅** User closed the bug after that install.
