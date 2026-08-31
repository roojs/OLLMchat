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

**Status:** 🚫 PASSED OVER — fix in Knowles GTK IME, not OLLMchat (2026-07-24)

**Detail:** [`done/2026-07-19-CLOSED-android-ime-autocomplete-nofill.md`](done/2026-07-19-CLOSED-android-ime-autocomplete-nofill.md)

**Next:** 🚫 Do not implement in this repo; follow Knowles GTK / EntryPopupTest.

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

### S1 — Settings tab order (Models first)

**Status:** ⏳ OPEN — Connections is first; user wants Models first

**Detail:** [`2026-08-31-android-settings-tab-order.md`](2026-08-31-android-settings-tab-order.md)

---

### S2 — Add Model search empty (TLS)

**Status:** ✔️ applied (`apply_to_session` on catalog soup) — await user ✅ after APK rebuild

**Detail:** [`2026-08-31-android-add-model-search-tls.md`](2026-08-31-android-add-model-search-tls.md)

---

### U6 — Global copy button

**Status:** ⏳ 🔷 open — “Copy output” at end of completed chat cycles  
**Note:** ℹ️ General / shared product feature (not Android-specific). Parked on this tracker only because it was exercised during Android testing.

---

### W1–W3 / F1 — WebKit search + media

Tracked under plans, not here:

- ℹ️ W1–W3: [`WEBKIT-5.0-webkit-control.md`](../plans/WEBKIT-5.0-webkit-control.md), [`5.0.1`](../plans/done/5.0.1-DONE-windows-webkit-accessibility.md), [`5.0.2`](../plans/done/5.0.2-DONE-android-webkit-control.md)
- ⏳ 🔷 F1 — file / attachment pipeline on input

---

## Suggested order

1. **S2** — Add Model search TLS
2. **S1** — Settings Models-first tab order
3. **C1** — device verify FGS
4. **U6** — global copy
5. **T1** — when it regresses badly
4. 🚫 **IME-3** — passed over (GTK Knowles)
5. **W / F1** — feature track (may need shared-code approval)
