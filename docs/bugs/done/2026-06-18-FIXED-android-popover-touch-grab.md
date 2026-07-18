# Android — popover touch grab blocks chat-bar toggles (tools + model dropdown)

**Status:** FIXED (2026-07-18) — workaround: raise model/tools pulldown so near-edge dismiss works.  
**Opened:** 2026-06-18  
**Platform:** Android chat POC (`org.roojs.ollmchat.androidpoc`)  
**GTK fork:** `/home/alan/git/gtk` (`main` — IME/popup work only; no GDK TLS; shipped via `android-bugs.patch`)  
**Related:** [`docs/plans/done/9.0-DONE-android-poc-summary.md`](../plans/done/9.0-DONE-android-poc-summary.md)

### Resolution

🔷 Raised the chat-bar model/tools pulldown slightly so the near-edge grab band no longer blocks close/toggle. GTK Android `input_region` / grab gap left unpatched; reopen if the workaround regresses.

---

## Problem

On Android, the **tools** popover (`Gtk.MenuButton` + `Gtk.Popover`) and **model** list (`Gtk.DropDown`, internal `Gtk.Popover`) misbehave only when the tap is **close to** the popover — not when it is far away.

### Three distance zones (user-confirmed behaviour)

| Zone | What you tap | What happens |
|------|----------------|--------------|
| **Far** — well outside the popover | Empty chat area, Send, input field, etc. | **Works.** Autohide dismisses the popover as expected. |
| **On** — visible bubble / list content | Inside the popover | **Works.** Normal interaction (checkboxes, list rows, etc.). |
| **Near** — narrow band around the bubble | Just outside the visible edge: anchor button again, sibling model/tools button, shadow/padding around the bubble | **Broken.** Popover stays open; button toggle and outside-dismiss do not fire. |

The failure is **proximity-based**: GTK/Android treat taps differently depending on how close they are to the popup **surface** rectangle vs the popover **content** (`input_region`). Far-away taps never hit the popup `View`, so they reach the toplevel and autohide works. Near-edge taps land inside the popup view’s layout bounds (but often outside the real `input_region`) and get stuck there.

**Expected (near zone):** Tapping the anchor button toggles closed; tapping the adjacent chat-bar control dismisses the open popover and activates the other control.

**Actual (near zone):** Touches are delivered to the popup surface and neither dismiss the popover nor reach the buttons underneath.

---

## Reproduction (manual)

1. Build/install Android chat POC.
2. Open a session with models loaded so the chat bar shows **model dropdown** + **tools** button (`ChatBar`).
3. Tap **tools** — popover opens.
4. **Control — far tap:** tap Send or the chat input — popover should dismiss (confirm this works).
5. Re-open tools popover. Tap **tools** again or **model** — taps in the narrow band beside/under the bubble edge.
6. **Fail case:** popover stays open; sibling button does not toggle.
7. Re-open. Tap clearly outside the popover (step 4) — should dismiss again.

Desktop (same `ChatBar.vala`) does not exhibit the near-zone failure — Android/GTK-backend specific.

---

## App implementation (not the root cause)

Both widgets are standard GTK 4 controls in shared `libollmchatgtk/ChatBar.vala`:

| Control | GTK widget | Popover wiring |
|---------|------------|----------------|
| Model list | `Gtk.DropDown` | Internal popover; `button_toggled` → `gtk_popover_popup` / `popdown` ([`gtkdropdown.c`](../../../git/gtk/gtk/gtkdropdown.c)) |
| Tools list | `Gtk.MenuButton` + `Gtk.Popover` | `tools_menu_button.popover = popover`; toggle → popup/popdown ([`gtkmenubutton.c`](../../../git/gtk/gtk/gtkmenubutton.c)) |

Chat bar layout: horizontal box, `spacing: 5`, order is model dropdown → tools button → spacer → Send (`ChatBar.vala`).

No custom popover positioning or touch handling in app code — behaviour comes from GTK + Android GDK backend.

---

## GTK stack (where the bug likely lives)

### 1. Popover grab + autohide

When a `Gtk.Popover` maps with `autohide=TRUE` (default):

- `gtk_grab_add(popover)` — GTK-level modal grab ([`gtkpopover.c`](../../../git/gtk/gtk/gtkpopover.c) ~1246).
- `gdk_seat_grab(seat, popup_surface)` on Android when `surface->autohide` ([`gdkandroidsurface.c`](../../../git/gtk/gdk/android/gdkandroidsurface.c) ~289–293).

Outside-click dismiss and anchor-button toggle both depend on the press reaching the correct widget/surface.

### 2. Android popup is a full rectangular `View`

Popups are native sibling views positioned over the toplevel ([`gdkandroidpopup.c`](../../../git/gtk/gdk/android/gdkandroidpopup.c), `ToplevelView.pushPopup` in [`ToplevelActivity.java`](../../../git/gtk/gdk/android/glue/java/org/gtk/android/ToplevelActivity.java)).

The view’s **layout width/height** come from `gdk_surface_layout_popup_helper()` (includes shadow margins from popup layout). Z-order: popups are `addView`’d on top of the toplevel surface.

