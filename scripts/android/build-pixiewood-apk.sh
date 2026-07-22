#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ROOT_DIR/.android-sdk}"
PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-shell-poc.xml}"
PIXIEWOOD_DIR="${PIXIEWOOD_DIR:-$ROOT_DIR/.android-tools/gtk-android-builder}"
PIXIEWOOD_ARCH="${PIXIEWOOD_ARCH:-aarch64}"
PIXIEWOOD_BUILD_DIR="$ROOT_DIR/.pixiewood/bin-$PIXIEWOOD_ARCH"
PIXIEWOOD="${PIXIEWOOD:-}"
GTK_ANDROID_BUILDER_REVISION="${GTK_ANDROID_BUILDER_REVISION:-}"
PIXIEWOOD_PHASE="${PIXIEWOOD_PHASE:-all}"
# Strip native debug symbols on meson install (debug buildtype, debug Gradle APK).
# Used for GitHub Release assets; local/manual builds leave this unset.
PIXIEWOOD_STRIP_DEBUG="${PIXIEWOOD_STRIP_DEBUG:-}"

read_gtk_android_builder_revision() {
  local revision_file="$ROOT_DIR/scripts/android/gtk-android-builder.revision"
  if [ -z "$GTK_ANDROID_BUILDER_REVISION" ] && [ -f "$revision_file" ]; then
    GTK_ANDROID_BUILDER_REVISION="$(
      grep -v '^[[:space:]]*#' "$revision_file" | grep -v '^[[:space:]]*$' | head -n1 | tr -d '[:space:]'
    )"
  fi
}

