# AdwViewStack: Child name '' not found when opening Settings

> Pointer: `docs/bug-fix-process.md` (emoji). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval

**Started:** 2026-08-05

---

## Problem

🔷 Opening Settings logs:

```text
G_LOG_LEVEL_WARNING : Adwaita : Child name '' not found in AdwViewStack
```

Often right after `ProjectManager.load_projects_from_db` starts (Settings
`show_dialog` kicks that off without awaiting it).

---

## Evidence

- ✔️ Adwaita only warns from `adw_view_stack_set_visible_child_name` when
  `name != NULL` and no page matches (`''` is not NULL).
- ✔️ Desktop Settings gear:

```167:169:ollmapp/Window.vala
			this.settings_button.clicked.connect(() => {
				this.settings_dialog.show_dialog.begin("");
			});
```

- ✔️ Desktop `show_dialog` treats any non-null as a page switch:

```238:241:ollmapp/SettingsDialog/MainDialog.vala
			// Switch to specified page if provided
			if (page_name != null) {
				this.view_stack.set_visible_child_name(page_name);
			}
```

- ✔️ Timing: `load_projects()` is started (not yielded), then
  `set_visible_child_name(page_name)` runs — matches log order
  (RPC start → warning immediately).
- ✔️ Android already correct: `if (page_name != "")` and
  `show_dialog.begin()` with no empty string.

---

## Root cause

✔️ Gear passes `""`; desktop null-check does not treat empty as “default tab”,
so Adwaita looks up a child named `''`.

---

## Proposed fix

🔷 Match Android: empty means leave the current/default tab; call site omit
the page arg.

#### Replace with — `ollmapp/Window.vala` (settings button clicked)

```vala
			this.settings_button.clicked.connect(() => {
				this.settings_dialog.show_dialog.begin();
			});
```

#### Replace with — `ollmapp/SettingsDialog/MainDialog.vala` (page switch)

```vala
			if (page_name != null && page_name != "") {
				this.view_stack.set_visible_child_name(page_name);
			}
```

---

## Attempts / changelog

- ✔️ Correlated warning with Settings `show_dialog("")` + fire-and-forget
  `load_projects`.
- ⏳ Await apply.

## Next

- ⏳ 🔷 Apply both Replace fences; reopen Settings and confirm warning gone