### 3. `input_region` is set but ignored while grabbed — **prime suspect**

GTK sets a Cairo `input_region` on the popover surface to match the visible bubble (excluding CSS shadow padding) in `gtk_popover_update_shape()` ([`gtkpopover.c`](../../../git/gtk/gtk/gtkpopover.c) ~1516–1531). That region is pushed to Java via `gdk_android_surface_set_input_region()`.

In `ToplevelActivity.java`, `motionEventProxy()`:

```java
if (this != ToplevelView.this.grabbed) {
    if (this.inputRegion != null &&
        Arrays.stream(this.inputRegion)
            .noneMatch(region -> region.contains(event.getX(), event.getY())))
        return false;
}
// grabbed surfaces get all events, regardless of input region
```

**When the popup has seat grab, touches inside the view’s bounding rectangle but outside `input_region` are still forwarded to GDK** instead of falling through to the toplevel. That matches the **near zone** only:

- **Far zone:** tap is outside the popup `View` rect → Android delivers to toplevel → autohide dismiss works.
- **Near zone:** tap is inside the popup `View` rect but outside `input_region` (shadow/margin band, or over an anchor button the bubble sits above) → grabbed surface eats the event → no dismiss, no button toggle.
- **On zone:** tap is inside `input_region` → popover handles it normally.

macOS GDK already drops presses outside `input_region` ([`gdkmacosdisplay-translate.c`](../../../git/gtk/gdk/macos/gdkmacosdisplay-translate.c) ~246–253). Android does not when grabbed.

### 4. Chat-bar geometry puts anchor buttons in the near zone

Model dropdown and tools button are adjacent (5 px spacing). A popover anchored above either control extends its **popup view bounds** over the sibling button by roughly one shadow-margin width. Those buttons sit in the near zone — close enough to the surface rect, not far enough for autohide-via-toplevel.

### 5. Android display flags

`gdk_display_set_shadow_width(display, FALSE)` ([`gdkandroiddisplay.c`](../../../git/gtk/gdk/android/gdkandroiddisplay.c) ~331) — compositor does not draw shadows, but popup layout may still reserve shadow space in surface geometry.

---

## Conclusions (current)

| Ruled in | Ruled out |
|----------|-----------|
| **Near-zone** hits: inside popup view rect, outside `input_region` | Autohide broken globally (far taps dismiss fine) |
| `input_region` bypass on grabbed surfaces in `motionEventProxy` | App-specific popover code in `ChatBar` (uses stock GTK widgets) |
| Popup view rect larger than visible bubble; anchor buttons in the margin band | Desktop GTK popover logic (works there) |

**Root cause (hypothesis):** The popup Android `View` is laid out to a rectangle **larger** than the popover’s `input_region` (shadow/padding from popup layout). While grabbed, Java forwards every touch in that rectangle to GDK, ignoring `input_region`. Touches in the extra margin — including on anchor/sibling buttons just beside the bubble — neither dismiss the popover nor reach the widgets below. Touches far outside the rectangle still hit the toplevel and autohide works.

---

## Proposed fixes (need approval before coding)

### A. GTK Android patch (preferred — fixes all popovers)

**File:** `gdk/android/glue/java/org/gtk/android/ToplevelActivity.java` — `motionEventProxy()`

Always honour `inputRegion` for **press/down** events, even when `this == grabbed`. Optionally still allow move/release outside region during an active grab (mirror macOS: ignore press outside, allow release).

Alternative/additional: in `gdkandroidevents.c`, drop touch/button press events when coordinates fall outside `surface->input_region` (C-side, consistent with macOS).

**Verify:** tools toggle, model dropdown toggle, tap-between-buttons, tap outside bubble on device.

### B. GTK Android patch — shrink popup view hit target

After `set_input_region`, set the Android view non-clickable outside region (e.g. custom `onTouchEvent` dispatch to parent, or `setBackground` + `touchDelegate`). More invasive; A is simpler.

### C. App workaround (narrow, if GTK patch delayed)

Android-only chat bar changes (needs explicit approval per POC golden rule):

- Increase spacing between model dropdown and tools button.
- Replace `Gtk.MenuButton` / `Gtk.DropDown` popovers with a custom overlay that does not use GDK popup surfaces (large effort).
- Force popover positions that do not overlap siblings (fragile; does not fix edge padding).

**Recommendation:** pursue **A** in the GTK fork (`/home/alan/git/gtk`, `main` → refresh `android-bugs.patch`), then rebuild the Android APK wrap. App workarounds are poor substitutes.

---

## Attempts / changelog

| Date | Change | Result |
|------|--------|--------|
| 2026-06-18 | Opened log; traced `ChatBar` → GTK `MenuButton`/`DropDown`/`Popover` → Android `ToplevelActivity.motionEventProxy` | Root cause hypothesised; no code changes yet |
| 2026-06-18 | User clarification: far-away taps dismiss correctly; failure is **near-edge / proximity** only | Refines model to popup-view rect vs `input_region` margin band |
| 2026-06-18 | Added `AndroidTouchDebug` (`--touch-debug` / `files/touch-debug`) for toplevel touch HUD + logcat | Popup-surface taps still invisible to app layer |

