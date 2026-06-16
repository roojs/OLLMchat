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
| **R03** | (patch not in APK) | `android-bugs.patch` not applied to cached GTK | `regression/test-r03-gtk-patch-marker.sh` |
| **R04** | [27586907940](https://github.com/roojs/OLLMchat/actions/runs/27586907940) | `Undefined constant 'toolchain'` during configure | `regression/test-r04-stale-toolchain-discard.sh` |
| **R05** | (same family as R02) | Meson setup before GTK tree exists | `regression/test-r05-wrap-redirects-need-gtk.sh` |
| **R06** | (CI preflight) | Broken subprojects cache + stale toolchain + configure | `verify-android-ci-preflight.sh` (included in `--full`) |

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
After bootstrap, `subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c` exists and
`ImContext.java` contains the `deleteSurrounding` fix.

### R04 — stale toolchain discard
Invalid `toolchain.cross` (NDK path missing) triggers discard of ini + bin-aarch64 +
toolchain together — no partial Pixiewood state left for configure.

### R05 — wrap-redirects need GTK
`subprojects/graphene.wrap` redirects into `gtk/subprojects/`; meson cannot download
wraps until GTK is bootstrapped.

### R06 — CI preflight (full only)
Simulates restored CI caches (broken GTK + bad toolchain), runs `PIXIEWOOD_PHASE=setup`
and `configure`, asserts `build.ninja` exists.

---

## Related scripts (not in the default suite)

| Script | Purpose |
|--------|---------|
| `verify-cross-configure.sh` | Host-side meson cross configure smoke test |
| `verify-cross-compile.sh` | Host-side compile smoke test |
| `verify-apk.sh` | APK contents after a full build |
| `test-gtk-subproject-readiness.sh` | Legacy; superseded by R02 + R06 |
