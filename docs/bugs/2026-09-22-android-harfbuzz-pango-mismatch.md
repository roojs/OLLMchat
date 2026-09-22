# Android configure: stale harfbuzz 8.4.0, then missing gnutls

**Status:** ⏳ two configure blockers; harfbuzz pin proposed — await apply approval; gnutls needs a direction

**Hit:** 2026-09-21 / 2026-09-22 — `scripts/android/build-chat-poc-apk.sh` (Pixiewood meson reconfigure)

**Related:** [`done/2026-08-20-FIXED-android-pango-glib-mismatch.md`](done/2026-08-20-FIXED-android-pango-glib-mismatch.md) (same wrap-pin / stale-checkout class; R14–R16)

---

## Problem

🔷 Android APK configure dies before any OLLMchat Vala compiles.

- 🔷 **Expected:** `PIXIEWOOD_PHASE=configure` / `scripts/android/build-chat-poc-apk.sh` writes `.pixiewood/bin-aarch64/build.ninja`.
- 🔷 **Actual (1):** GTK `meson.build:451`: `glib-2.0` found **2.84.0** but need `>= 2.89.3` (wrap is **2.90.0**). Unblocked by a one-off `git checkout 2.90.0` on `subprojects/glib`.
- 🔷 **Actual (2):** pango `meson.build:281`: `harfbuzz` found **8.4.0** but need `>= 11.0.0` (overridden).
- 🔷 **Actual (3)** after discarding 8.4.0: `libocrpc/meson.build:44`: `gnutls` pkg-config lookup failed (no Android wrap).

## Evidence

- ℹ️ Configure log: `subprojects/pango/meson.build:281:15: ERROR: Dependency 'harfbuzz' is required but not found.`
- ✔️ `android/pixiewood-wraps/gtk/pango.wrap.pin` is pango **1.58.2** (`d360f140…`); `harfbuzz_req = '>= 11.0.0'`.
- ✔️ GTK nested wrap `subprojects/gtk/subprojects/harfbuzz.wrap` already pins tag **14.4.0** (peeled `36cb489cb02ce4b92099669ba9f9bea348eff93f`).
- ✔️ Top-level `subprojects/harfbuzz.wrap` is wrap-redirect into that GTK wrap.
- ✔️ Live checkout `subprojects/harfbuzz` is still tag **8.4.0** (`63973005…`, dated 2026-06-14). Meson uses the existing tree; it does not re-clone 14.4.0.
- ✔️ `discard_stale_pinned_checkouts` only walks `android/pixiewood-wraps/**/*.wrap` and `gtk/*.wrap.pin`. There is no harfbuzz wrap-git in pixiewood-wraps, so 8.4.0 is never discarded.
- ✔️ `drop_meson_subproject_trees` also omits harfbuzz (gtk / gee / json-glib / soup / libxml2 / sqlite / nghttp2 only).
- ℹ️ GLib 2.84 was the same hole: `discard_stale_pinned_checkouts` skips `glib` because `glib.wrap` uses tag `2.90.0` and HEAD is a commit hash. Not in this cut.
- ✔️ 2026-09-22: `rm -rf subprojects/harfbuzz` then configure cloned tag **14.4.0** (`36cb489cb0…`). Pango / GTK / GtkSourceView configured. Next error is gnutls (below).

## Root cause — harfbuzz

✔️ Pango 1.58.2 (needed by the android-ime GTK pin) requires harfbuzz **>= 11**. The wrap already says **14.4.0**, but a restored/local **8.4.0** checkout is left in place. Meson override-provides that 8.4.0 tree, so configure fails.

🚫 Do not pin pango back to a pre-1.58 tree (GTK wrap needs `>= 1.58`).
🚫 Do not bump glib for this (already 2.90.0).
🚫 Do not name the pin `harfbuzz.wrap` (copied into `subprojects/`; Meson duplicate provider vs wrap-redirect).

## Proposed fix

🔷 Same pattern as pango R14/R16: a `*.wrap.pin` overlay, discard unless HEAD matches, clone before Meson download / skip-download.

### `android/pixiewood-wraps/gtk/harfbuzz.wrap.pin` — pin GTK nested harfbuzz to 14.4.0 peeled commit

#### Add

New file. Commit hash so `discard_git_checkout_unless_revision` can match `HEAD`. Existing `*.wrap.pin` loops overlay it onto `subprojects/gtk/subprojects/harfbuzz.wrap` and clone `subprojects/harfbuzz`.

