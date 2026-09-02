# Android About hang: Adw.AboutWindow second toplevel vs singleTask

**Status:** ✅ FIXED — user closed 2026-09-02 (About opens on first tap)

**Started:** 2026-08-31

**Package:** `org.roojs.ollmchat.androidpoc` pid **32693**

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ C5 `launchMode=singleTask` — [`done/2026-07-18-FIXED-android-poc-completion-batch.md`](done/2026-07-18-FIXED-android-poc-completion-batch.md)
- ℹ️ BG-2 — [`docs/android/2026-07-20-user-experience.md`](../android/2026-07-20-user-experience.md)
- ℹ️ June 18 recreate-on-show (second-present **crash**, not this hang) — `ollmapp/About.vala`
- ℹ️ Settings already uses `Adw.Dialog.present(parent)` on the same toplevel (`ollmapp/android/MainDialog.vala`)

---

## Problem

🔷 **First tap** of About on Android: no About UI, chat shell frozen. Never works (not a second-open or Home/Recents issue). Force-stop required. Later Home/Recents still shows that same frozen shell.

---

## Evidence

Device SM_S9380, 2026-08-31. Main logcat had already rotated; `events` buffer still had the repro.

- ✔️ 08:42:55 — process start, one `ToplevelActivity`, task `sz=1`
- ✔️ 08:42:58.544 — tap (`input_interaction` on the same window)
- ✔️ 08:42:58.700 — **the app** fires `MAIN` at `ToplevelActivity` (GDK starting a **second** activity for `AboutWindow`):
  `wm_new_intent … startActivityAsUser:org.roojs.ollmchat.androidpoc`
- ✔️ Android does **not** create that second activity. `singleTask` delivers `onNewIntent` to the **existing** one (pause/resume in **2 ms** — internal, not the user leaving the app). No second `SurfaceView`
- ✔️ `dumpsys window`: still **one** window (`ToplevelActivity`)
- ✔️ `launchMode=2` (`singleTask`) — C5 Home/Recents workaround. Same flag is why the About activity never appears
- ✔️ GTK Thread wchan `do_sys_poll`, **0% CPU**, all 27 threads sleeping. Not a spin, not an ANR, not a JNI deadlock
- ✔️ debuggerd needs root — no native stacks. `run-as` gave wchan only
- 🚫 Not the June 18 second-show crash (recreate `AboutWindow`). This is **first** tap

---

## Root cause

✔️ First tap calls `Adw.AboutWindow.present()`. That class is a **separate `Gtk.Window`**. GDK-Android maps every `Gtk.Window` to a **new `ToplevelActivity`**.

✔️ C5 `singleTask` means that second `MAIN` never becomes a new activity (it is `onNewIntent` on the chat shell). About still takes a **modal grab** on a GdkToplevel that never gets a surface → first tap hangs. GTK loop stays idle in poll.

ℹ️ C5 is **why** the second activity is refused. It is not the user-visible bug. The bug is “About never maps on first tap.”

✔️ Settings works because it is `Adw.Dialog` on the **existing** toplevel.

🚫 Revert `singleTask` — that brings C5 reboot-feel back. 🚫 Paper over with a no-op About on Android.

---

## Proposed fix

🔷 First tap (and every later tap): `Adw.AboutDialog` overlays the **existing** chat toplevel. No second activity, so `singleTask` is irrelevant. Same path as Settings. Shared `ollmapp/About.vala` (desktop + Android). Drop `default_width` / `transient_for` (dialog API has neither).

ℹ️ Shared file — user approved apply 2026-08-31.

### 1. `ollmapp/About.vala` — `show_about_dialog()`: window → dialog overlay

**Why:** First tap must not start a second GdkToplevel. Overlay on the chat window instead.

**Where:** class doc first line; method doc under `show_about_dialog()`; ctor line; drop `default_width`; replace `transient_for` + `present()`.

**Depends on:** none.

##### Part 1 — Class doc

#### Remove
```vala
	 * About button widget that shows an Adw.AboutWindow when clicked.
```

#### Replace with
```vala
	 * About button widget that shows an Adw.AboutDialog when clicked.
```

##### Part 2 — Method doc

#### Remove
```vala
		 * Creates a fresh {@link Adw.AboutWindow} each time so Android can
		 * safely re-present after the previous window was closed.
```

#### Replace with
```vala
		 * Uses {@link Adw.AboutDialog} so Android overlays the existing
		 * toplevel instead of opening a second activity.
```

##### Part 3 — Ctor type

#### Remove
```vala
			var about_window = new Adw.AboutWindow() {
```

#### Replace with
```vala
			var about = new Adw.AboutDialog() {
```

##### Part 4 — Drop `default_width` (dialog has no window width)

#### Remove
```vala
				copyright = "Copyright © 2026 Alan Knowles",
				default_width = 600,  // Set width ~30% wider than default
				comments = """<b>OLLMchat</b> is a work-in-progress AI application for 
```

#### Replace with
```vala
				copyright = "Copyright © 2026 Alan Knowles",
				comments = """<b>OLLMchat</b> is a work-in-progress AI application for 
```

##### Part 5 — Present on this button; drop `transient_for`

#### Remove
```vala
			var active_window = this.get_root() as Gtk.Window;
			if (active_window != null) {
				about_window.set_transient_for(active_window);
			}
			
			about_window.present();
```

#### Replace with
```vala
			about.present(this);
```

---

## Attempts / changelog

- ✔️ 2026-08-31 — Device events + `dumpsys`: **first tap** → self `MAIN` `wm_new_intent`; `singleTask` reuses the chat activity (no About surface); GTK idle in poll.
- 🚫 Do not revert C5 `singleTask`.
- ✔️ 2026-08-31 — Applied Parts 1–5 in `ollmapp/About.vala` (`Adw.AboutDialog` + `present(this)`).

## Next

- ✅ User closed 2026-09-02.
