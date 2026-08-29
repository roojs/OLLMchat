# 2.6.7 libsecret + hold two seconds

> **Do not update `docs/plans/TOOLS-1.0-summary.md` for this plan.**

> Split from [`TOOLS-2.6.5-run-command-timeout-live-spill.md`](TOOLS-2.6.5-run-command-timeout-live-spill.md). Timeout / live / spill already landed there. VTE is **not** here: [`TOOLS-2.6.6-FUTURE-run-command-vte.md`](TOOLS-2.6.6-FUTURE-run-command-vte.md).

**Status:** **⏳** **proposed**

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/2.6-DONE-run-terminal-command-tool.md`](done/2.6-DONE-run-terminal-command-tool.md) · related: [`done/2.6.3-DONE-run-command-root-elevation.md`](done/2.6.3-DONE-run-command-root-elevation.md)

**Precedent (password store + hold fill):** RooTerm — `app.RooTerm/src/Config.vala` (`Secret.password_store`), `app.RooTerm/src/Terminal/Ssh.vala` (`Secret.password_lookup_sync`), `app.RooTerm/src/Host/TabBar.vala` (overlay fill on hold/countdown), `app.RooTerm/resources/style.css` (`.host-tab-close-fill`).

---

## Purpose

- **🔷** `⏳` First successful sudo password is stored in libsecret.
- **🔷** `⏳` Later root prompts: **hold** the allow control for **two seconds**. Background fill animates while held. Release early cancels. A single click must not approve.
- **🔷** `⏳` After the hold, the same `sudo -S true` check as typed. If it fails, show the password form and drop the secret.
- **🔷** `⏳` Deny stays a normal click.
- **🔷** `⏳` **Linux GTK** only. **Windows** / **Android:** no libsecret. Root elevation stays Linux-only.
- **ℹ️** RooTerm fill: `Gtk.Overlay` child is a box whose `width_request` grows; CSS paints `.host-tab-close-fill`. Copy that overlay-on-the-button idea, do not import RooTerm widgets.
- **ℹ️** RooTerm secret: `Secret.Schema` + `Secret.password_store.begin` / `Secret.password_lookup_sync`. Inline the same calls in `ChatPermission` (no secret-helper class).

---

## Current behaviour

- **ℹ️** Root runs: type password every time → `sudo -S true` check → pipe into `sudo -S /bin/sh -c …`. Copy says the password is not saved. See `ChatPermission.vala`, `Request.execute_with_subprocess()`.
- **ℹ️** **Windows:** `run_command` is registered. No sudo, no libsecret.
- **ℹ️** **Android:** tool is **not** registered.

---

## When a secret exists ⏳

- **🔷** `⏳` Hide the password entry.
- **🔷** `⏳` Allow (root) becomes a hold target. Label along the lines of `Hold 2s — use saved password`.

---

## When no secret exists ⏳

- **🔷** `⏳` Keep today’s type-then-Allow path (`sudo -S true` before resume).
- **🔷** `⏳` On success, `Secret.password_store` the password, then proceed as now.

---

## Wrong stored password ⏳

- **🔷** `⏳` `sudo -S true` still runs after a completed hold (same check as typed).
- **🔷** `⏳` Failure: show the entry, error label, delete the bad secret, do **not** resume.

---

## Schema (confirm) ⏳

- **💩** `⏳` Schema `org.roojs.ollmchat.Elevation`, attribute `user` = `GLib.Environment.get_user_name()`, label `OLLMchat sudo`. One secret per login user.

---

## Build ⏳

- **🔷** `⏳` `dependency('libsecret-1')` on `libollmchatgtk` (**Linux only**). `--pkg=libsecret-1`.
- **🔷** `⏳` `debian/control` Build-Depends: `libsecret-1-dev`.
- **ℹ️** Windows / Android meson: do not `dependency('libsecret-1', required: true)`.
- **ℹ️** `host_machine.system() == 'linux'` is already false on Android and Windows.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libollmchatgtk/meson.build` — Linux-only `libsecret-1` ⏳

**Why:** GTK permission widget talks to the session keyring. Other hosts must not require the pkg.

