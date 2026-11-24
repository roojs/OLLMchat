# Trixie packages fail to link because the WebDriver library calls removed WebKit symbols

**Status:** ⏳

## User decisions required

- 💩 Rebuild and publish `libwebkitgtk-6.0-webdriver` from [webkitgtk-automation](https://github.com/roojs/webkitgtk-automation) against Debian WebKit `2.54.3-1~deb13u1`, then put that package in the roojs trixie suite. Nothing in this tree can make the current `.so` link.

## User reported

- 🔷 The Pixie build is still failing and needs a fix.
- 🔷 A previous explanation about something wrong with the Web view was not clear.

## Success scenario

- The Debian 13 package job links `ollmchat` and uploads the Trixie `.deb` files.
- That job still installs `libwebkitgtk-6.0-webdriver-dev` from the roojs trixie suite.
- The installed WebDriver library is built against the same WebKit as Debian's `libjavascriptcoregtk-6.0-1`.

## Current behavior

- Release `v1.4.17` job **Debian / Trixie packages** stops at the `ollmchat` link.
- The link line includes `/usr/lib/x86_64-linux-gnu/libwebkitgtk-6.0-webdriver.so.4` and `/usr/lib/x86_64-linux-gnu/libjavascriptcoregtk-6.0.so`.
- The linker reports two missing symbols from the WebDriver library.

## Codebase observed behavior

- [`config/meson.build`](../../config/meson.build) prefers pkg-config module `webkitgtk-6.0-webdriver` and links the versioned library directly:

```meson
webkit_webdriver_dep = declare_dependency(
  dependencies: [dependency('javascriptcoregtk-6.0')],
  compile_args: webkit_webdriver_cflags,
  link_args: [
    join_paths(webkit_webdriver_libdir, 'libwebkitgtk-6.0-webdriver.so.4'),
  ],
)
```

- [`ollmapp/meson.build`](../../ollmapp/meson.build) passes that dependency into the `ollmchat` executable.
- The Trixie job apt-installs `libwebkitgtk-6.0-webdriver-dev` after the roojs suite is enabled. That is the same install as the Ubuntu jobs.

## Debugging

#### Current debug output

- GitHub Actions run `45348982046`, job **Debian / Trixie packages**, 2026-11-24. Apt lines and the link error.

```text
Get: libwebkitgtk-6.0-webdriver4 2.54.0-1~deb13u3+webdriver1
Get: libjavascriptcoregtk-6.0-1 2.54.3-1~deb13u1
Get: libwebkitgtk-6.0-4 2.54.3-1~deb13u1
/usr/bin/ld: .../libwebkitgtk-6.0-webdriver.so.4: undefined reference to `WTF::RealTimeThreads::setEnabled(bool)'
/usr/bin/ld: .../libwebkitgtk-6.0-webdriver.so.4: undefined reference to `WTF::RealTimeThreads::singleton()'
collect2: error: ld returned 1 exit status
```

- Same two symbols on the previous Trixie job, run `45128432365`, 2026-11-23.

#### Debug code added (remove when complete)

None.

## Proposed fix

### Phase 1 — Rebuild the Trixie WebDriver library

Why: `libwebkitgtk-6.0-webdriver.so.4` at `2.54.0-1~deb13u3+webdriver1` was compiled against WebKit 2.54.0. That build still calls `WTF::RealTimeThreads`. Debian security replaced JavaScriptCore and WebKit with `2.54.3-1~deb13u1`, which removed those symbols (upstream replaced `RealTimeThreads` with `HighPriorityThreads`). The chat binary links the old WebDriver `.so` to the new JavaScriptCore, so the link fails. Rebuilding the WebDriver package on current Debian 13 compiles it against the JavaScriptCore that the job installs.

No edit in this repository. [`docs/bugs/done/2026-11-06-CLOSED-trixie-webkit-webdriver.md`](done/2026-11-06-CLOSED-trixie-webkit-webdriver.md) already rules out shipping Trixie without WebDriver, and rules out linking an Ubuntu WebDriver `.so`.

Steps:

- In `webkitgtk-automation`, build `libwebkitgtk-6.0-webdriver4` and `libwebkitgtk-6.0-webdriver-dev` on Debian 13 with WebKit `2.54.3-1~deb13u1` installed.
- Publish those packages into the roojs trixie suite, replacing `2.54.0-1~deb13u3+webdriver1`.
- Re-run the Trixie package job. It should pick up the new package with no workflow change.

## LLM

- ℹ️ User said "Pixie". The Android pixie APK job on run `45348982046` was still compiling when this was written. The finished failure is **Debian / Trixie packages**. "Web view" is this WebDriver build of WebKitGTK, which is the library behind the in-app browser.
- ℹ️ Prior close: [`docs/bugs/done/2026-11-06-CLOSED-trixie-webkit-webdriver.md`](done/2026-11-06-CLOSED-trixie-webkit-webdriver.md). That package was published 2026-11-07 as GitHub release `webkit2gtk-2.54.0-1-deb13u3-webdriver1`. It matched Debian at the time. Debian security has since moved WebKit to 2.54.3.
- ℹ️ Debian main trixie still lists `libwebkitgtk-6.0-4` `2.52.6-1~deb13u1`. The CI container installs `2.54.3-1~deb13u1` from `trixie-security`. Pinning the job to 2.52.6 would miss the WebDriver build by a larger gap.
- 🚫 Do not set `-Dwebkit_webdriver=disabled` on Trixie. The closed report says that hold is not the package we ship.
- 🚫 Do not install the Ubuntu plucky, questing, or resolute WebDriver `.so` into the Trixie root. Those builds do not match Trixie JavaScriptCore.
- ℹ️ Upstream: WebKit PR 71157, "[Linux] Remove RT threads", labeled for a 2.54 backport. It deletes `WTF::RealTimeThreads` and adds `WTF::HighPriorityThreads`. The two missing symbols are `setEnabled(bool)` and `singleton()`.
- ⏳ Stop **E**. The rebuild is in `webkitgtk-automation`, not this workspace.
