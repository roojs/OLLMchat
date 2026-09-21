# AdwViewStack: Child name '' not found when opening Settings

**Status:** ✔️ applied; await user smoke **✅**

**Started:** 2026-09-21

**Reporter:** Alan

**Component:** `ollmapp/Window.vala` (settings gear)

**Process:** Follow **`docs/bug-fix-process.md`**.

**Related:**

- ℹ️ [`2026-08-05-CLOSED-adw-viewstack-empty-child-name.md`](done/2026-08-05-CLOSED-adw-viewstack-empty-child-name.md) — same diagnosis; closed unapplied because the warning was not seen then

---

## Problem

🔷 Opening Settings logs:

```text
G_LOG_LEVEL_WARNING : Adwaita : Child name '' not found in AdwViewStack
```

---

## Root cause

✔️ Gear called `show_dialog.begin("")`. Desktop `show_dialog(string? page_name = null)` treats any non-null as a page switch, so Adwaita looks up a child named `''`.

✔️ Android already omits the arg (`show_dialog.begin()`).

🚫 Empty-string guard on `set_visible_child_name` — that would hide a bad caller. Fix the call site.

---

## Proposed fix

🔷 Omit the empty page arg so the default (null) leaves the current tab.

#### Replace with — `ollmapp/Window.vala` (settings button clicked)

```vala
			this.settings_button.clicked.connect(() => {
				this.settings_dialog.show_dialog.begin();
			});
```

---

## Attempts / changelog

- ✔️ 2026-09-21 — Applied call-site fix (same hunk as the August proposal).

## Next

- ⏳ 🔷 User smoke: open Settings from the gear; warning gone