**Where:** immediately after the `ollmchatgtk_deps = [ … ]` list (after `valac.find_library('posix'),` / `]`).

**Depends on:** none.

#### Add — append libsecret only when the host is Linux

```meson
if host_machine.system() == 'linux'
  ollmchatgtk_deps += dependency('libsecret-1')
endif
```

- **ℹ️** The existing `library()` `vala_args` do not list `--pkg=gtk4` on the Linux cut; Meson injects pkgs from `dependencies`. Same for `libsecret-1`. Do **not** add `--pkg=libsecret-1` on the Android `vala_args` branch.

### 2. `debian/control` — `libsecret-1-dev` ⏳

**Why:** Debian builds need the headers / vapi.

**Where:** `Build-Depends`, after `libadwaita-1-dev,`.

**Depends on:** none.

- **ℹ️** Same `Build-Depends` line exists in `debian/split/control`, `debian/monolithic/control`, and `debian/monolithic-remote-only/control`. Apply the same **Add** there so those packaging trees still configure.

#### Add — build dependency next to the other GTK libs

```
               libsecret-1-dev,
```

### 3. `docs/meson.build` — valadoc `--pkg=libsecret-1` ⏳

**Why:** Valadoc lists pkgs explicitly and already compiles `ChatPermission.vala` with `-D LINUX`.

**Where:** `valadoc_docs` `command:` array, after `'--pkg=gtk4',`.

**Depends on:** **### 1**.

#### Add — libsecret pkg for valadoc

```meson
    '--pkg=libsecret-1',
```

### 4. `resources/style.css` — hold fill ⏳

**Why:** Semi-transparent fill over Allow while the pointer is held.

**Where:** after `.permission-widget .elevation-password-error` (before `.permission-widget .command-preview`).

**Depends on:** none.

#### Add — overlay fill on the Allow button while holding

```css
.permission-widget .elevation-hold-fill {
  background-color: alpha(@destructive_color, 0.45);
}
```

---

## `ChatPermission.vala` ⏳

- **🔷** `⏳` Overlay fill box, CSS class `.elevation-hold-fill`, `halign = START`, width 1 until press.
- **🔷** `⏳` `Gtk.GestureClick` pressed: arm `GLib.Timeout.add(50)`. Each tick: fill width = `(button_width * elapsed_ms) / 2000`. At `>= 2000` and still pressed: lookup secret, put it in the (hidden) entry, run existing `validate_elevation_and_resume`.
- **🔷** `⏳` Released, gesture `cancel`, or pointer leave before 2000: `Source.remove`, `fill.width_request = 1`, `visible = false`.
- **🔷** `⏳` While `elevation_hold`, the existing Allow `clicked` handler must return without validating.
- **ℹ️** Match RooTerm tick math in `Host/TabBar.vala` (`width_request = (row.get_width() * left) / total`) — here fill **grows** with elapsed, it does not shrink.
- **ℹ️** `#if LINUX` around `Secret.*` and the overlay. `elevation_hold` stays a normal field (false on Windows / Android).
- **ℹ️** `password_store.begin` is fire-and-forget after a successful `sudo -S true`. Do not wait for the keyring before resume. C puts the async callback **before** the attribute varargs, so do **not** `yield Secret.password_store(...)`.

### 5. `libollmchatgtk/ChatPermission.vala` — fields ⏳

**Why:** Hold state and Linux schema. No helper type.

**Where:** class body, after `private Gtk.Button allow_always_btn;`.

**Depends on:** none.

#### Add — hold flag (all hosts); fill / timer / schema on Linux

```vala
		private bool elevation_hold = false;
#if LINUX
		private Gtk.Box hold_fill;
		private uint hold_timeout_src = 0;
		private int64 hold_start_us = 0;
		private Secret.Schema elevation_schema;
#endif
```

### 6. `libollmchatgtk/ChatPermission.vala` — constructor: overlay + hold gesture ⏳

**Why:** Friction is the hold, not a second click. Inline press / tick / release in the constructor (no `start_hold()`).

**Where:** `public ChatPermission()`, replace the `allow_once_btn` append; schema + overlay + controllers go in that same spot.

**Depends on:** **### 4**, **### 5**.

