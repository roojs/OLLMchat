# Editor long-hold toast repeats on every tap

**Status:** ✅ user closed 2026-10-09 — per-tap toast removed. The hint shows once when Text view is mapped, and once when a document opens while the editor is already mapped. Phone check not run.

**Related:** ℹ️ `liboccoder/SourceView.vala` (Android `phone_tap` / `phone_toast`)

## Problem

- **🔷** Phone only. Desktop has no long-hold toast.
- **🔷** The phone text editor toasts “Long hold to start editing” on every tap while the file is in view mode.
- **🔷** That hint may show **once** when the document opens.
- **🔷** Going from chat or the browser into Text view resets the rule, so the hint may show **once** after that flip.
- **🔷** Further taps on that same visit must not toast.

## Evidence

- **ℹ️** `phone_tap.released` adds `Long hold to start editing` (timeout 3) on every release while the view is not editable and no diff or delete is active.
- **ℹ️** A second toast, `View mode. Long hold to edit.`, is added when a tap outside the editor drops edit mode. That path is once per exit, not once per click.

## Block rule

Show the view-mode hint only at the start of a visit. Block it for the rest of that visit.

- **🔷** **Show** when `open_file` puts the phone into view mode for a document.
- **🔷** **Reset and show once** when the phone goes from chat into Text view, or from the browser into Text view.
- **🔷** **Block** every later tap on the source view while that Text-view visit stays open.
- **🔷** Another flip from chat or the browser into Text view starts a new visit and may show the hint once more.
- **🚫** Desktop. This toast and this reset exist only on the phone.
- **🚫** Do not toast on each click, scroll, or repeat tap during the visit.

## Proposed changes

Taps never toast. The hint is shown at the two visit starts, inline. No new method.

On the phone, chat hides the pane and the browser swaps the stack child. Both unmap the editor. `SourceView.map` is the flip back into Text view.

- **🚫** Do not change the leave-edit toast `View mode. Long hold to edit.` It already fires once per exit.

### 1. `liboccoder/SourceView.vala` — `phone_tap.released`: stop the per-tap toast

**Why:** This handler adds `Long hold to start editing` on every view-mode tap. That is the repeat.

**Where:** Android `construct` block, the `this.phone_tap.released.connect` handler. Keep `phone_tap` and its `begin` handler so view-mode taps stay captured.

**Depends on:** none.

#### Remove

```vala
			this.phone_tap.released.connect((n_press, x, y) => {
				if (this.source_view.editable || this.diff_active) {
					return;
				}
				if (this.current_file != null && this.current_file.delete_id > 0) {
					return;
				}
				this.phone_toast.add_toast(new Adw.Toast("Long hold to start editing") {
					timeout = 3
				});
			});
```

### 2. `liboccoder/SourceView.vala` — `map`: once after chat or browser

**Why:** Returning from chat or the browser maps the editor again. That resets the visit and shows the hint once. A later tap does not.

**Where:** Android `construct` block, after `this.source_view.add_controller(this.phone_tap);`, before the existing one-shot `this.map.connect` that installs the outside-tap watcher.

**Depends on:** §1. The tap path must already be gone.

#### Add

After `this.source_view.add_controller(this.phone_tap);`. Shows the hint once each time Text view is mapped with a document in view mode.

```vala
			this.map.connect(() => {
				if (this.source_view.editable || this.diff_active) {
					return;
				}
				if (this.current_file == null || this.current_file.delete_id > 0) {
					return;
				}
				this.phone_toast.add_toast(new Adw.Toast("Long hold to start editing") {
					timeout = 3
				});
			});
```

### 3. `liboccoder/SourceView.vala` — `open_file`: once when the document opens on screen

**Why:** Opening a document while Text view is already showing does not map the editor again. The hint still has to show once for that open.

**Where:** `open_file`, inside the Android view-mode block, after the `has_focus` clear and before `#else`.

**Depends on:** §1.

#### Add

After the `has_focus` block. Skip when the editor is not mapped, so a restore that opens the file before Text view is shown does not toast twice with §2.

```vala
				if (this.get_mapped()) {
					this.phone_toast.add_toast(new Adw.Toast("Long hold to start editing") {
						timeout = 3
					});
				}
```

## Attempts / changelog

- **✔️** `liboccoder/SourceView.vala`: removed the per-tap toast, show the hint on `map` into Text view, and show it from `open_file` only when the editor is already mapped.
- **✅** 2026-10-09 — User closed the log. Phone check not run.

## Next

- **✅** Closed.
