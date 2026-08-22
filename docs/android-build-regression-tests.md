# Android build regression tests

Run **before every GitHub Android build push**:

```bash
# Fast checks (~30 seconds) — icons, GTK bootstrap, toolchain, wrap-redirects
scripts/android/run-android-regression-tests.sh

# Full CI simulation (~2–5 minutes) — above + setup + configure with broken caches
scripts/android/run-android-regression-tests.sh --full
```

GitHub Actions runs the same suite in `.github/workflows/x-android.yml`
(`run-android-regression-tests.sh --full`).

---

## Failure → test mapping

| ID | CI run(s) | Error / symptom | Regression test |
|----|-----------|-----------------|-----------------|
| **R01** | [27520220666](https://github.com/roojs/OLLMchat/actions/runs/27520220666) | Icon staging: `sidebar-hide-symbolic.svg` missing on build host | `regression/test-r01-bundled-android-icons.sh` |
| **R02** | [27585547860](https://github.com/roojs/OLLMchat/actions/runs/27585547860), [27585952776](https://github.com/roojs/OLLMchat/actions/runs/27585952776), [27586582052](https://github.com/roojs/OLLMchat/actions/runs/27586582052) | `wrap-redirect …/gtk/subprojects/graphene.wrap does not exist` | `regression/test-r02-gtk-bootstrap-restore.sh` |
| **R03** | (patch not in APK) | `android-bugs.patch` not applied to cached GTK | `regression/test-r03-gtk-patch-marker.sh` |
| **R04** | [27586907940](https://github.com/roojs/OLLMchat/actions/runs/27586907940) | `Undefined constant 'toolchain'` during configure | `regression/test-r04-stale-toolchain-discard.sh` |
| **R05** | (same family as R02) | Meson setup before GTK tree exists | `regression/test-r05-wrap-redirects-need-gtk.sh` |
| **R06** | (CI preflight) | Broken subprojects cache + stale toolchain + configure | `verify-android-ci-preflight.sh` (included in `--full`) |
| **R07** | [27588239244](https://github.com/roojs/OLLMchat/actions/runs/27588239244) (runtime) | TLS / paste / delete fixes missing from APK despite green build | `regression/test-r07-apk-runtime-patches.sh` (runs `verify-apk.sh` binary checks) |
| **R08** | (restore-keys partial hit) | Old subprojects cache restored after `PIXIEWOOD_DEPS_HASH` change | `regression/test-r08-stale-restored-cache-discard.sh` |
| **R09** | [27590212384](https://github.com/roojs/OLLMchat/actions/runs/27590212384) | `validate-restored-caches.sh: CACHE_MATCHED_PIXIEWOOD_BUILD_KEY: unbound variable` | `regression/test-r09-validate-caches-partial-env.sh` |
| **R10** | [27613430785](https://github.com/roojs/OLLMchat/actions/runs/27613430785), [27613805784](https://github.com/roojs/OLLMchat/actions/runs/27613805784) | `gdkandroidollmchatpatch.c` truncated or `g_debug` undeclared | covered by extended `test-r03-gtk-patch-marker.sh` |
| **R11** | [27614072148](https://github.com/roojs/OLLMchat/actions/runs/27614072148) (runtime) | TLS still broken: `libgioopenssl.so` cannot load `libssl` from `filesDir/share/gio/modules/` | `regression/test-r11-gio-openssl-deps.sh` + `verify-apk.sh` OpenSSL asset checks |
| **R12** | [27615842437](https://github.com/roojs/OLLMchat/actions/runs/27615842437) | `verify-apk.sh` grepped C comment `touch selection bubbles` (not in stripped `libgtk-4.so`) | `regression/test-r12-verify-apk-libgtk-strings.sh` |
| **R13** | [32201421756](https://github.com/roojs/OLLMchat/actions/runs/32201421756) | GLib TLS scan patch was gitignored under `subprojects/`; 9.2 dropped that approach | `regression/test-r13-glib-tls-ensure-before-scan.sh` (patch must **not** ship) |
| **R14** | [32241554256](https://github.com/roojs/OLLMchat/actions/runs/32241554256) | `pango` 1.58.2 from GTK `revision = main` needs glib `>= 2.88`; wrap is pinned at 2.84.0 | `regression/test-r14-pango-wrap-not-main.sh` |
| **R15** | [32241554256](https://github.com/roojs/OLLMchat/actions/runs/32241554256), [32435474269](https://github.com/roojs/OLLMchat/actions/runs/32435474269) | Local `--full` reused frozen wrap-git; GitHub fetched `main` (pango, then libadwaita) vs glib 2.84.0 | `regression/test-r15-glib-stack-wrap-git-pinned.sh` |
| **R16** | [32441247618](https://github.com/roojs/OLLMchat/actions/runs/32441247618), [32441610454](https://github.com/roojs/OLLMchat/actions/runs/32441610454) | After discarding stale pango, Meson download: `wrap-redirect … pango/subprojects/freetype2.wrap does not exist` | `regression/test-r16-pango-pin-checkout-before-meson.sh` |
| **R17** | [32547800217](https://github.com/roojs/OLLMchat/actions/runs/32547800217) | `Package gtksourceview-5 not found` compiling `libocmarkdowngtk`; local valac has the vapi from desktop `-dev` | `regression/test-r17-android-host-vapi-packages.sh` |
| **R18** | [32552806663](https://github.com/roojs/OLLMchat/actions/runs/32552806663) | `network_session` does not exist on `WebKitGtkAndroid.WebView` until wrap pin `v0.1.3` | `regression/test-r18-webkit-get-network-session.sh` |
| **R19** | [32568270350](https://github.com/roojs/OLLMchat/actions/runs/32568270350) | `Package gee-0.8 not found` generating `ocmarkdowngtk.vapi`; laptop has host `libgee-0.8-dev` | `regression/test-r19-android-custom-vapi-gee-vapidir.sh` |

When a **new** CI failure appears:

1. Add a row to this table.
2. Add `scripts/android/regression/test-rNN-<slug>.sh`.
3. Register it in `run-android-regression-tests.sh`.
4. Run `--full` locally before pushing.

---

## What each test checks

### R01 — bundled Android icons
Every `bundled` row in `android/icons/manifest` has a file under `android/icons/Adwaita/`.

### R02 — GTK bootstrap restore
Broken `subprojects/gtk` (stub without nested wraps) is repaired by copying
`.pixiewood/gtk-subproject-bootstrap/`, not by failing meson wrap-redirects.

### R03 — GTK patch marker
After bootstrap, `subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c` exists with
the `ollmchat-android-bugs-v4` tag and a complete function body (truncated patch tree
fails compile), and `ImContext.java` contains the hold-delete / `syncEditableFromGtk` fix.

### R09 — validate caches partial env
`validate-restored-caches.sh` exits cleanly when only subprojects cache env vars are
set (no `CACHE_MATCHED_PIXIEWOOD_BUILD_KEY`).

### R04 — stale toolchain discard
Invalid `toolchain.cross` (NDK path missing) triggers discard of ini + bin-aarch64 +
toolchain together — no partial Pixiewood state left for configure.

### R05 — wrap-redirects need GTK
`subprojects/graphene.wrap` redirects into `gtk/subprojects/`; meson cannot download
wraps until GTK is bootstrapped.

### R06 — CI preflight (full only)
Simulates restored CI caches (broken GTK + bad toolchain), runs `PIXIEWOOD_PHASE=setup`
and `configure`, asserts `build.ninja` exists.

### R08 — stale restored cache discard
Simulates `actions/cache` restore-keys returning a subprojects entry for an old
`PIXIEWOOD_DEPS_HASH`; `validate-restored-caches.sh` must remove `subprojects/gtk`.

### R07 — APK runtime patches (when APK exists)
After a local or CI build, `verify-apk.sh` checks:

- `assets/share/gio/modules/libgioopenssl.so` is packaged with `libssl.so*` and `libcrypto.so*` beside it
- `assets/share/ollmchat-android-runtime.tag` contains `ollmchat-android-bugs-v2`
- `libgtk-4.so` contains `ollmchat-android-bugs-v11` (patch marker string literals; no GDK TLS markers)
- `classes.dex` uses `deleteSurroundingText` lambda, not `sendKeyEvent` IME deletes
- `classes.dex` contains `syncEditableFromGtk` (IME `Editable` kept in sync for hold-backspace)

Stale compile caches that skip GTK rebuild fail R07 even when setup/configure pass.

### R12 — verify-apk libgtk string literals
Every `strings … libgtk-4.so | grep` pattern in `verify-apk.sh` must appear as a C
string literal in `gdkandroidollmchatpatch.c`. C source comments are not present in
stripped release libraries (CI run 27615842437).

### R13 — GLib TLS scan patch must not ship
TLS is static `g_io_openssl_load` in the app (plan 9.2). `glib.wrap` must not list
`tls-ensure-before-scan.patch`, and that file must not exist under
`android/pixiewood-wraps/glib/packagefiles/`. `hack.patch` (`g_set_user_dirs`
visibility) stays. CI run 32201421756 originally failed because the patch lived
only under gitignored `subprojects/`; we do not put that patch back.

### R14 — pango wrap must not track `main`
`android/pixiewood-wraps/gtk/pango.wrap.pin` pins pango 1.57.2
(`fa2ba89e7ed0907c8852add50cb13edefe93e66e`), compatible with glib 2.84.0.
After GTK bootstrap / restore, `subprojects/gtk/subprojects/pango.wrap` matches
that pin (upstream GTK wrap uses `revision = main`, which fetched pango 1.58.2
on CI and required glib `>= 2.88`). A restored `subprojects/nested-pango.wrap`
from an older cache is deleted so Meson does not see two pango providers. A
restored `subprojects/pango` tree that is not the pinned commit is discarded so
Meson re-clones 1.57.2 instead of keeping pango 1.58.2.

### R15 — GLib-stack wrap-git must be pinned (not `main`)
A local `meson` / `--full` preflight with `PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1`
reuses `subprojects/` trees. That hid pango 1.58.2 and libadwaita 1.10.rc on
GitHub: both wraps tracked `main` while the laptop still had June/July
checkouts that configured against glib 2.84.0.

Fast R15 fails unless `glib`, `gtk`, nested `pango`, and `libadwaita` wrap-git
files exist in git (not ignored) with a non-floating `revision`. After GTK
bootstrap, those wraps must not still say `main`/`master`. Skip-download is
refused while any of those wraps float, so `--full` actually re-clones them.

Do **not** pin fontconfig/fribidi here: they are not GLib consumers and did not
fail configure. Pin the next GLib-stack wrap when Meson reports a glib floor
above 2.84.0, and add it to this list.

### R16 — clone pinned pango before Meson wrap download
Discarding a stale `subprojects/pango` (R14) left no tree. `--full` then ran
`meson subprojects` and died on GTK wrap-redirects into
`pango/subprojects/freetype2.wrap`. Ensure clones pango (and libadwaita) at
their wrap pins before Meson download or skip-download.

---

## Automatic cache invalidation (no manual clear)

CI never requires `refresh_cache` for normal dependency or patch updates. Stale trees are
discarded by configuration:

| Cache | Invalidates when |
|-------|------------------|
| **PIXIEWOOD_DEPS_HASH** | Any file under `android/pixiewood-wraps/**`, gtk-subproject scripts, `verify-apk.sh`, etc. changes (`hashFiles` in workflow) |
| **PIXIEWOOD_APP_HASH** | App `meson.build` / `ollmapp/android/**` changes |
| **Compile cache key** | `pixiewood-build-v3-stable-$DEPS-$APP` — no broad restore-key prefix; wrong hash = miss |
| **Post-restore validation** | `validate-restored-caches.sh` drops subprojects/gtk, GTK bootstrap, or compile tree when restored `cache-matched-key` lacks current hash, patch marker, or `gdkandroidollmchatpatch*.o` / `libgtk-4.so` tag |
| **Post-build gate** | `verify-apk.sh` fails the job if shipped `libgtk-4.so` / `classes.dex` lack patch markers |
| **Cache save** | Compile cache is not re-saved unless `gdkandroidollmchatpatch*.o` exists in the prefix |

The workflow `refresh_cache` input is an emergency override only (workflow_dispatch); pushes
use the rules above automatically.

---

### R17 — host vapi packages on the Android runner
`libocmarkdowngtk` / `libollmchatgtk` / the POC pass `--pkg=gtksourceview-5`.
`gtk4.vapi` ships with `valac`; `gtksourceview-5.vapi` comes from
`libgtksourceview-5-dev`. A laptop with that desktop package compiles; GitHub
did not install it. R17 greps `.github/workflows/x-android.yml` and
`docs/android-build.md` for that package (and the existing gtk4 / libadwaita
`-dev` lines). `--full` also runs `verify-cross-compile.sh`, which now builds
`ollmchat-android-poc` instead of a library subset.

### R18 — wrap pin must ship `WebView.network_session`
CI clones `webkitgtk-android` from
`android/pixiewood-wraps/webkitgtk-android/webkitgtk-android.wrap`.
`31fd762d` only had `get_network_session()`. Release **`v0.1.3`** adds the
WebKit-shaped property. `Browser.vala` uses `.network_session`. CI
restore-keys can leave a getter-only `subprojects/webkitgtk-android` and then
skip Meson download. R18 requires wrap `v0.1.3`, property syntax in
`Browser.vala`, and discards/clones a stale checkout (same as R16 pango).

### R19 — custom_target `--pkg gee-0.8` needs `gee_vapi_dir`
`library()` gets gee from the Android subproject via `dependency('gee-0.8')`.
A `custom_target` valac line does not. Laptops with `libgee-0.8-dev` still
compile; CI does not install that package. R19 greps Android meson files
that pass `--pkg gee-0.8` and requires `gee_vapi_dir` (same as
`libocmarkdown` / `libocrpc`). Do **not** add `libgee-0.8-dev` to the
runner — that would hide a missing vapidir again.

---

## Related scripts (not in the default suite)

| Script | Purpose |
|--------|---------|
| `verify-cross-configure.sh` | Host-side meson cross configure smoke test |
| `verify-cross-compile.sh` | Host-side compile of `ollmchat-android-poc` (included in `--full`) |
| `verify-apk.sh` | APK contents after a full build |
| `test-gtk-subproject-readiness.sh` | Legacy; superseded by R02 + R06 |