#### Remove

```vala
			this.button_box.append(this.deny_always_btn);
			this.button_box.append(this.deny_once_btn);
			this.button_box.append(this.allow_once_btn);
			this.button_box.append(this.allow_always_btn);
```

#### Replace with

```vala
			this.button_box.append(this.deny_always_btn);
			this.button_box.append(this.deny_once_btn);
#if LINUX
			this.elevation_schema = new Secret.Schema(
				"org.roojs.ollmchat.Elevation",
				Secret.SchemaFlags.NONE,
				"user", Secret.SchemaAttributeType.STRING);
			this.hold_fill = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				halign = Gtk.Align.START,
				valign = Gtk.Align.FILL,
				hexpand = false,
				vexpand = true,
				width_request = 1,
				visible = false,
				can_target = false
			};
			this.hold_fill.add_css_class("elevation-hold-fill");
			var allow_overlay = new Gtk.Overlay();
			allow_overlay.set_child(this.allow_once_btn);
			allow_overlay.add_overlay(this.hold_fill);
			this.button_box.append(allow_overlay);
			var hold_press = new Gtk.GestureClick();
			hold_press.pressed.connect((n_press, x, y) => {
				if (!this.elevation_hold) {
					return;
				}
				this.hold_fill.visible = true;
				this.hold_fill.width_request = 1;
				this.hold_start_us = GLib.get_monotonic_time();
				if (this.hold_timeout_src != 0) {
					GLib.Source.remove(this.hold_timeout_src);
				}
				this.hold_timeout_src = GLib.Timeout.add(50, () => {
					var elapsed_ms = (GLib.get_monotonic_time() - this.hold_start_us) / 1000;
					this.hold_fill.width_request = (int) ((this.allow_once_btn.get_width() * elapsed_ms) / 2000);
					if (elapsed_ms < 2000) {
						return true;
					}
					this.hold_timeout_src = 0;
					this.hold_fill.visible = false;
					this.hold_fill.width_request = 1;
					var stored = "";
					try {
						stored = Secret.password_lookup_sync(
							this.elevation_schema,
							null,
							"user", GLib.Environment.get_user_name());
					} catch (GLib.Error e) {
						stored = "";
					}
					if (stored == null || stored == "") {
						this.elevation_hold = false;
						this.password_label.set_visible(true);
						this.password_entry.set_visible(true);
						this.allow_once_btn.label = "Allow (root)";
						this.allow_once_btn.sensitive = false;
						this.password_entry.grab_focus();
						return false;
					}
					this.password_entry.text = stored;
					this.validate_elevation_and_resume.begin(
						OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE);
					return false;
				});
			});
			hold_press.released.connect((n_press, x, y) => {
				if (this.hold_timeout_src == 0) {
					return;
				}
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
				this.hold_fill.width_request = 1;
				this.hold_fill.visible = false;
			});
			hold_press.cancel.connect(() => {
				if (this.hold_timeout_src == 0) {
					return;
				}
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
				this.hold_fill.width_request = 1;
				this.hold_fill.visible = false;
			});
			this.allow_once_btn.add_controller(hold_press);
			var hold_motion = new Gtk.EventControllerMotion();
			hold_motion.leave.connect(() => {
				if (this.hold_timeout_src == 0) {
					return;
				}
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
				this.hold_fill.width_request = 1;
				this.hold_fill.visible = false;
			});
			this.allow_once_btn.add_controller(hold_motion);
#else
			this.button_box.append(this.allow_once_btn);
#endif
			this.button_box.append(this.allow_always_btn);
```

### 7. `libollmchatgtk/ChatPermission.vala` — `request()`: lookup → hold or type ⏳

**Why:** Non-empty secret hides the entry and arms hold. Empty / error keeps today’s type form.

**Where:** `request()`, from `this.password_label.set_visible(high_risk);` through the high-risk `GLib.Idle.add` focus; plus cleanup before `return` after the yield.

**Depends on:** **### 5**, **### 6**.

##### Part 1 — high-risk visibility + lookup

**Where:** after `// allow_once_btn is always visible`, through the `GLib.Idle.add` that focuses the password entry.

