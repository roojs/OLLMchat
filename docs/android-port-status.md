# Android port — concise status

**Updated:** 2026-06-17  
**Active debug doc (read this for device issues):** [`docs/bugs/2026-06-17-android-chat-poc-device-issues.md`](bugs/2026-06-17-android-chat-poc-device-issues.md)

**Package:** `org.roojs.ollmchat.androidpoc`  
**Build:** `scripts/android/build-chat-poc-apk.sh` → `scripts/android/adb-install-chat-poc.sh`  
**Plan:** [`docs/plans/9.1-android-chat-shell.md`](plans/9.1-android-chat-shell.md)

**Golden rule:** Android port work is **Android-only**. Do not edit shared/desktop code without explicit permission — stop and propose first if it seems necessary.

---

## Summary

| Area | Status |
|------|--------|
| TLS | **Closed** — [`docs/bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md`](bugs/done/2026-06-17-FIXED-android-runtime-tls-ime-paste.md) |
| Config **write** | **Pass** — `files/etc/ollmchat/config.2.json` on device |
| Config **load**, chat boot, agents, input, About icon | **Open** — see active debug doc §2–§7 |
| Next build | **Not done** — fix batch documented in debug doc **Next test batch** |

Use the [device issues doc](bugs/2026-06-17-android-chat-poc-device-issues.md) for per-issue status, desired result, what we tried, and the test loop.

---

## Quick commands

```bash
# Build + install
rm -rf .pixiewood/android/app/src/main/jniLibs   # if symlink step fails
scripts/android/build-chat-poc-apk.sh
scripts/android/adb-install-chat-poc.sh

# Config on device
adb shell cat /storage/emulated/0/Android/data/org.roojs.ollmchat.androidpoc/files/etc/ollmchat/config.2.json

# Cold start log
adb shell am force-stop org.roojs.ollmchat.androidpoc && adb logcat -c
adb shell am start -n org.roojs.ollmchat.androidpoc/org.gtk.android.ToplevelActivity
```

---

## Phase checklist (plan 9.1)

- [x] Phase 0 — Config2-only load  
- [x] Phase 1 — Android shell + settings + bootstrap  
- [x] Phase 2 — ChatWidget + HistoryBrowser wired in code  
- [ ] Phase 3 — Device verify — **blocked** on open issues in debug doc  
