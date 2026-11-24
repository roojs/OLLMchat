# Android chat POC — completion backlog

**Status:** 🚫 CLOSED 2026-11-24 — Android is past POC; this umbrella tracker is retired. Only active Android bug left from here: **S3** → [`../2026-09-02-android-add-model-search-popover-layout.md`](../2026-09-02-android-add-model-search-popover-layout.md).

**Started:** 2026-07-18

**Package:** `org.roojs.ollmchat.androidpoc`

**Related:**

- ℹ️ [`2026-07-18-FIXED-android-poc-completion-batch.md`](2026-07-18-FIXED-android-poc-completion-batch.md) — all verified / cancelled items + changelog
- ℹ️ [`2026-07-09-FIXED-android-poc-device-issues.md`](2026-07-09-FIXED-android-poc-device-issues.md) — history / TLS; § Problem 3 → C1 here
- ℹ️ Build: `scripts/android/build-chat-poc-apk.sh` → `scripts/android/adb-install-chat-poc.sh`

**Golden rule:** Android-only edits by default. Shared code needs explicit approval.

---

### C1 — Streaming when screen off / app in background

**Status:** 🚫 CLOSED with tracker — code landed; no scheduled device retest

**What it is:** While the model is **still generating** a reply, Android often kills or suspends the network when you **turn the screen off** or **switch to another app**. Without a foreground service, the SSE stream dies and you get “Network error”.

**What we did:** ✔️ A **foreground service** (`StreamingForegroundService`) — the persistent “Generating reply…” notification — so Android is less likely to kill the connection mid-stream.

**How to test (only if you care about this):**

1. Start a reply that takes several seconds (long prompt or slow model).
2. While tokens are still arriving, **turn the screen off** or **switch to another app** for ~30s.
3. Come back — stream should still be going (or finish cleanly), not instant “Network error”.

**Next:** 🚫 Reopen only if screen-off / background still loses stream on a current APK.

---

### S1 — Settings tab order (Models first)

**Status:** ✅ FIXED — Android Settings opens on **Models** first (no retest needed)

**Detail:** [`2026-08-31-FIXED-android-settings-tab-order.md`](2026-08-31-FIXED-android-settings-tab-order.md)

---

### S3 — Add Model search popover layout (width + height)

**Status:** ⏳ OPEN — tracked separately (not closed with this file)

**Detail:** [`../2026-09-02-android-add-model-search-popover-layout.md`](../2026-09-02-android-add-model-search-popover-layout.md)

---

### S2 — Add Model search empty (TLS)

**Status:** ✅ FIXED — search returns rows

**Detail:** [`2026-08-31-FIXED-android-add-model-search-tls.md`](2026-08-31-FIXED-android-add-model-search-tls.md)

---

### U6 — “Copy output” button

**Status:** 🚫 CLOSED with tracker — feature request; reopen ad hoc if wanted

**What it is:** A **Copy** control on completed assistant messages (copy the model’s reply to the clipboard). Mentioned during Android testing; would live in shared chat UI, not Android-only.

**Next:** 🚫 Nothing to test until someone builds it.

---

### T1 — Composer height after **+**

**Status:** 🚫 CLOSED with tracker — mostly fixed; reopen only if you see it again

**What it is:** After tapping **+** (insert template / fill composer), the text box should **grow in height** to fit wrapped text. Sometimes it stayed one line tall until you typed another character.

**How you’d notice:** Tap **+**, get a multi-line fill — if the composer stays stubby and clips text until you edit, that’s T1. No scheduled test; fix again if it annoys you.

**Prior fixes:** [`2026-07-18-FIXED-composer-plus-no-resize.md`](2026-07-18-FIXED-composer-plus-no-resize.md)

---

### W1–W3 / F1 — WebKit search + media

Tracked under plans, not here:

- ℹ️ W1–W3: [`../../plans/WEBKIT-5.0-webkit-control.md`](../../plans/WEBKIT-5.0-webkit-control.md), [`5.0.1`](../../plans/done/5.0.1-DONE-windows-webkit-accessibility.md), [`5.0.2`](../../plans/done/5.0.2-DONE-android-webkit-control.md)
- ⏳ 🔷 F1 — file / attachment pipeline on input

---

## LLM

- ✔️ 2026-11-24 — User: Android no longer POC; retire this backlog. **S3** add-model popover stays open in its own report.