```
[wrap-git]
directory = harfbuzz
url = https://github.com/harfbuzz/harfbuzz.git
push-url = git@github.com:harfbuzz/harfbuzz.git
# GTK nested wrap uses tag 14.4.0. Pin the peeled commit so
# discard_git_checkout_unless_revision can match HEAD. Pango 1.58.2
# needs harfbuzz >= 11.0.0; a restored 8.4.0 checkout breaks configure.
revision = 36cb489cb02ce4b92099669ba9f9bea348eff93f
depth = 1

[provide]
harfbuzz = libharfbuzz_dep
harfbuzz-subset = libharfbuzz_subset_dep
```

### `scripts/android/gtk-subproject.sh` — `pango_checkout_matches_pin()`: matching harfbuzz helpers

#### Add

Immediately after `pango_checkout_matches_pin()`, same shape. Used by skip-download and R20.

```
harfbuzz_pin_revision() {
  wrap_file_revision "$ROOT_DIR/android/pixiewood-wraps/gtk/harfbuzz.wrap.pin"
}

harfbuzz_checkout_matches_pin() {
  local pin actual
  pin="$(harfbuzz_pin_revision)"
  [ -n "$pin" ] || return 1
  [ -d "$ROOT_DIR/subprojects/harfbuzz/.git" ] || return 1
  actual="$(git -C "$ROOT_DIR/subprojects/harfbuzz" rev-parse HEAD 2>/dev/null || true)"
  [ "$actual" = "$pin" ]
}
```

### `scripts/android/build-pixiewood-apk.sh` — `maybe_download_meson_subprojects()`: skip-download requires harfbuzz pin

#### Replace with

In the skip-download `if`, after `pango_checkout_matches_pin &&`, add `harfbuzz_checkout_matches_pin &&`. Update the stderr line to mention pinned harfbuzz.

```
     pango_checkout_matches_pin &&
     harfbuzz_checkout_matches_pin &&
     libadwaita_checkout_matches_pin &&
```

and

```
    echo "Subprojects cache needs GTK bootstrap, patch, pinned pango/harfbuzz, or floating wrap-git refresh." >&2
```

### `scripts/android/regression/test-r15-glib-stack-wrap-git-pinned.sh` — also assert harfbuzz pin

#### Add

After the pango `assert_pinned_wrap_git` call, one more call:

```
assert_pinned_wrap_git \
  "$ROOT_DIR/android/pixiewood-wraps/gtk/harfbuzz.wrap.pin" harfbuzz
```

### `scripts/android/regression/test-r20-harfbuzz-wrap-pin.sh` — R20: pin, discard 8.4.0, clone 14.4.0

#### Add

New executable script. Same contract as R14 discard + R16 ensure.

```
#!/usr/bin/env bash
# R20 — local 2026-09-21: pango 1.58.2 needs harfbuzz >= 11.0.0; restored
# subprojects/harfbuzz 8.4.0 was kept because there was no wrap.pin.
# GTK nested wrap already says tag 14.4.0; pin the peeled commit.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

PIN="$ROOT_DIR/android/pixiewood-wraps/gtk/harfbuzz.wrap.pin"
NESTED="$ROOT_DIR/subprojects/gtk/subprojects/harfbuzz.wrap"
PIN_REV=36cb489cb02ce4b92099669ba9f9bea348eff93f
HB="$ROOT_DIR/subprojects/harfbuzz"

[ -f "$PIN" ] || { echo "missing pinned harfbuzz wrap: $PIN" >&2; exit 1; }
if ls "$ROOT_DIR/android/pixiewood-wraps/gtk/harfbuzz.wrap" >/dev/null 2>&1; then
  echo "harfbuzz pin must not be named *.wrap (copied into subprojects/; Meson duplicate harfbuzz)" >&2
  exit 1
fi
if git -C "$ROOT_DIR" check-ignore -q "$PIN"; then
  echo "pinned harfbuzz wrap is gitignored (CI will not see it): $PIN" >&2
  exit 1
fi
grep -qE "^revision[[:space:]]*=[[:space:]]*$PIN_REV" "$PIN" ||
  { echo "pinned harfbuzz.wrap must use $PIN_REV (14.4.0 peeled; pango >= 11)" >&2; exit 1; }
grep -qE '^revision[[:space:]]*=[[:space:]]*(main|master|HEAD)[[:space:]]*$' "$PIN" &&
  { echo "pinned harfbuzz.wrap must not track main" >&2; exit 1; }

rm -rf "$HB"
mkdir -p "$HB"
printf '%s\n' "project('harfbuzz', 'c', 'cpp', version: '8.4.0')" \
  > "$HB/meson.build"

prepare_android_subprojects_before_meson
[ -d "$HB" ] && [ ! -d "$HB/.git" ] &&
  { echo "prepare left stale harfbuzz checkout (8.4.0 cache)" >&2; exit 1; }
[ -f "$NESTED" ] || { echo "GTK nested harfbuzz.wrap missing after prepare" >&2; exit 1; }
grep -qE "^revision[[:space:]]*=[[:space:]]*$PIN_REV" "$NESTED" ||
  { echo "GTK nested harfbuzz.wrap was not pinned" >&2; exit 1; }
grep -qE '^revision[[:space:]]*=[[:space:]]*(main|master|HEAD)[[:space:]]*$' "$NESTED" &&
  { echo "GTK nested harfbuzz.wrap still tracks main" >&2; exit 1; }

ensure_pinned_wrap_git_checkouts
harfbuzz_checkout_matches_pin ||
  { echo "R20 harfbuzz checkout is not $PIN_REV after ensure" >&2; exit 1; }
grep -q "version: '8.4.0'" "$HB/meson.build" &&
  { echo "R20 harfbuzz tree still reports 8.4.0 after pin checkout" >&2; exit 1; }

echo "R20 harfbuzz-wrap-pin: OK"
```

