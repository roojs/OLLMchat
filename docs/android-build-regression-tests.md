# Android build regression tests

Run **before every GitHub Android build push**:

```bash
# Fast checks (~30 seconds) — icons, GTK bootstrap, toolchain, wrap-redirects
scripts/android/run-android-regression-tests.sh

# Full CI simulation (~2–5 minutes) — above + setup + configure with broken caches
scripts/android/run-android-regression-tests.sh --full
```

GitHub Actions runs the same suite in `.github/workflows/android-build-reusable.yml`
(`run-android-regression-tests.sh --full`).

---

## Failure → test mapping

| ID | CI run(s) | Error / symptom | Regression test |
|----|-----------|-----------------|-----------------|
| **R01** | [27520220666](https://github.com/roojs/OLLMchat/actions/runs/27520220666) | Icon staging: `sidebar-hide-symbolic.svg` missing on build host | `regression/test-r01-bundled-android-icons.sh` |
| **R02** | [27585547860](https://github.com/roojs/OLLMchat/actions/runs/27585547860), [27585952776](https://github.com/roojs/OLLMchat/actions/runs/27585952776), [27586582052](https://github.com/roojs/OLLMchat/actions/runs/27586582052) | `wrap-redirect …/gtk/subprojects/graphene.wrap does not exist` | `regression/test-r02-gtk-bootstrap-restore.sh` |
| **R03** | (fork fixes not in tree) | stale GTK checkout missing roojs/gtk OLLMchat fixes | `regression/test-r03-gtk-patch-marker.sh` |
| **R04** | [27586907940](https://github.com/roojs/OLLMchat/actions/runs/27586907940) | `Undefined constant 'toolchain'` during configure | `regression/test-r04-stale-toolchain-discard.sh` |
| **R05** | (same family as R02) | Meson setup before GTK tree exists | `regression/test-r05-wrap-redirects-need-gtk.sh` |
| **R06** | (CI preflight) | Broken subprojects cache + stale toolchain + configure | `verify-android-ci-preflight.sh` (included in `--full`) |
| **R07** | [27588239244](https://github.com/roojs/OLLMchat/actions/runs/27588239244) (runtime) | TLS / paste / delete fixes missing from APK despite green build | `regression/test-r07-apk-runtime-patches.sh` (runs `verify-apk.sh` binary checks) |
| **R08** | (restore-keys partial hit) | Old subprojects cache restored after `PIXIEWOOD_DEPS_HASH` change | `regression/test-r08-stale-restored-cache-discard.sh` |
| **R09** | [27590212384](https://github.com/roojs/OLLMchat/actions/runs/27590212384) | `validate-restored-caches.sh: CACHE_MATCHED_PIXIEWOOD_BUILD_KEY: unbound variable` | `regression/test-r09-validate-caches-partial-env.sh` |
| **R10** | [27613430785](https://github.com/roojs/OLLMchat/actions/runs/27613430785), [27613805784](https://github.com/roojs/OLLMchat/actions/runs/27613805784) | `gdkandroidollmchatpatch.c` truncated or `g_debug` undeclared | covered by extended `test-r03-gtk-patch-marker.sh` |
| **R11** | [27614072148](https://github.com/roojs/OLLMchat/actions/runs/27614072148) (runtime) | TLS still broken: `libgioopenssl.so` cannot load `libssl` from `filesDir/share/gio/modules/` | `regression/test-r11-gio-openssl-deps.sh` + `verify-apk.sh` OpenSSL asset checks |
| **R12** | [27615842437](https://github.com/roojs/OLLMchat/actions/runs/27615842437) | `verify-apk.sh` grepped C comment `touch selection bubbles` (not in stripped `libgtk-4.so`) | `regression/test-r12-verify-apk-libgtk-strings.sh` |

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

### R03 — GTK fork marker
After bootstrap, `subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c` exists with
the `ollmchat-android-bugs-v4` tag and a complete function body (truncated fork tree
fail compile), and `ImContext.java` contains the `deleteSurrounding` fix.

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
- `libgtk-4.so` contains `ollmchat-android-bugs-v2`, `ollmchat-android-popup-v2`, and `ollmchat-android-tls-v2` (patch marker string literals)
- `classes.dex` uses `deleteSurroundingText` lambda, not `sendKeyEvent` IME deletes
- `classes.dex` contains `syncEditableFromGtk` (IME `Editable` kept in sync for hold-backspace)

Stale compile caches that skip GTK rebuild fail R07 even when setup/configure pass.

### R12 — verify-apk libgtk string literals
Every `strings … libgtk-4.so | grep` pattern in `verify-apk.sh` must appear as a C
string literal in `gdkandroidollmchatpatch.c`. C source comments are not present in
stripped release libraries (CI run 27615842437).

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

## Related scripts (not in the default suite)

| Script | Purpose |
|--------|---------|
| `verify-cross-configure.sh` | Host-side meson cross configure smoke test |
| `verify-cross-compile.sh` | Host-side compile smoke test |
| `verify-apk.sh` | APK contents after a full build |
| `test-gtk-subproject-readiness.sh` | Legacy; superseded by R02 + R06 |
