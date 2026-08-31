# Android Settings tabs: Connections first, want Models first

**Status:** ⏳ user-stated; fix proposed — await apply approval

**Started:** 2026-08-31

**Package:** `org.roojs.ollmchat.androidpoc`

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Android shell: `ollmapp/android/MainDialog.vala`
- ℹ️ Desktop (already Models first): `ollmapp/SettingsDialog/MainDialog.vala`

---

## Problem

🔷 Android Settings tab order is the wrong way around. **Models first.** Do not copy a Connections-first layout.

**Actual:** Connections → Models → Tools (`add_titled` order in the Android dialog).

**Desktop (for contrast):** Models → Connections → …

---

## Evidence

- ✔️ `ollmapp/android/MainDialog.vala` ctor adds Connections, then Models, then Tools.
- ✔️ First `ViewStack` child is the default tab.

---

## Proposed fix

🔷 Android-only: add Models before Connections. Tools stays last.

### 1. `ollmapp/android/MainDialog.vala` — ctor: Models tab before Connections

**Why:** Default / left tab is Models. **Where:** ctor, the Connections `add_titled` block then the Models block (Tools unchanged). **Depends on:** none.

##### Part 1 — Swap the two `add_titled` blocks

#### Remove
```vala
			this.connections_page = new ConnectionsPage(this);
			this.view_stack.add_titled(
				this.connections_page,
				this.connections_page.page_name,
				this.connections_page.page_title
			);
			this.view_stack.get_page(this.connections_page).icon_name = this.connections_page.page_icon;
			this.action_bar_area.append(this.connections_page.action_widget);
			this.connections_page.action_widget.visible = false;

			this.models_page = new ModelsPage(this);
			this.view_stack.add_titled(
				this.models_page,
				this.models_page.page_name,
				this.models_page.page_title
			);
			this.view_stack.get_page(this.models_page).icon_name = this.models_page.page_icon;
			this.action_bar_area.append(this.models_page.action_widget);
			this.models_page.action_widget.visible = false;
```

#### Replace with
```vala
			this.models_page = new ModelsPage(this);
			this.view_stack.add_titled(
				this.models_page,
				this.models_page.page_name,
				this.models_page.page_title
			);
			this.view_stack.get_page(this.models_page).icon_name = this.models_page.page_icon;
			this.action_bar_area.append(this.models_page.action_widget);
			this.models_page.action_widget.visible = false;

			this.connections_page = new ConnectionsPage(this);
			this.view_stack.add_titled(
				this.connections_page,
				this.connections_page.page_name,
				this.connections_page.page_title
			);
			this.view_stack.get_page(this.connections_page).icon_name = this.connections_page.page_icon;
			this.action_bar_area.append(this.connections_page.action_widget);
			this.connections_page.action_widget.visible = false;
```

---

## Attempts / changelog

- ✔️ 2026-08-31 — User: Models first; Android currently Connections first.

## Next

⏳ 🔷 Approve Part 1, then rebuild APK and confirm Settings opens on Models.