### `scripts/android/run-android-regression-tests.sh` — register R20 in `FAST_TESTS`

#### Add

After the R19 line in `FAST_TESTS`:

```
  "$REGRESSION_DIR/test-r20-harfbuzz-wrap-pin.sh"
```

### `docs/android-build-regression-tests.md` — R20 row + section

#### Add

Table row after R19:

```
| **R20** | local 2026-09-21 configure | pango 1.58.2 needs harfbuzz `>= 11`; restored `subprojects/harfbuzz` 8.4.0 kept | `regression/test-r20-harfbuzz-wrap-pin.sh` |
```

And a **What each test checks** subsection after R19:

```
### R20 — harfbuzz wrap must be pinned and stale 8.4.0 discarded
`android/pixiewood-wraps/gtk/harfbuzz.wrap.pin` pins harfbuzz **14.4.0**
(`36cb489cb0…`, peeled from GTK’s nested tag). After GTK bootstrap / restore,
`subprojects/gtk/subprojects/harfbuzz.wrap` matches that pin. A restored
`subprojects/harfbuzz` tree that is not the pinned commit is discarded and
cloned (same as R14/R16 pango) so Meson does not override-provide 8.4.0 to
pango 1.58.2.
```

## Root cause — gnutls

✔️ After harfbuzz 14.4.0, configure reaches `libocrpc` (already on the Android `subdir()` list; Phase 1 also added `libocfiles`). `libocrpc/meson.build` always does `dependency('gnutls')` ([`RPC-8.2.8.2`](../plans/done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) §9). Pixiewood has **no gnutls wrap**. `android/pixiewood-extra.cross` only disables gnutls **inside glib-networking** (OpenSSL TLS). WrapDB has no gnutls wrap.

ℹ️ [`RPC-8.2.8.6`](../plans/done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) Phase 2 `Cert.ensure()` mints a device client leaf via GnuTLS (`create_pem_files`). Android HTTPS takeover needs that mint.

🚫 Do not `#if ANDROID` away `Cert` minting to make configure pass.
🚫 Do not treat the glib-networking `gnutls = 'disabled'` line as the libocrpc switch.

## Proposed fix — gnutls (needs a direction)

- 🔷 Android `Cert.ensure()` must still mint a client leaf (8.2.8.6).
- 💩 **A — GnuTLS wrap stack** (gmp / nettle / libtasn1 / gnutls) under `android/pixiewood-wraps/`, `<gnutls/>` in the chat-poc manifest. No WrapDB port; this is a new Android packaging track.
- 💩 **B — mint with the OpenSSL already in the APK** (`android/pixiewood-wraps/openssl`). `Cert.create_pem_files` would need an OpenSSL path on Android. Not in an approved plan.

## Attempts / changelog

- ℹ️ 2026-09-21: glib checkout moved 2.84 → 2.90 by hand; configure then died on harfbuzz 8.4 vs `>= 11`.
- ✔️ 2026-09-22: discarded `subprojects/harfbuzz` 8.4.0; meson cloned **14.4.0**. Configure then died on gnutls.
- ⏳ Apply harfbuzz wrap.pin + R20 after approval.
- ⏳ GnuTLS: wait for A vs B.

## Next

- 🔷 ⏳ User approve harfbuzz pin apply.
- 🔷 ⏳ User pick gnutls A or B (or another direction).
- 🔷 ⏳ After harfbuzz apply: R14–R16 + R20.
- 💩 glib tag-vs-HEAD skip in `discard_stale_pinned_checkouts` — same class, not this cut.