install_pixiewood_extra_wraps() {
  local extra="$ROOT_DIR/android/pixiewood-wraps"
  if [ ! -d "$extra" ]; then
    return
  fi

  mkdir -p "$ROOT_DIR/subprojects"

  local dep_dir dep dest wrap
  for dep_dir in "$extra"/*/; do
    dep="$(basename "$dep_dir")"
    dest="$PIXIEWOOD_DIR/prepare/wraps/$dep"
    mkdir -p "$dest"
    cp -a "$dep_dir"/* "$dest/"

    for wrap in "$dep_dir"/*.wrap; do
      if [ -f "$wrap" ]; then
        cp -a "$wrap" "$ROOT_DIR/subprojects/"
      fi
    done

    if [ -d "$dep_dir/packagefiles" ]; then
      mkdir -p "$ROOT_DIR/subprojects/packagefiles"
      cp -a "$dep_dir/packagefiles/." "$ROOT_DIR/subprojects/packagefiles/"
    fi
  done
}

pixiewood_prefix_has_pkg() {
  local pkg="$1"
  find "$PIXIEWOOD_BUILD_DIR" -name "$pkg.pc" -print -quit 2>/dev/null | grep -q .
}

chat_pixiewood_prefix_ready() {
  pixiewood_prefix_has_pkg gee-0.8 &&
    pixiewood_prefix_has_pkg libsoup-3.0 &&
    pixiewood_prefix_has_pkg json-glib-1.0 &&
    pixiewood_prefix_has_pkg libxml-2.0 &&
    pixiewood_prefix_has_pkg sqlite3
}

needs_pixiewood_prepare() {
  ensure_pixiewood_compile_state_consistent

  if [ ! -f "$PIXIEWOOD_BUILD_DIR/build.ninja" ] ||
     [ ! -f "$ROOT_DIR/.pixiewood/pixiewood.ini" ] ||
     [ ! -f "$ROOT_DIR/.pixiewood/toolchain.cross" ] ||
     ! pixiewood_toolchain_cross_valid; then
    return 0
  fi

  if [[ "$PIXIEWOOD_MANIFEST" == *pixiewood-chat-poc.xml ]] &&
     ! chat_pixiewood_prefix_ready; then
    echo "Pixiewood prefix is missing chat POC dependencies; rerunning prepare." >&2
    return 0
  fi

  if [[ "$PIXIEWOOD_MANIFEST" == *pixiewood-chat-poc.xml ]] &&
     ! pixiewood_prefix_has_patched_gtk; then
    echo "Pixiewood prefix was built without OLLMchat GTK fork markers; rerunning prepare." >&2
    return 0
  fi

  return 1
}

version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
}

pixiewood_build_meson_version() {
  local log="$PIXIEWOOD_BUILD_DIR/meson-logs/meson-log.txt"

  if [ ! -f "$log" ]; then
    return 1
  fi

  grep -m1 '^Version: ' "$log" | sed 's/^Version: //'
}

pixiewood_root_meson_version() {
  local root_meson="$ROOT_DIR/.android-tools/meson/root/usr/bin/meson"

  if [ ! -x "$root_meson" ]; then
    return 1
  fi

  "$root_meson" --version
}

ensure_android_meson() {
  MESON_FOR_ANDROID="$ROOT_DIR/scripts/android/meson-for-pixiewood.sh"
  "$ROOT_DIR/scripts/android/ensure-meson.sh" >/dev/null
}

# shellcheck source=android-meson-path.sh
source "$ROOT_DIR/scripts/android/android-meson-path.sh"
# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"
# shellcheck source=pixiewood-cache.sh
source "$ROOT_DIR/scripts/android/pixiewood-cache.sh"

drop_meson_subproject_trees() {
  local wrap_dir
  for wrap_dir in \
    gtk \
    libgee-0.20.8 \
    json-glib-1.10.8 \
    libsoup-3.6.5 \
    libxml2-2.15.3 \
    sqlite-amalgamation-3530200 \
    nghttp2-1.62.1; do
    rm -rf "$ROOT_DIR/subprojects/$wrap_dir"
  done
}

download_meson_subprojects() {
  local meson="$1"

  if ! compgen -G "$ROOT_DIR/subprojects/*.wrap" > /dev/null; then
    return
  fi

  if [ "${PIXIEWOOD_FORCE_SUBPROJECT_REFRESH:-}" = "1" ] ||
     [ "${CI:-}" != "true" ] ||
     [ "${PIXIEWOOD_REFRESH_SUBPROJECTS:-}" = "1" ]; then
    drop_meson_subproject_trees
  fi

  # Root-level wrap-redirects point at gtk/subprojects/*.wrap; GTK must exist
  # before meson subprojects download or setup can run.
  ensure_gtk_subproject_checked_out
  ensure_gtk_subproject_patched

  with_android_meson_path "$meson" subprojects download --sourcedir "$ROOT_DIR"
  ensure_gtk_subproject_patched
}

ensure_gtk_android_builder() {
  if [ -n "$PIXIEWOOD" ]; then
    return
  fi
  if command -v pixiewood >/dev/null 2>&1; then
    PIXIEWOOD="$(command -v pixiewood)"
    return
  fi

  read_gtk_android_builder_revision

  if [ ! -x "$PIXIEWOOD_DIR/pixiewood" ]; then
    rm -rf "$PIXIEWOOD_DIR"
    git clone https://github.com/sp1ritCS/gtk-android-builder.git "$PIXIEWOOD_DIR"
    if [ -n "$GTK_ANDROID_BUILDER_REVISION" ]; then
      git -C "$PIXIEWOOD_DIR" checkout "$GTK_ANDROID_BUILDER_REVISION"
    fi
  fi
  PIXIEWOOD="$PIXIEWOOD_DIR/pixiewood"
}

pixiewood_configure_options() {
  if [ ! -f "$PIXIEWOOD_MANIFEST" ]; then
    echo "Pixiewood manifest not found: $PIXIEWOOD_MANIFEST" >&2
    exit 1
  fi
  python3 - "$PIXIEWOOD_MANIFEST" <<'PY'
import sys
import xml.etree.ElementTree as ET

NS = {
    "pw": "https://sp1rit.arpa/pixiewood/",
}
tree = ET.parse(sys.argv[1])
root = tree.getroot()
for option in root.findall(".//pw:build/pw:configure-options/pw:option", NS):
    text = (option.text or "").strip()
    if text:
        print(text)
PY
}

reconfigure_pixiewood_build() {
  local meson="$1"
  shift
  local -a configure_options=("$@")
  local -a cross_files=(
    --cross-file "$ROOT_DIR/.pixiewood/toolchain.cross"
    --cross-file "$PIXIEWOOD_DIR/prepare/arch/$PIXIEWOOD_ARCH.cross"
    --cross-file "$PIXIEWOOD_DIR/prepare/android.cross"
  )

  if [ -f "$ROOT_DIR/android/pixiewood-extra.cross" ]; then
    cross_files+=(--cross-file "$ROOT_DIR/android/pixiewood-extra.cross")
  fi

  local -a setup_args=(setup)
  if [ -f "$PIXIEWOOD_BUILD_DIR/build.ninja" ]; then
    setup_args+=(--reconfigure)
  fi

  # Meson keeps the strip option across reconfigures; always set it explicitly
  # so a prior release build cannot leave manual/debug APKs stripped.
  local -a strip_args=(-Dstrip=false)
  if [ "$PIXIEWOOD_STRIP_DEBUG" = "1" ]; then
    strip_args=(-Dstrip=true)
  fi

  with_android_meson_path "$meson" "${setup_args[@]}" \
    "${cross_files[@]}" \
    --buildtype debug \
    "${strip_args[@]}" \
    "${configure_options[@]}" \
    "$PIXIEWOOD_BUILD_DIR" \
    "$ROOT_DIR"
}

init_pixiewood_env() {
  if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ] ||
     [ ! -d "$ANDROID_SDK_ROOT/ndk" ]; then
    "$ROOT_DIR/scripts/android/install-sdk.sh"
  fi

  ensure_gtk_android_builder
  install_pixiewood_extra_wraps
  ensure_pixiewood_compile_state_consistent

  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export ANDROID_SDK_ROOT
  export CC="${CC:-gcc}"
  export CXX="${CXX:-g++}"
  export CC_FOR_BUILD="${CC_FOR_BUILD:-gcc}"
  export CXX_FOR_BUILD="${CXX_FOR_BUILD:-g++}"
  ensure_android_meson
  mapfile -t PIXIEWOOD_CONFIGURE_OPTIONS < <(pixiewood_configure_options)
}

run_pixiewood() {
  with_android_meson_path "$PIXIEWOOD" -C "$ROOT_DIR" "$@"
}

# GIO TLS modules live under lib/.../gio/modules in jniLibs. They must be on a
# real filesystem path for g_io_modules_scan_*. Modern AGP rejects
# android:extractNativeLibs in the manifest; useLegacyPackaging extracts them.
patch_pixiewood_gradle_native_libs() {
  local gradle="$ROOT_DIR/.pixiewood/android/app/build.gradle"

  if [ ! -f "$gradle" ] || grep -q 'useLegacyPackaging' "$gradle"; then
    return 0
  fi

  sed -i '/enableKotlin = false/a\
\
    packaging {\
        jniLibs {\
            useLegacyPackaging = true\
        }\
    }' "$gradle"
}

# Android only packages top-level lib/ABI/*.so from jniLibs. TLS uses static
# gioopenssl linked into the app (g_io_openssl_load); no GIO modules in assets.
write_ollmchat_android_runtime_tag() {
  local dest="$ROOT_DIR/.pixiewood/android/app/src/main/assets/share"

  mkdir -p "$dest"
  printf 'ollmchat-android-bugs-v11\n' > "$dest/ollmchat-android-runtime.tag"
}

# Android native code has no /etc/ssl/certs/. Ship the build host's Debian
# ca-certificates bundle; GTK extracts assets/share/ to filesDir/share/ before
# main(). ollmapp_configure_android_gio_tls_modules() sets SSL_CERT_FILE.
install_ca_certificates_to_assets() {
  local ca_src="${CA_CERTIFICATES_SRC:-/etc/ssl/certs/ca-certificates.crt}"
  local dest="$ROOT_DIR/.pixiewood/android/app/src/main/assets/share/ssl/certs"

  if [ ! -f "$ca_src" ]; then
    echo "CA bundle missing on build host: $ca_src" >&2
    echo "Install ca-certificates (e.g. apt install ca-certificates)." >&2
    exit 1
  fi

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -a "$ca_src" "$dest/ca-certificates.crt"

  if [ ! -s "$dest/ca-certificates.crt" ]; then
    echo "CA bundle staging failed: $dest/ca-certificates.crt" >&2
    exit 1
  fi
}

# Pixiewood only copies bin, lib, and glib schemas into APK assets. GTK UI icons
# (header bar buttons, symbolic actions, etc.) are listed in android/icons/manifest
# and staged from the build host's icon themes into assets/share/icons/Adwaita/.
# POC Java helpers (wake lock + streaming FGS) live under android/*.java.
# WebViewHost Java comes from the webkitgtk-android subproject (5.0.2).
install_poc_java() {
  local dest_dir="$ROOT_DIR/.pixiewood/android/app/src/main/java/org/roojs/ollmchat/androidpoc"
  local java_root="$ROOT_DIR/.pixiewood/android/app/src/main/java"
  local wake_src="$ROOT_DIR/android/PartialWakeLock.java"
  local fg_src="$ROOT_DIR/android/StreamingForeground.java"
  local fgs_src="$ROOT_DIR/android/StreamingForegroundService.java"
  local wka_dir="$ROOT_DIR/subprojects/webkitgtk-android"
  local wka_install=""

  if [ ! -f "$wake_src" ]; then
    echo "PartialWakeLock.java missing: $wake_src" >&2
    exit 1
  fi
  if [ ! -f "$fg_src" ] || [ ! -f "$fgs_src" ]; then
    echo "StreamingForeground Java sources missing under android/" >&2
    exit 1
  fi
  mkdir -p "$dest_dir"
  rm -f "$dest_dir/KeepScreenOn.java"
  cp -a "$wake_src" "$dest_dir/PartialWakeLock.java"
  cp -a "$fg_src" "$dest_dir/StreamingForeground.java"
  cp -a "$fgs_src" "$dest_dir/StreamingForegroundService.java"

  if [ -x "$wka_dir/scripts/android/install-webview-java.sh" ]; then
    wka_install="$wka_dir/scripts/android/install-webview-java.sh"
  elif [ -x /home/alan/git/webkitgtk-android/scripts/android/install-webview-java.sh ]; then
    wka_install=/home/alan/git/webkitgtk-android/scripts/android/install-webview-java.sh
  fi
  if [ -z "$wka_install" ]; then
    echo "webkitgtk-android install-webview-java.sh missing (subproject or /home/alan/git/webkitgtk-android)" >&2
    exit 1
  fi
  "$wka_install" "$java_root"
}

# Pixiewood regenerate may omit permissions / reset launchMode; keep POC defaults.
patch_android_manifest() {
  local manifest="$ROOT_DIR/.pixiewood/android/app/src/main/AndroidManifest.xml"

  if [ ! -f "$manifest" ]; then
    echo "AndroidManifest missing: $manifest" >&2
    exit 1
  fi
  if ! grep -q 'android.permission.WAKE_LOCK' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.WAKE_LOCK"/>' "$manifest"
  fi
  if ! grep -q 'android.permission.FOREGROUND_SERVICE"' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>' "$manifest"
  fi
  if ! grep -q 'FOREGROUND_SERVICE_DATA_SYNC' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>' "$manifest"
  fi
  if ! grep -q 'android.permission.POST_NOTIFICATIONS' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>' "$manifest"
  fi
  # C1: dataSync FGS while streaming (Java StreamingForegroundService).
  if ! grep -q 'StreamingForegroundService' "$manifest"; then
    sed -i '/<\/application>/i\    <service android:name="org.roojs.ollmchat.androidpoc.StreamingForegroundService" android:exported="false" android:foregroundServiceType="dataSync"/>' "$manifest"
  fi
  # C5: standard stacks a new ToplevelActivity on each launcher return (full reboot feel).
  if grep -q 'android:launchMode="standard"' "$manifest"; then
    sed -i 's/android:launchMode="standard"/android:launchMode="singleTask"/' "$manifest"
  fi
}

install_icon_themes_to_assets() {
  local manifest="$ROOT_DIR/android/icons/manifest"
  local index_theme="$ROOT_DIR/android/icons/Adwaita/index.theme"
  local assets_icons="$ROOT_DIR/.pixiewood/android/app/src/main/assets/share/icons"
  local stage="$ROOT_DIR/.pixiewood/android-icon-stage"
  local stage_adwaita="$stage/Adwaita"
  local dest_relpath source_theme source_relpath src dest_file dest_dir line

  if [ ! -f "$manifest" ]; then
    echo "Android icon manifest missing: $manifest" >&2
    exit 1
  fi
  if [ ! -f "$index_theme" ]; then
    echo "Android icon index.theme missing: $index_theme" >&2
    exit 1
  fi

  rm -rf "$stage" "$assets_icons/Adwaita"
  mkdir -p "$stage_adwaita"
  cp -a "$index_theme" "$stage_adwaita/"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "$line" ] && continue

    dest_relpath="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    source_theme="${line%%$'\t'*}"
    source_relpath="${line#*$'\t'}"

    if [ "$source_theme" = bundled ]; then
      src="$ROOT_DIR/android/icons/Adwaita/$dest_relpath"
    else
      src="/usr/share/icons/$source_theme/$source_relpath"
    fi
    if [ ! -f "$src" ]; then
      echo "Icon source missing: $src" >&2
      if [ "$source_theme" = bundled ]; then
        echo "Add the file under android/icons/Adwaita/ or fix android/icons/manifest." >&2
      else
        echo "Install adwaita-icon-theme on the build host or mark the row bundled in the manifest." >&2
      fi
      exit 1
    fi

    dest_file="$stage_adwaita/$dest_relpath"
    dest_dir="$(dirname "$dest_file")"
    mkdir -p "$dest_dir"
    cp -a "$src" "$dest_file"
  done < "$manifest"

  mkdir -p "$assets_icons"
  cp -rL "$stage_adwaita" "$assets_icons/"
  rm -rf "$stage"

  if [ ! -f "$assets_icons/Adwaita/symbolic/actions/sidebar-show-symbolic.svg" ]; then
    echo "Expected icon missing after staging: sidebar-show-symbolic.svg" >&2
    exit 1
  fi
}

# Pixiewood generate symlinks jniLibs -> root/lib. Materialize a real copy
# after meson install so Gradle sees a normal directory tree for top-level .so
# files, then run Gradle ourselves.
materialize_pixiewood_jni_libs() {
  local jni="$ROOT_DIR/.pixiewood/android/app/src/main/jniLibs"
  local root_lib="$ROOT_DIR/.pixiewood/root/lib"

  if [ ! -d "$root_lib" ]; then
    echo "Pixiewood install tree missing: $root_lib" >&2
    exit 1
  fi

  rm -f "$jni"
  rm -rf "$jni"
  mkdir -p "$jni"
  cp -a "$root_lib/." "$jni/"
}

run_pixiewood_gradle_assemble() {
  (
    cd "$ROOT_DIR/.pixiewood/android"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    ./gradlew --no-daemon assembleDebug
  )
}

maybe_download_meson_subprojects() {
  local meson="$1"

  prepare_android_subprojects_before_meson

  if [ "${PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD:-}" = "1" ] &&
     [ -f "$(gtk_subproject_patch_marker)" ] &&
     gtk_subproject_is_complete; then
    echo "Skipping Meson subprojects download (restored from cache)."
    return
  fi

  if [ "${PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD:-}" = "1" ]; then
    echo "Subprojects cache needs GTK bootstrap or patch; re-downloading wraps." >&2
  fi

  echo "Downloading Meson subprojects for Android wraps."
  download_meson_subprojects "$meson"
}

pixiewood_meson_strip_enabled() {
  local coredata="$PIXIEWOOD_BUILD_DIR/meson-private/coredata.dat"

  [ -f "$coredata" ] && grep -q '^strip = true' "$coredata"
}

pixiewood_strip_setting_matches() {
  if [ "$PIXIEWOOD_STRIP_DEBUG" = "1" ]; then
    pixiewood_meson_strip_enabled
  else
    ! pixiewood_meson_strip_enabled
  fi
}

maybe_reconfigure_pixiewood_build() {
  local meson="$1"
  shift
  local current configured root_current
  local meson_min="${MESON_MIN_VERSION:-1.8.0}"

  ensure_pixiewood_compile_state_consistent

  if [ "${PIXIEWOOD_SKIP_RECONFIGURE:-}" = "1" ] &&
     pixiewood_compile_cache_looks_usable; then
    current="$("$meson" --version)"
    configured="$(pixiewood_build_meson_version || true)"
    root_current="$(pixiewood_root_meson_version || true)"
    if pixiewood_strip_setting_matches &&
       [ -n "$configured" ] &&
       version_ge "$configured" "$meson_min" &&
       version_ge "$current" "$meson_min" &&
       [ -n "$root_current" ] &&
       version_ge "$root_current" "$meson_min" &&
       [ "$configured" = "$current" ] &&
       [ "$current" = "$root_current" ]; then
      echo "Skipping Pixiewood Meson reconfigure (restored compile cache)."
      return
    fi
    if [ -n "$configured" ]; then
      echo "Pixiewood compile cache used Meson $configured; reconfiguring with Meson $current (root: ${root_current:-unknown})." >&2
    fi
    if ! pixiewood_strip_setting_matches; then
      if [ "$PIXIEWOOD_STRIP_DEBUG" = "1" ]; then
        echo "Meson strip option does not match release build; reconfiguring with -Dstrip=true." >&2
      else
        echo "Meson strip option does not match debug build; reconfiguring with -Dstrip=false." >&2
      fi
    fi
  fi

  reconfigure_pixiewood_build "$meson" "$@"
}

run_pixiewood_configure() {
  init_pixiewood_env
  maybe_download_meson_subprojects "$MESON_FOR_ANDROID"

  if needs_pixiewood_prepare; then
    run_pixiewood prepare \
      --sdk "$ANDROID_SDK_ROOT" \
      --meson "$MESON_FOR_ANDROID" \
      "$PIXIEWOOD_MANIFEST"
  fi

  echo "Reconfiguring Pixiewood Meson build (configure-only)."
  maybe_reconfigure_pixiewood_build "$MESON_FOR_ANDROID" "${PIXIEWOOD_CONFIGURE_OPTIONS[@]}"

  echo "Android cross configure succeeded for $PIXIEWOOD_BUILD_DIR"
}

run_pixiewood_setup() {
  init_pixiewood_env
  maybe_download_meson_subprojects "$MESON_FOR_ANDROID"

  if needs_pixiewood_prepare; then
    run_pixiewood prepare \
      --sdk "$ANDROID_SDK_ROOT" \
      --meson "$MESON_FOR_ANDROID" \
      "$PIXIEWOOD_MANIFEST"
  fi
}

run_pixiewood_build() {
  init_pixiewood_env
  maybe_download_meson_subprojects "$MESON_FOR_ANDROID"

  echo "Reconfiguring Pixiewood Meson build."
  maybe_reconfigure_pixiewood_build "$MESON_FOR_ANDROID" "${PIXIEWOOD_CONFIGURE_OPTIONS[@]}"

  run_pixiewood generate
  patch_pixiewood_gradle_native_libs
  run_pixiewood build --skip-gradle
  materialize_pixiewood_jni_libs
  write_ollmchat_android_runtime_tag
  install_ca_certificates_to_assets
  install_icon_themes_to_assets
  install_poc_java
  patch_android_manifest
  run_pixiewood_gradle_assemble
  verify_apk_script="${PIXIEWOOD_VERIFY_APK_SCRIPT:-$ROOT_DIR/scripts/android/verify-apk.sh}"
  "$verify_apk_script"

  if [ "$PIXIEWOOD_STRIP_DEBUG" = "1" ]; then
    echo "Built debug APK with native debug symbols stripped (PIXIEWOOD_STRIP_DEBUG=1)."
  fi

  echo "Generated Android artifacts under $ROOT_DIR/.pixiewood/android/app/build/outputs"
}

case "$PIXIEWOOD_PHASE" in
  configure)
    run_pixiewood_configure
    ;;
  setup)
    run_pixiewood_setup
    ;;
  build)
    run_pixiewood_build
    ;;
  all)
    run_pixiewood_setup
    run_pixiewood_build
    ;;
  *)
    echo "Unknown PIXIEWOOD_PHASE: $PIXIEWOOD_PHASE (expected configure, setup, build, or all)" >&2
    exit 2
    ;;
esac