#### Remove

```vala
			this.password_label.set_visible(high_risk);
			this.password_entry.set_visible(high_risk);
			this.password_error_label.set_visible(false);
			if (high_risk) {
				this.password_entry.text = "";
				this.password_error_label.label = "";
				this.allow_once_btn.sensitive = false;
			}
			
			if (high_risk) {
				this.add_css_class ("high-risk");
				this.allow_once_btn.remove_css_class ("suggested-action");
				this.allow_once_btn.add_css_class ("destructive-action");
				this.allow_once_btn.label = "Allow (root)";
			}
			if (!high_risk) {
				this.remove_css_class ("high-risk");
				this.allow_once_btn.remove_css_class ("destructive-action");
				this.allow_once_btn.add_css_class ("suggested-action");
				this.allow_once_btn.label = "Allow";
				this.allow_once_btn.sensitive = true;
			}
			
			// Show the widget
			this.set_visible(true);

			if (high_risk) {
				GLib.Idle.add(() => {
					this.password_entry.grab_focus();
					return false;
				});
			}
```

#### Replace with

```vala
			this.elevation_hold = false;
			this.password_label.set_visible(high_risk);
			this.password_entry.set_visible(high_risk);
			this.password_error_label.set_visible(false);
			if (high_risk) {
				this.password_entry.text = "";
				this.password_error_label.label = "";
				this.allow_once_btn.sensitive = false;
			}
			
			if (high_risk) {
				this.add_css_class ("high-risk");
				this.allow_once_btn.remove_css_class ("suggested-action");
				this.allow_once_btn.add_css_class ("destructive-action");
				this.allow_once_btn.label = "Allow (root)";
			}
			if (!high_risk) {
				this.remove_css_class ("high-risk");
				this.allow_once_btn.remove_css_class ("destructive-action");
				this.allow_once_btn.add_css_class ("suggested-action");
				this.allow_once_btn.label = "Allow";
				this.allow_once_btn.sensitive = true;
			}
#if LINUX
			if (high_risk) {
				var stored = "";
				try {
					stored = Secret.password_lookup_sync(
						this.elevation_schema,
						null,
						"user", GLib.Environment.get_user_name());
				} catch (GLib.Error e) {
					stored = "";
				}
				if (stored != null && stored != "") {
					this.elevation_hold = true;
					this.password_label.set_visible(false);
					this.password_entry.set_visible(false);
					this.allow_once_btn.sensitive = true;
					this.allow_once_btn.label = "Hold 2s — use saved password";
				}
			}
#endif
			
			// Show the widget
			this.set_visible(true);

			if (high_risk) {
				GLib.Idle.add(() => {
					if (this.elevation_hold) {
						return false;
					}
					this.password_entry.grab_focus();
					return false;
				});
			}
```

##### Part 2 — reset hold when the prompt closes

**Where:** after `this.password_entry.text = "";` in the post-`yield` cleanup, before `this.pending_high_risk = false;`.

#### Remove

```vala
			this.password_entry.text = "";
			this.pending_high_risk = false;
```

#### Replace with

```vala
			this.password_entry.text = "";
#if LINUX
			if (this.hold_timeout_src != 0) {
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
			}
			this.hold_fill.visible = false;
			this.hold_fill.width_request = 1;
#endif
			this.elevation_hold = false;
			this.pending_high_risk = false;
```

### 8. `libollmchatgtk/ChatPermission.vala` — `validate_elevation_and_resume`: store / clear ⏳

**Why:** Same `sudo -S true` as typed. Success stores. Failed hold shows the form and deletes the secret.

**Where:** `validate_elevation_and_resume`, the `if (!ok)` body, then immediately after `this.pending_elevation_password = password;`.

**Depends on:** **### 5**.

##### Part 1 — wrong password: type form + clear secret when it was a hold

**Where:** the existing `if (!ok)` block.

#### Remove

```vala
			if (!ok) {
				this.password_error_label.label = "Wrong password. Try again.";
				this.password_error_label.set_visible(true);
				this.password_entry.text = "";
				this.allow_once_btn.sensitive = false;
				this.password_entry.grab_focus();
				return;
			}

			this.pending_elevation_password = password;
```

