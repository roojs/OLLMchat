# Android chat POC — completion backlog

**Status:** ⏳ OPEN — remaining Android POC work only.

**Started:** 2026-07-18

**Package:** `org.roojs.ollmchat.androidpoc`

**Related:**

- ℹ️ [`done/2026-07-18-FIXED-android-poc-completion-batch.md`](done/2026-07-18-FIXED-android-poc-completion-batch.md) — all verified / cancelled items + changelog
- ℹ️ [`done/2026-07-09-FIXED-android-poc-device-issues.md`](done/2026-07-09-FIXED-android-poc-device-issues.md) — history / TLS; § Problem 3 → C1 here
- ℹ️ Build: `scripts/android/build-chat-poc-apk.sh` → `scripts/android/adb-install-chat-poc.sh`

**Golden rule:** Android-only edits by default. Shared code needs explicit approval.

---

### IME-3 — Spell-correct does not replace typed word

**Status:** ⏳ OPEN — device-verified on EntryPopupTest; still broken; must fix for chat POC

**Expected:** 🔷 Type `TAT` → tap Gboard’s `THAT` → field becomes `THAT`. Leave-field must not double-fill (IME-2).

**Actual:** 🔷 Suggestion tap does not delete/replace the typed prefix; correction does not land.

**Cause:** ✔️ Gboard calls `InputConnection.replaceText(start, end, text)`; our bridge only updates the Android Editable, so GTK still shows the typo until a later finish/sync.

**Tried:** ✔️ Knowles `finishComposingText` Editable≠GTK — late/insufficient. Debug log captured `replaceText(10,13,"rat ")` with GTK still `… tat`.

**Next:** ⏳ 🔷 Apply `replaceText` into GTK on Knowles; re-verify; then ship to chat POC. Detail: [`2026-07-19-android-ime-autocomplete-nofill.md`](2026-07-19-android-ime-autocomplete-nofill.md).

---

### C1 — Sleep / network disconnect (critical)

**Status:** ⏳ OPEN — FGS `dataSync` applied; await device verify

**Expected:** 🔷 Mid-stream survives screen-off / brief app flip (or clear interrupt UX).

**Actual:** 🔷 OS drops TCP → libsoup SSE dies → “Network error”; no resume.

**Applied:** ✔️ Java `StreamingForegroundService` + JNI + Vala start/stop on `session.is_running`; wake lock alone was insufficient.

**Next:** ⏳ 🔷 Rebuild APK; screen-off / flip mid-stream — expect “Generating reply…” notification + stream survival. Soften error copy only after that.

---

### T1 — Message input height flakiness

**Status:** ⏳ 🔷 still open — improved, not fully reliable (e.g. after **+** fill)

**ℹ️** Shared `libollmchatgtk` (`ScrolledView` / chat input) — **not Android-backend-specific**; exercised hard on the phone. Prior fixes: [`done/2026-07-18-FIXED-composer-plus-no-resize.md`](done/2026-07-18-FIXED-composer-plus-no-resize.md), height bugs under `docs/bugs/done/` (2026-07-16 … 2026-07-19).

**Next:** ⏳ 🔷 Revisit when it bites again; not blocking other POC work.

---

### U6 — Global copy button

**Status:** ⏳ 🔷 open — “Copy output” at end of completed chat cycles  
**Note:** ℹ️ General / shared product feature (not Android-specific). Parked on this tracker only because it was exercised during Android testing.

---

### W1–W3 / F1 — WebKit search + media

Tracked under plans, not here:

- ℹ️ W1–W3: [`5.0-ACTIVE-webkit-control.md`](../plans/5.0-ACTIVE-webkit-control.md), [`5.0.1`](../plans/5.0.1-windows-webkit-accessibility.md), [`5.0.2`](../plans/5.0.2-android-webkit-control.md)
- ⏳ 🔷 F1 — file / attachment pipeline on input

---

## Suggested order

1. **IME-3** — fix suggestion replace (`TAT`→`THAT`); then ship to chat POC
2. **C1** — device verify FGS
3. **U6** — global copy
4. **T1** — when it regresses badly
5. **W / F1** — feature track (may need shared-code approval)
