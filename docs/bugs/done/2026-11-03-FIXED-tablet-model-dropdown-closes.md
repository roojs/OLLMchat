# Tablet model dropdown closes as soon as it opens

**Status:** ✅ 2026-11-03. The model menu stays open on the tablet. Width stays the list width.

## Problem

- 🔷 On the tablet emulator, the model pull-down at the bottom of the chat opens and then disappears. It never stays open.
- 🔷 A mouse click on the emulator does this. The header agent picker stays open.

## Evidence

- ℹ️ Emulator stdout `/tmp/emu-tablet.log` is host noise: `scroll event from unregistered device 18`. That is the emulator's Qt input path, not the menu.
- ✔️ App logcat, `emulator-5556`, `org.roojs.ollmchat.androidpoc` pid 13370, 2026-11-03 08:43:35–08:43:41. Same popup `0x706302b7c850` on every click:
  - `CLIP-POP` `parent=1280x732` `popup_bounds=305x452@(-13,252)` `req=305x452`
  - surface maps, grab, `OnLayoutSurface` `610x904 @ 2.0`
  - `AndroidSurface: hide` `(1 0)` about 70ms later (one slower frame was 237ms)
- ✔️ Agent picker, 08:44:32, different popup `0x706302cbca90`, `204x179@(538,19)`. Hide is 1.2s later, when it was dismissed on purpose.
- ✔️ `GtkPopover` pops itself down when a later layout size is smaller than the widget minimum (`gtk_popover_native_layout` → `is_acceptable_size`).
- ✔️ `ChatBar.init_models` waits until `show`, then an idle sets the popover minimum to `root width - 32`. On this window that is about 1248. The Android surface is already mapped at 305. The next layout still has width 305, the minimum is 1248, and the popover hides. The agent dropdown never sets that minimum.
- 🚫 Not the opening click's release. The toggle opens on click, and the hide is a later layout. The agent picker gets the same emulator mouse and stays up.

## Root cause

- ✔️ The full-width size request runs after the popover is already mapped. Android reports the surface size asynchronously, so GTK checks the old 305px surface against the new minimum and closes the menu.

## Proposed fix

- 🔷 The menu stays open.
- 💩 On Android, do not raise the popover minimum after `show`. Desktop still does, because that resize is applied before the size check. The tablet list stays at its content width (about 305).

#### Replace with

```vala
				popup.show.connect(() => {
					var root = this.get_root();
					if (root == null) {
						return;
					}
					/* Android maps the surface after present. Raising the
					   minimum here then fails the popover size check
					   and the menu closes. */
					if (root.get_display().get_type().name() == "GdkAndroidDisplay") {
						return;
					}
					var width = root.get_width() - 32;
					Idle.add(() => {
						popup.set_size_request(width, -1);
						return false;
					});
				});
```

## Attempts / changelog

- ✔️ 2026-11-03: read `/tmp/emu-tablet.log` and pid 13370 logcat. No product change in that pass.
- 🚫 Setting the width from the toggle `notify["active"]`. That notify runs after `toggled`, so the popover is already mapped. Installed once; `req` stayed `305x452` and the menu stayed open only because the idle was gone.
- ✔️ `libollmchatgtk/ChatBar.vala`: skip the post-show size request when the display is `GdkAndroidDisplay`.
- ✔️ 2026-11-03: the Android skip is `#if ANDROID` then `return` inside the show handler. The width request stays on the main path.

## Next

- ✔️ 2026-11-03 08:56, pid 20029, tap `(250, 1490)`. Five `CLIP-POP` lines, `req=305x452`, no `AndroidSurface: hide`. Screenshot still shows the model list a second later (`deepseek-r1:1.5b` selected, rows from `beam:cloud` through `gpt-oss:120b`).
- ✔️ 2026-11-03 09:01, pid 20434, same tap after the Android skip. Five `CLIP-POP` lines, `req=305x452`, no hide. The list is still on screen.
- ✅ 2026-11-03 — user confirmed this is fixed.
