# File Server Port row is not editable

**Status:** ✔️ Port copies Tools Engine ID (`Rows.String`); LLM Name/URL same wiring  
**Hit:** 2026-09-19 — Connections → File Server → Port  
**Component:** `ollmapp/SettingsDialog/FileServerRow.vala`

---

## Problem

🔷 Port cannot be edited at all. It is not sensitive.

**Expected:** click Port (or the entry) and type a listen port.

**Actual:** the field does not take input.

---

## Evidence

- ℹ️ Working LLM connection Name/URL: `ConnectionRow` suffix `Gtk.Entry` on an `Adw.ActionRow` with **default** `activatable` (not false). No `width_chars`.
- ℹ️ Working settings strings: `Rows/String.vala` does `add_suffix(entry)` then `set_activatable_widget(entry)`.
- ℹ️ File Server Port: `activatable = false` plus `width_chars = 6`. Those came from `docs/bugs/2026-09-19-fileserver-port-placeholder.md` (meant to let the suffix receive clicks).
- 💩 `activatable = false` on `Gtk.ListBoxRow` / `Adw.ActionRow` stops row activation. Clicks on the title do nothing. The real entry is a 6-character suffix, so it never gets focus. Proxy/systemd were not given `activatable = false` and still use suffix switches.

---

## Root cause

✔️ Port (and Host) were marked non-activatable, unlike every working suffix entry in this dialog. That is the opposite of `Rows/String.vala`.

---

## Proposed fix

🔷 Same pattern as `Rows/String.vala` / `Rows/Connection.vala`: drop `activatable = false`, `set_activatable_widget` on the entry and host dropdown, drop `width_chars = 6`. Do **not** fill Port with `8443`.

### `ollmapp/SettingsDialog/FileServerRow.vala` constructor

#### Remove

```vala
			this.host_row = new Adw.ActionRow() {
				title = "Host",
				activatable = false,
				visible = false
			};
			this.host_row.add_suffix(this.host_dropdown);
			this.expander.add_row(this.host_row);

			this.port_entry = new Gtk.Entry() {
				text = "",
				placeholder_text = "8443",
				width_chars = 6,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.port_row = new Adw.ActionRow() {
				title = "Port",
				activatable = false,
				visible = false
			};
			this.port_row.add_suffix(this.port_entry);
			this.expander.add_row(this.port_row);
```

#### Replace with

```vala
			this.host_row = new Adw.ActionRow() {
				title = "Host",
				visible = false
			};
			this.host_row.add_suffix(this.host_dropdown);
			this.host_row.set_activatable_widget(this.host_dropdown);
			this.expander.add_row(this.host_row);

			this.port_entry = new Gtk.Entry() {
				text = "",
				placeholder_text = "8443",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.port_row = new Adw.ActionRow() {
				title = "Port",
				visible = false
			};
			this.port_row.add_suffix(this.port_entry);
			this.port_row.set_activatable_widget(this.port_entry);
			this.expander.add_row(this.port_row);
```

---

## Attempts / changelog

- ✔️ `activatable = false` on Host/Port (placeholder bug log) — did **not** make Port editable.
- ✔️ `set_activatable_widget` like `Rows/String.vala` — user: Port **gone back** to not sensitive. Those String rows are not inside `Adw.ExpanderRow`.
- 💩 Expander suffix entries that work (`ConnectionRow` Name/URL) only `add_suffix`. They do **not** call `set_activatable_widget`. Activating an Entry is Enter, not focus; the row eats the click.
- 💩 Empty Port has no text, so the suffix is a tiny target. `hexpand = true` widens it. Host DropDown keeps `set_activatable_widget` (same as `Rows/Connection.vala`).
- ✔️ 2026-09-20: Port is `add_suffix` only + `hexpand`. Compiles.
- 🔷 2026-09-20: user pasted gibberish into Port; subtitle still said HTTPS. `hexpand` does not size an Adw suffix. `FileConnectionAdd` uses `width_request`. HTTPS subtitle used non-empty `https`, not `int.try_parse` like `Https.listen`.
- ✔️ 2026-09-20: `width_request = 96`, row `activated` → `grab_focus`, digits-only `insert_text` (`^[0-9]*$`), `max_length = 5`. Apply/subtitle require port 1–65535.
- 🔷 2026-09-20: suffix `Gtk.Entry` inside `Adw.ExpanderRow` never became a click target (user: five attempts, zero effect). `/usr/bin/ollmchat` is what they run. `activatable = true` on the ActionRow steals clicks from a suffix. Replace with `Adw.EntryRow` (the row is the editor).
- 🔷 2026-09-20: user: steppers work, cannot type, 1–5 too low for a user service, should say Invalid. Then: Tools Engine ID works; LLM connection fields may never have been editable.

✔️ Engine ID is `Rows.String` inside `Rows.Tool : Adw.ExpanderRow`: `Gtk.Entry { width_chars = 30 }`, `add_suffix`, `set_activatable_widget`. No `can_focus = false` on that expander. File Server / LLM `ConnectionRow` used `can_focus = false` + `focus_on_click = false` and never copied `width_chars = 30` / `set_activatable_widget`.

### Copy Engine ID onto Port and LLM Name/URL/API Key

#### Port (`FileServerRow.vala`)

`Gtk.Entry` like `Rows.String` (`width_chars = 30`, `set_activatable_widget`). Drop expander `can_focus`/`focus_on_click` false. Digits-only, `max_length = 5`. Blur: empty = off; 1024–65535 writes `https`; else row subtitle `Invalid`, CSS `error`, do not write. HTTPS status requires `n >= 1024`.

#### LLM (`ConnectionRow.vala`)

Same `width_chars = 30` + `set_activatable_widget` on Name, URL, API Key. Drop expander `can_focus`/`focus_on_click` false.

### `ollmapp/SettingsDialog/FileServerRow.vala` constructor — drop EntryRow

#### Remove

`Adw.EntryRow` Port row, `insert_text` digits filter, `port_row.text`.

#### Replace with

`Gtk.SpinButton.with_range(0, 65535, 1)` suffix on `Adw.ActionRow`, `width_request = 150` like `Rows/Int`, `set_activatable_widget` like Host. 0 = no HTTPS. Apply still on focus leave (not every stepper click).

### `ollmapp/SettingsDialog/FileServerRow.vala` constructor — Port suffix

#### Remove

```vala
			this.port_entry = new Gtk.Entry() {
				text = "",
				placeholder_text = "8443",
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.port_row = new Adw.ActionRow() {
				title = "Port",
				visible = false
			};
			this.port_row.add_suffix(this.port_entry);
			this.port_row.set_activatable_widget(this.port_entry);
			this.expander.add_row(this.port_row);
```

#### Replace with

Same as `ConnectionRow` Name/URL: suffix Entry, no activatable widget. `hexpand` so an empty Port is still a click target.

```vala
			this.port_entry = new Gtk.Entry() {
				text = "",
				placeholder_text = "8443",
				hexpand = true,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			this.port_row = new Adw.ActionRow() {
				title = "Port",
				visible = false
			};
			this.port_row.add_suffix(this.port_entry);
			this.expander.add_row(this.port_row);
```

- 🔷 2026-09-20: Port field need not be Engine ID wide; size for 65535 (`width_chars = 5`).

- 🔷 User: expand File Server, click Port, type a number.