---

## GTK upstream — is this a known issue?

**Short answer: not as a filed, Android-specific bug.** The exact failure mode (grabbed popup `Surface` ignoring `input_region`, blocking anchor-button toggle) does not appear in GNOME GitLab under an `android` label or in search-accessible issue titles. As of 2026-06-18, [GTK issues labeled `android`](https://gitlab.gnome.org/GNOME/gtk/-/issues?label_name%5B%5D=android) return **0 items**.

### Closest upstream references

| Reference | Relevance |
|-----------|-----------|
| [MR !7555 — Android backend](https://gitlab.gnome.org/GNOME/gtk/-/merge_requests/7555) (merged Aug 2024) | Author’s “Current Issues” list: broken mouse/touch (“button sticked down”), `GtkPopoverMenu` relayout spam, `Gtk.FontPicker` “select” not closing dialog, popup measure/layout “still incorrect”. **No mention of `input_region` or shadow click-through.** Thread discusses `Gtk.Popover` arrow drift on reposition — related popup geometry, not this grab bug. |
| [gtk#4529](https://gitlab.gnome.org/GNOME/gtk/-/issues/4529) — popover won’t close after child popover | Desktop (Wayland/X11). Notes popover “intercepts clicks outside” in broken state. Different root cause (device grab stack), but similar symptom. |
| [gtk#2446](https://gitlab.gnome.org/GNOME/gtk/-/issues/2446) | Led to `gtk_grab_add` on autohide popovers (2020). |
| [gtk#7414](https://gitlab.gnome.org/GNOME/gtk/-/issues/7414) | Active state stuck when releasing outside popup but inside window (Wayland, 2025). |
| Commit `f38a9df` (2021) — “popover: Don’t include shadow border in input region” | **Desktop fix for the same UX goal** Jonas Ådahl: exclude shadow so you can “click through” to the button that opened the popover. macOS backend was later updated to honour `input_region` in tracking areas and to drop presses outside the region (`gdkmacosdisplay-translate.c`). **Android never got the equivalent Java-side enforcement when grabbed.** |

### Conclusion

This looks like an **unfiled gap in the experimental Android backend**: GTK sets `input_region` correctly for popovers, but `ToplevelActivity.motionEventProxy()` deliberately bypasses it for seat-grabbed surfaces. That conflicts with the shadow click-through behaviour desktop backends have had since 2021.

**Recommendation:** file a new issue on [GNOME/gtk](https://gitlab.gnome.org/GNOME/gtk/-/issues/new) (label `android`, component `Backend: Android` if available) with a minimal repro (`Gtk.MenuButton` + adjacent `Gtk.DropDown` in a horizontal box) and link to the macOS precedent. Until then, a local patch in `/home/alan/git/gtk` (`main`, then `android-bugs.patch`) is appropriate.

---

## Open questions

1. Measure the near-zone width on device (shadow extents from popover CSS vs popup `popup_bounds` in logcat) — is it ~10–20 px or larger?
2. Does the near zone reproduce with only one control (model dropdown alone), or only when sibling buttons sit under the margin?
3. After fix A, do we need `gtk_widget_set_limit_events` on popover (GTK 4.18+) for correct cross-surface dismiss?
4. Should we file upstream and/or cherry-pick the Java/C input-region fix to Florian’s Android GDK branch?

---

## Debug ideas (if reproducing with logs)

### App touch HUD (`--touch-debug` or `files/touch-debug`)

Android-only (`AndroidTouchDebug.vala`). Attaches capture + bubble
`EventControllerLegacy` on the main window and shows the last toplevel-surface
touch on a HUD label.

**Limitation:** touches that GDK delivers to a **popup native surface** (open
`Gtk.Popover` / `Gtk.DropDown` list) do **not** appear here — that is exactly
the gap we are investigating. Compare:

- **No log line / HUD frozen** when tapping near the popover edge → event went
  to the popup layer (or nowhere on the toplevel tree).
- **HUD updates with `pick=GtkMenuButton` or `GtkDropDown`** on far taps →
  toplevel received the event.

**Enable on device** (argv is usually empty on Android):

```bash
PKG=org.roojs.ollmchat.androidpoc
adb shell touch /storage/emulated/0/Android/data/$PKG/files/touch-debug
adb shell am force-stop $PKG
adb logcat -c
adb shell am start -n $PKG/org.gtk.android.ToplevelActivity
adb logcat -s OLLMchat GLib-GIO | grep touch
```

Disable: `adb shell rm …/files/touch-debug`. Host/desktop `android_poc` build
can use `--touch-debug` on the command line instead.

Logcat filter (GTK traces):

```bash
# Filter GTK Android popup/grab traces while reproducing
adb logcat -c
# … reproduce on device …
adb logcat -d | grep -iE 'Android\.Popup|Grabbing surface|input_region|motionEvent'
```

Temporarily add `GLib.debug()` in a local GTK build around `gdk_android_surface_set_input_region` and `gdk_android_events_handle_motion_event` to log coords vs `cairo_region_contains_point`.