#### Replace with

```vala
			if (!ok) {
				this.password_error_label.label = "Wrong password. Try again.";
				this.password_error_label.set_visible(true);
				this.password_entry.text = "";
				this.allow_once_btn.sensitive = false;
#if LINUX
				if (this.elevation_hold) {
					this.elevation_hold = false;
					this.password_label.set_visible(true);
					this.password_entry.set_visible(true);
					this.allow_once_btn.label = "Allow (root)";
					try {
						Secret.password_clear_sync(
							this.elevation_schema,
							null,
							"user", GLib.Environment.get_user_name());
					} catch (GLib.Error e) {
					}
				}
#endif
				this.password_entry.grab_focus();
				return;
			}

			this.pending_elevation_password = password;
#if LINUX
			Secret.password_store.begin(
				this.elevation_schema,
				Secret.COLLECTION_DEFAULT,
				"OLLMchat sudo",
				password,
				null,
				(obj, res) => {
					try {
						Secret.password_store.end(res);
					} catch (GLib.Error e) {
					}
				},
				"user", GLib.Environment.get_user_name());
#endif
```

### 9. `libollmchatgtk/ChatPermission.vala` — `create_button`: ignore Allow click while holding ⏳

**Why:** A single click must not use the saved password. Hold completion calls `validate_elevation_and_resume.begin` itself.

**Where:** `create_button`, `clicked` handler, `ALLOW_ONCE` / `ALLOW_ALWAYS` arm, inside `if (this.pending_high_risk)`.

**Depends on:** **### 5**, **### 6**.

#### Remove

```vala
						if (this.pending_high_risk) {
							if (this.password_entry.get_text().strip() == "") {
								return;
							}
							this.validate_elevation_and_resume.begin (response);
							break;
						}
```

#### Replace with

```vala
						if (this.pending_high_risk) {
							if (this.elevation_hold) {
								return;
							}
							if (this.password_entry.get_text().strip() == "") {
								return;
							}
							this.validate_elevation_and_resume.begin (response);
							break;
						}
```

---

## Copy that currently says the password is not saved ⏳

- **💩** `⏳` User-facing root copy still says the password is not saved. After this plan that is false. Wording below is a proposal.

### 10. `liboctools/RunCommand/Request.vala` — `build_perm_question()` root copy ⏳

**Why:** The permission question is shown for both type and hold. Do not claim the password is unused after a successful check.

**Where:** `build_perm_question()`, the last sentence of `this.permission_question` when `this.run_as_root`.

**Depends on:** none.

#### Remove

```vala
					+ "Enter your password below. It is used only for this command and is not saved.";
```

#### Replace with

```vala
					+ "If asked, enter your password. After a successful check it is stored in the system keyring.";
```

### 11. `liboctools/RunCommand/Tool.vala` — Root Access bullet ⏳

**Why:** Tool help still says `(not saved)`.

**Where:** `description` / help text, the bullet under `Root Access (Linux GTK app only):`.

**Depends on:** none.

#### Remove

```
- The user must approve in the app and enter their password in the permission prompt (not saved).
```

#### Replace with

```
- The user must approve in the app. After a successful check the password is stored in the system keyring.
```

---

## LLM notes

- **🚫** Do not add a `Use a different password` control. If the stored secret fails `sudo -S true`, the existing wrong-password path already shows the entry.
- **🚫** Do not add a secret-helper class or `start_hold()` / `on_hold_tick()` — inline in `ChatPermission`.
- **🚫** Do not make Allow-Always remember root commands (still `one_time_only` for `run_as_root`).
- **🚫** Do not put libsecret in `liboctools`.
- **🚫** Do not `dependency('libsecret-1')` as required on Windows or Android meson.
- **🚫** Do not treat a single click as “use saved password”.
- **🚫** Do not register `run_command` on Android in this plan.
- **🚫** Do not implement VTE — that is **2.6.6**.
- **🚫** Do not `yield Secret.password_store(...)` — C varargs vs async callback order. Use `password_store.begin` as fenced.
- **💩** `debian/README` apt install line does not list `libsecret-1-dev` yet. Optional follow-up.
