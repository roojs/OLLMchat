# ActivityBanner: NULL action_button on construct signal connect

**Status:** ✔️ fix applied — await user verify window opens

## Problem

🔷 App aborts at startup when constructing `ActivityBanner`:

- **Actual:** `GLib-GObject: invalid (NULL) pointer instance` → critical handler abort
- **Expected:** window opens; banner action button wires without crash
- **Repro:** launch `ollmchat` (desktop); crash during `OLLMapp.Window` construction

## Evidence

ℹ️ GDB backtrace (user):

- `#14` `ActivityBanner.vala:108` — `g_signal_connect_object`
- `#18`–`#20` `ActivityBanner.new` → `Window.vala:183`

✔️ Line 108 is `this.action_button.clicked.connect(...)` inside `construct`.

✔️ `action_button` is assigned in the **public constructor body** after `Object(...)` (line 84).

✔️ Introduced in `39457cff` (“cancel support on notification”) — clicked handler added to `construct` while button creation stayed in the ctor body.

## Root cause

✔️ Vala/GObject construction order: `construct` runs **during** `Object(...)`, **before** the rest of the public constructor body. At line 108, `this.action_button` is still NULL.

`this.notification.connect(...)` is fine (signal on `this`). Connecting a child widget created later is not.

## Proposed fix

💩 Move `action_button.clicked.connect` into the public constructor body **immediately after** `action_button` is created and appended. Leave `notification.connect` in `construct`.

### 1. `ollmapp/ActivityBanner.vala` — wire clicked after button exists

**Why:** child button does not exist until after `Object(...)` returns; connecting in `construct` is the NULL instance.

**Where:** ctor body after `row.append(this.action_button)`; remove the clicked connect from `construct`.

**Depends on:** none.

#### Remove

```vala
		construct
		{
			this.notification.connect(this.on_notification);
			this.action_button.clicked.connect(() => {
				if (this.current_notification.action_label == "") {
					return;
				}
				this.notification_reply(this.current_notification);
			});
		}
```

#### Replace with

```vala
		construct
		{
			this.notification.connect(this.on_notification);
		}
```

#### Add — after `row.append(this.action_button);` in the public constructor: connect clicked once the button exists

```vala
			this.action_button.clicked.connect(() => {
				if (this.current_notification.action_label == "") {
					return;
				}
				this.notification_reply(this.current_notification);
			});
```

## Attempts / changelog

- ✔️ Confirmed from backtrace + source + commit `39457cff` (no extra debug needed).
- ✔️ Applied: `action_button.clicked` connect moved into ctor body after button create.
- ✔️ Dropped `construct` entirely — `notification.connect` also in ctor body after `Object(...)` (no construct-props / no need for a separate block).

## Next

⏳ ✅ User verify: rebuild/launch — window opens without GLib-GObject NULL abort.
