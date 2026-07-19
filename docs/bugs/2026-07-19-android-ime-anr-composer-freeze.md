# Android IME ANR during chat render — composer freeze

**Status:** ⏳ REOPENED — app freeze insufficient; same deadlock still ANRs (further into load)

**Started:** 2026-07-19  
**Reopened:** 2026-07-19 (after ✅ was premature)

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Was briefly under `docs/bugs/done/2026-07-19-FIXED-…` — **un-archived**; freeze helped but did not eliminate ANR
- ℹ️ `docs/bugs/2026-07-19-android-ime-autocomplete-nofill.md` — same `ImContext` / `blockForMain` bridge
- ℹ️ GTK: `ToplevelActivity.setActiveImContext`, `ImContext.reset` / `finishComposingText`

---

## Problem

- **🔷** Opening / restoring a heavy session on Android: *Input dispatching timed out* (~10s); app shows ANR / appears crashed.
- **🔷** After composer-freeze trial: still happens **regularly**, often **further into** markdown load than before.
- **🔷** Expected: UI stays responsive (or at least does not deadlock) while history markdown renders.

---

## Evidence

### Prior (morning)

- **ℹ️** ANRs 13:45, 13:52, 14:10 — `finishComposingText` → `blockForMain` vs GTK `setActiveImContext` → `restartInput` waiting on `InputMethodManager$H`.

### After freeze + “✅” (afternoon)

- **✔️** Freeze code **is** in installed APK (`streaming_state` / `set_focus(null)` / `can_focus`).
- **✔️** New ANRs **14:48:47** and **14:50:06** (bugreport `/tmp/phone-bugreport-anr2.zip`):
  - **Android `main`:** `Waiting` — `finishComposingText` → `GlibContext.blockForMain` (14:50) or `syncEditableFromGtk` → `blockForMain` (14:48)
  - **`GTK Thread`:** `Blocked` — `InputMethodManager.restartInput` ← `setActiveImContext` waiting to lock `InputMethodManager$H` **held by thread 1**
  - GTK Thread CPU ~10–11s (`utm≈948–1078`) — busy rendering, then hits IME path → deadlock
- **✔️** Same ABBA lock order as morning; freeze only delayed when IME/`setActiveImContext` runs.

### Ruled out

- **🚫** Missing freeze in APK — present.
- **🚫** Desktop markdown hang as primary — fixtures do not hang desktop; ANR stacks are IME bridge.

---

## Root cause

- **✔️** Cross-thread IME bridge deadlock:
  1. Android UI thread runs `finishComposingText` / connection teardown holding `InputMethodManager$H`, then `blockForMain` (waits for GTK).
  2. GTK thread (busy with markdown) calls `setActiveImContext` → **`imm.restartInput(this)` synchronously** and needs that same IMM lock.
  3. Neither proceeds → input dispatch ANR.
- **✔️** App-level composer freeze reduces how often focus/IME attaches early, but **does not** fix `restartInput` being called on the GTK thread while `blockForMain` can run on UI thread.

---

## What we already tried

- **✔️** Keep composer frozen while `restoring_session`; clear focus before hide; `can_focus` follows `editable`.
- **✅→❌** User thought heavy session was fixed; later regular ANRs prove incomplete.

---

## Proposed fix (GTK — was deferred)

- **🔷** Never call `InputMethodManager.restartInput` on the GTK thread.
- **🔷** Match other `Surface` APIs (`updateDND`, `reposition`, `drop`): marshal IMM work to the Android UI thread.

### 1. `ToplevelActivity.java` — `setActiveImContext`

**Where:** `ToplevelView.Surface.setActiveImContext`

#### Replace with

```java
			public void setActiveImContext(ImContext context) {
				if (activeImContext == context)
					return;
				activeImContext = context;
				runOnUiThread(() -> {
					InputMethodManager imm = getSystemService(InputMethodManager.class);
					imm.restartInput(this);
				});
			}
```

### 2. `ImContext.java` — `reset`

**Where:** static `reset(View view)`

#### Replace with

```java
	@Keep
	private static void reset(View view) {
		view.post(() -> {
			InputMethodManager imm = view.getContext().getSystemService(InputMethodManager.class);
			imm.restartInput(view);
		});
	}
```

**Ship path:** refresh `android-bugs.patch` / GTK wrap after local `subprojects/gtk` edit (same as other Android IME patches).

**🚫** Do not remove app-level freeze yet — keep as belt-and-suspenders until ANRs stop.

---

## Attempts / changelog

- **✔️** 2026-07-19 — App freeze applied; briefly marked ✅.
- **✔️** 2026-07-19 — Reopened; ANRs 14:48 / 14:50 same deadlock; proposed `runOnUiThread` / `view.post` for `restartInput`.

---

## Next

- **⏳** 🔷 Approve §1–§2; apply; rebuild APK; open heavy session and confirm no ANR.
- **⏳** If still ANRs → audit other GTK-thread IMM calls.
