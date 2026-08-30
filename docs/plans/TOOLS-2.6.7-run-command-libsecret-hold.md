# 2.6.7 libsecret + hold two seconds

> **Do not update `docs/plans/TOOLS-1.0-summary.md` for this plan.**

> Split from [`TOOLS-2.6.5-run-command-timeout-live-spill.md`](TOOLS-2.6.5-run-command-timeout-live-spill.md). Timeout / live / spill already landed there. VTE is **not** here: [`TOOLS-2.6.6-FUTURE-run-command-vte.md`](TOOLS-2.6.6-FUTURE-run-command-vte.md).

**Status:** **✔️** agent-done — awaiting user **✅**

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/2.6-DONE-run-terminal-command-tool.md`](done/2.6-DONE-run-terminal-command-tool.md) · related: [`done/2.6.3-DONE-run-command-root-elevation.md`](done/2.6.3-DONE-run-command-root-elevation.md)

**Precedent (password store + hold fill):** RooTerm — `app.RooTerm/src/Config.vala` (`Secret.password_store`), `app.RooTerm/src/Terminal/Ssh.vala` (`Secret.password_lookup_sync`), `app.RooTerm/src/Host/TabBar.vala` (overlay fill on hold/countdown), `app.RooTerm/resources/style.css` (`.host-tab-close-fill`).

**Precedent (platform stub):** `libocbwrap` — Linux sources vs a non-Linux file. Same class name; Meson picks one tree. Valadoc lists the Linux file only. Stub lives in `stub/` (not `windows/`) so Android is not compiling a Windows path.

---

## Purpose

- **🔷** `✔️` First successful sudo password is stored in libsecret.
- **🔷** `✔️` Later root prompts: if a secret exists, `prepare()` runs `check(true)` **before** showing hold. Fail → type form. Success → hold Allow **two seconds**.
- **🔷** `✔️` After the hold (or a typed Allow), `check(false)`: success stores + `checked`; fail shows the type form and drops the secret.
- **🔷** `✔️` Deny stays a normal click.
- **🔷** `✔️` `ChatPermission` owns a `Sudo` widget. Hold, keyring, password row, and `sudo -S true` live there.
- **🔷** `✔️` Named methods on `Sudo`: `prepare()`, `reset()`, `submit()`, `check()`, `store()`, `on_hold_pressed()`, `on_hold_tick()`. `check(bool hold)` owns post-success and post-fail UI. `hold` true (from `prepare`): success arms hold. `hold` false (from `submit` / hold tick): success `store` + `checked`. Fail always shows the type form.
- **🔷** `✔️` Non-Linux (`android` and `windows`) compile `stub/Sudo.vala` — overlay so Allow still packs, empty `prepare` / `reset` / `submit`. No libsecret, no hold. `ChatPermission` has **no** `#if`.
- **🔷** `✔️` libsecret is the Linux Secret Service (GNOME Keyring). It is **not** on Pixiewood/Android and is **not** Android Keystore. Do not wrap it, do not `--pkg=libsecret-1` on the Android `library()` `vala_args`, do not add `libsecret-1-dev` to Android host apt.
- **🔷** `✔️` Linux meson + packaging + Linux CI + build docs gain `libsecret-1`. Windows MSYS2 does not.
- **ℹ️** RooTerm fill: `Gtk.Overlay` child is a box whose `width_request` grows. Copy that idea, do not import RooTerm widgets.
- **ℹ️** Constructor is `Sudo(Gtk.Button allow)`. Resume to ChatPermission is `checked(string password)`.

---

## Current behaviour

- **ℹ️** Root runs: type password every time → `sudo -S true` check → pipe into `sudo -S /bin/sh -c …`. Copy says the password is not saved. See `ChatPermission.vala`, `Request.execute_with_subprocess()`.
- **ℹ️** **Windows:** `run_command` is registered. No sudo. `run_as_root` returns `ERROR: run_as_root is not supported on Windows` before the permission widget.
- **ℹ️** **Android:** `run_command` is **not** registered. No sudo on the device. `libollmchatgtk` still builds (chat UI), so `Sudo` must compile — that is the stub, not libsecret.

---

## `Sudo` ✔️

- **🔷** `✔️` `Gtk.Box` owned by `ChatPermission`. Linux owns `label`, `entry`, `error_label` (those leave `ChatPermission`).
- **🔷** `✔️` Signals: `checked(string password)` after a successful `check(false)`; `busy(bool on)` so `ChatPermission` can disable Deny while that runs.
- **🔷** `✔️` Public `Gtk.Overlay overlay` — ChatPermission packs this in the button row instead of the raw Allow button.
- **🔷** `✔️` Linux: overlay fill, libsecret, hold, `check()`. Stub (`stub/Sudo.vala`): wrap Allow in `overlay`, no-op methods.
- **🚫** No secret-helper class. Hold press is `on_hold_pressed` / `on_hold_tick`, not a giant constructor lambda.

### Flow ✔️

- **🔷** `✔️` Prompt entry: `ChatPermission.request(..., high_risk: true)` → `this.sudo.prepare.begin()`.
- **🔷** `✔️` `prepare()` looks up the secret: none → type form; present → `yield this.check(true)` (no hold button until that succeeds).
- **🔷** `✔️` Type confirm: Allow `clicked` in `create_button` → `this.sudo.submit()`. Enter on the entry also calls `submit()`.
- **🔷** `✔️` `submit()` no-ops while `holding`, otherwise busy + `check.begin(false)`.
- **🔷** `✔️` Hold confirm: `on_hold_tick` at 2s busy + `check.begin(false)` (password already in `entry` from `prepare`).
- **🔷** `✔️` Fail stays in the widget. `request()` keeps yielding.

---

## When a secret exists ✔️

- **🔷** `✔️` After `check(true)` succeeds: hide the password entry and arm hold.
- **🔷** `✔️` Allow (root) becomes a hold target. Label along the lines of `Hold 2s — use saved password`.

---

## When no secret exists ✔️

- **🔷** `✔️` Keep today’s type-then-Allow path (`submit()` → `check(false)`).
- **🔷** `✔️` On success, `Secret.password_store` the password, then `checked`.

---

## Wrong stored password ✔️

- **🔷** `✔️` `check(true)` in `prepare()` and `check(false)` after hold/type share the same fail UI.
- **🔷** `✔️` Failure: show the entry, error label, delete the bad secret, do **not** emit `checked`.

---

## Schema (confirm) ✔️

- **💩** `✔️` Schema `org.roojs.ollmchat.Sudo`, attribute `user` = `GLib.Environment.get_user_name()`, label `OLLMchat sudo`. One secret per login user.

---

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

## Meson ✔️

### 1. `libollmchatgtk/meson.build` — Linux `Sudo.vala` + libsecret; else stub ✔️

**Why:** One class name, two files. libsecret only when the host is Linux.

**Where:** after the `ollmchatgtk_deps = [ … ]` list; after the `ollmchatgtk_src = files([ … ])` list (do **not** put `Sudo.vala` inside the common `files([` list).

**Depends on:** none.

#### Add — Linux dep + source split (same pattern as `libocbwrap`)

```meson
if host_machine.system() == 'linux'
  ollmchatgtk_deps += dependency('libsecret-1')
  ollmchatgtk_src += files('Sudo.vala')
else
  ollmchatgtk_src += files('stub/Sudo.vala')
endif
```

- **ℹ️** Meson injects `--pkg=libsecret-1` from the dependency on the Linux `library()` cut. Do **not** add that pkg on the Android `vala_args` branch.

### 2. `docs/meson.build` — valadoc source + pkg ✔️

**Why:** Valadoc lists Linux sources only (`libocbwrap/windows/*` is already omitted).

**Where:** `valadoc_docs` `input:` — `Sudo.vala` **before** `ChatPermission.vala`. `command:` — `'--pkg=libsecret-1',` after `'--pkg=gtk4',`.

**Depends on:** **### 1**.

#### Add — Linux Sudo before ChatPermission

```meson
    '../libollmchatgtk/Sudo.vala',
```

#### Add — libsecret pkg for valadoc

```meson
    '--pkg=libsecret-1',
```

---

## Linux packages (not Android, not Windows) ✔️

- **🔷** `✔️` Every Linux apt / spec / sqgipkg list that already has `libadwaita-1-dev` (or `pkgconfig(libadwaita-1)`) also gets libsecret.
- **🔷** `✔️` RPM: `packaging/rpm/ollmchat.spec` **and** `scripts/ci/build-rpm.sh` (`pkgconfig_deps`). Fedora/openSUSE CI does not list packages in `x-rpm.yml` — it runs that script.
- **🚫** `.github/workflows/x-android.yml`, `docs/android-build.md`, `scripts/android/regression/test-r17-android-host-vapi-packages.sh` — stub, no libsecret.
- **🚫** `.github/workflows/x-windows.yml`, `.github/workflows/windows-build.yml` — stub, no mingw libsecret.
- **ℹ️** README points at `docs/BUILD.md`; no package list there.

### 3. Apt / Debian / CI — `libsecret-1-dev` ✔️

**Why:** Configure and valadoc fail without the vapi.

**Where:** next to `libadwaita-1-dev` in each file.

**Depends on:** none.

Same **Add** in all of these:

- `debian/control`
- `debian/split/control`
- `debian/monolithic/control`
- `debian/monolithic-remote-only/control`
- `debian/README` (the `apt-get install` block)
- `docs/BUILD.md` (the `sudo apt install` block)
- `docs/creating-releases.md` (the Debian `apt-get install` block)
- `.github/workflows/x-debian.yml`
- `.github/workflows/x-sqgipkg.yml`
- `.github/workflows/deploy-docs.yml`
- `.github/workflows/remote-only-build.yml`

#### Add — Debian package name

```
libsecret-1-dev
```

Keep each file’s existing separators (`\` newlines, commas in `control`, spaces on one line in workflows).

### 4. `docs/BUILD.md` — what the package is for ✔️

**Why:** Other GTK deps have a one-line note.

**Where:** after the `**libseccomp-dev**` bullet.

**Depends on:** **### 3**.

#### Add — libsecret note

```markdown
- **libsecret-1-dev** — sudo password keyring (`OLLMchatGtk.Sudo`, Linux)
```

### 5. `sqgipkg.json` — both Linux arches ✔️

**Why:** sqgi sysroot apt must match meson.

**Where:** each `"packages"` array, after `"libadwaita-1-dev",` (x86_64 and aarch64).

**Depends on:** none.

#### Add — twice (both arch `deb.packages` lists)

```json
            "libsecret-1-dev",
```

### 6. `packaging/rpm/ollmchat.spec` — Fedora / openSUSE ✔️

**Why:** `rpmbuild` reads BuildRequires from this spec. `x-rpm.yml` only runs `scripts/ci/build-rpm.sh`.

**Where:** after `BuildRequires: pkgconfig(libadwaita-1)`. Devel package: after `Requires: libocmarkdowngtk-devel%{?_isa} = %{version}-%{release}` on `%package -n libollmchatgtk-devel`.

**Depends on:** none.

#### Add — build-time pkgconfig (Fedora `libsecret-devel` / openSUSE same virtual)

```
BuildRequires: pkgconfig(libsecret-1)
```

#### Add — `libollmchatgtk-devel` so the vapi pulls the keyring headers

```
Requires: pkgconfig(libsecret-1)
```

### 6b. `scripts/ci/build-rpm.sh` — `pkgconfig_deps` ✔️

**Why:** The script `dnf`/`zypper` installs this array **before** `rpmbuild`. Spec BuildRequires alone is not enough — the CI image will not have libsecret unless it is in this list.

**Where:** `pkgconfig_deps=(` array, after `'pkgconfig(libadwaita-1)'`.

**Depends on:** **### 6**.

#### Add

```bash
  'pkgconfig(libsecret-1)'
```

## Bwrap vs the keyring ✔️

- **🔷** `✔️` Storing the sudo password in libsecret is only safe if **sandboxed** `run_command` cannot read it. Today it can: libsecret is D-Bus Secret Service (`org.freedesktop.secrets`), usually a **unix socket** (`$XDG_RUNTIME_DIR/bus` / `DBUS_SESSION_BUS_ADDRESS`), not TCP.
- **ℹ️** `--unshare-net` does **not** cover that. `--ro-bind / /` still exposes the bus. The child inherits the session-bus env. Seccomp `socket`/`connect` notify (when network is off) **logs** AF_UNIX; it does not deny it.
- **🔷** `✔️` In `OLLMbwrap.Bubble.build_bubble_args`, drop the session bus for every bwrap child: `--unsetenv DBUS_SESSION_BUS_ADDRESS` and `--tmpfs` on `XDG_RUNTIME_DIR` (or at least replace the `bus` socket so `secret-tool` cannot connect). The GTK app still talks to libsecret **outside** bwrap.
- **ℹ️** `run_as_root` is **not** bwrapped. A root command can still reach the user session bus if sudo keeps that env. Do not claim the keyring is safe on that path.
- **🚫** Do not give the model a `secret-tool` recipe. Ban the bus; do not document how to query it.

### 6c. `libocbwrap/Bubble.vala` — `build_bubble_args()`: no session bus in the sandbox ✔️

**Why:** Without this, `secret-tool` / any D-Bus client in `run_command` can read `OLLMchat sudo`.

**Where:** `build_bubble_args()`, after `--ro-bind / /` (same region as `--tmpfs /tmp`). `--tmpfs` on the runtime dir **must** come after the root bind, or the real socket is visible again.

**Depends on:** none.

**ℹ️** MCP stdio uses the same `build_bubble_args`. Hiding the session bus is intended; a server that needs D-Bus is a later exception, not the default.

#### Add — unset session bus; tmpfs over the runtime dir so the unix socket is gone

```vala
			args += "--unsetenv";
			args += "DBUS_SESSION_BUS_ADDRESS";
			var runtime_dir = GLib.Environment.get_variable("XDG_RUNTIME_DIR");
			if (runtime_dir != null) {
				args += "--tmpfs";
				args += runtime_dir;
			}
```

---

## CSS ✔️

### 7. `resources/style.css` — hold fill ✔️

**Why:** Semi-transparent fill over Allow while the pointer is held.

**Where:** after `.permission-widget .elevation-password-error` (before `.permission-widget .command-preview`). Keep existing `.elevation-password-entry` / `.elevation-password-error` classes on `entry` / `error_label`.

**Depends on:** none.

#### Add — overlay fill on the Allow button while holding

```css
.permission-widget .sudo-hold-fill {
  background-color: alpha(@destructive_color, 0.45);
}
```

---

## New files ✔️

### 8. `libollmchatgtk/Sudo.vala` — Linux (new file) ✔️

**Why:** Sudo UI + keyring. `prepare` is the prompt entry. Hold handlers sit last. `check(bool hold)` owns success and fail.

**Where:** new file. Whole file is an **Add**.

**Depends on:** **### 1**, **### 7**.

- **🔷** Method order after the constructor: `prepare`, `reset`, `submit`, `check`, `store`, `on_hold_pressed`, `on_hold_tick`.
- **🔷** `check(bool hold)`: two small tries (`sudo -k`, then `sudo -S true`). Success/fail UI outside those tries. `hold` true → arm hold. `hold` false → `store` + `checked`.
- **🔷** `store(string password)` is only `password_store.begin` / `end`. Not `yield Secret.password_store`.
- **🔷** Locals in `check()`: `error`, `ok`, `proc`, `stdin`. Not `klauncher` / `kproc`.
- **🔷** `on_hold_pressed` / `on_hold_tick` — constructor only `pressed.connect(this.on_hold_pressed)`.

#### Add — new Linux class (complete file)

```vala
namespace OLLMchatGtk
{
	/**
	 * Root sudo prompt owned by {@link ChatPermission}.
	 *
	 * Stores a successful password in libsecret. Later prompts hide the
	 * entry and require a two-second hold on Allow. Wrong stored secrets
	 * fall back to the type form. Windows and Android compile a no-op stub.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.sudo = new Sudo(this.allow_once_btn);
	 * this.sudo.checked.connect((password) => {
	 *     this.pending_elevation_password = password;
	 *     this.resume_callback();
	 * });
	 * if (high_risk) {
	 *     this.sudo.prepare.begin();
	 * }
	 * }}}
	 */
	public class Sudo : Gtk.Box
	{
		public signal void checked(string password);
		public signal void busy(bool on);

		public Gtk.Overlay overlay;
		private Gtk.Button allow;
		private Gtk.Label label;
		private Gtk.PasswordEntry entry;
		private Gtk.Label error_label;
		private Gtk.Box hold_fill;
		private uint hold_timeout_src = 0;
		private int64 hold_start_us = 0;
		private bool holding = false;
		private Secret.Schema schema;

		/**
		 * Wrap Allow in an overlay and own the password row.
		 *
		 * @param allow the permission Allow button (packed via {@link overlay})
		 */
		public Sudo(Gtk.Button allow)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.allow = allow;
			this.hexpand = true;
			this.schema = new Secret.Schema(
				"org.roojs.ollmchat.Sudo",
				Secret.SchemaFlags.NONE,
				"user", Secret.SchemaAttributeType.STRING);
			this.label = new Gtk.Label("Your password (sudo):") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4,
				visible = false
			};
			this.entry = new Gtk.PasswordEntry() {
				hexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4,
				visible = false,
				css_classes = { "elevation-password-entry" }
			};
			this.error_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 8,
				wrap = true,
				visible = false,
				css_classes = { "elevation-password-error" }
			};
			this.append(this.label);
			this.append(this.entry);
			this.append(this.error_label);
			this.hold_fill = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				halign = Gtk.Align.START,
				valign = Gtk.Align.FILL,
				hexpand = false,
				vexpand = true,
				width_request = 1,
				visible = false,
				can_target = false,
				css_classes = { "sudo-hold-fill" }
			};
			this.overlay = new Gtk.Overlay();
			this.overlay.set_child(this.allow);
			this.overlay.add_overlay(this.hold_fill);
			this.entry.changed.connect(() => {
				if (this.holding) {
					return;
				}
				this.allow.sensitive = this.entry.get_text().strip() != "";
				this.error_label.visible = false;
			});
			this.entry.activate.connect(() => {
				this.submit();
			});
			var hold_press = new Gtk.GestureClick();
			hold_press.pressed.connect(this.on_hold_pressed);
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
			this.allow.add_controller(hold_press);
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
			this.allow.add_controller(hold_motion);
		}

		/**
		 * Look up a stored secret. If present, {@link check} with hold true.
		 * Otherwise show the type form.
		 */
		public async void prepare()
		{
			this.reset();
			this.allow.remove_css_class("suggested-action");
			this.allow.add_css_class("destructive-action");
			this.allow.label = "Allow (root)";
			this.allow.sensitive = false;
			this.entry.text = "";
			this.error_label.label = "";
			this.error_label.visible = false;
			var stored = "";
			try {
				stored = Secret.password_lookup_sync(this.schema, null,
					"user", GLib.Environment.get_user_name());
			} catch (GLib.Error e) {
				stored = "";
			}
			if (stored == null || stored == "") {
				this.holding = false;
				this.label.visible = true;
				this.entry.visible = true;
				GLib.Idle.add(() => {
					this.entry.grab_focus();
					return false;
				});
				return;
			}
			this.entry.text = stored;
			this.label.visible = false;
			this.entry.visible = false;
			yield this.check(true);
		}

		/**
		 * Hide the password row and cancel a hold in progress.
		 */
		public void reset()
		{
			if (this.hold_timeout_src != 0) {
				GLib.Source.remove(this.hold_timeout_src);
				this.hold_timeout_src = 0;
			}
			this.hold_fill.visible = false;
			this.hold_fill.width_request = 1;
			this.holding = false;
			this.label.visible = false;
			this.entry.visible = false;
			this.error_label.visible = false;
			this.error_label.label = "";
			this.entry.text = "";
			this.allow.remove_css_class("destructive-action");
			this.allow.add_css_class("suggested-action");
			this.allow.label = "Allow";
			this.allow.sensitive = true;
		}

		/**
		 * Typed Allow or Enter. Ignored while a hold is armed.
		 */
		public void submit()
		{
			if (this.holding) {
				return;
			}
			if (this.entry.get_text().strip() == "") {
				return;
			}
			this.allow.sensitive = false;
			this.busy(true);
			this.check.begin(false);
		}

		/**
		 * ''sudo -k'' then ''sudo -S true''.
		 *
		 * @param hold true from {@link prepare}: success arms hold. false from
		 *             {@link submit} / {@link on_hold_tick}: success stores and {@link checked}.
		 */
		private async void check(bool hold)
		{
			var error = "";
			try {
				var proc = new GLib.Subprocess.newv({"sudo", "-k"}, GLib.SubprocessFlags.NONE);
				proc.wait(null);
			} catch (GLib.Error e) {
				error = e.message;
			}
			var ok = false;
			if (error == "") {
				try {
					var proc = new GLib.Subprocess.newv({"sudo", "-S", "true"},
						GLib.SubprocessFlags.STDOUT_PIPE
						| GLib.SubprocessFlags.STDERR_PIPE
						| GLib.SubprocessFlags.STDIN_PIPE);
					var stdin = proc.get_stdin_pipe();
					stdin.write_all((this.entry.get_text() + "\n").data, null);
					stdin.close(null);
					yield proc.wait_async(null);
					ok = proc.get_successful();
				} catch (GLib.Error e) {
					error = e.message;
				}
			}
			if (error == "" && ok && hold) {
				this.holding = true;
				this.label.visible = false;
				this.entry.visible = false;
				this.allow.sensitive = true;
				this.allow.label = "Hold 2s — use saved password";
				return;
			}
			if (error == "" && ok) {
				var password = this.entry.get_text();
				this.store(password);
				this.checked(password);
				return;
			}
			if (error != "") {
				this.error_label.label = error;
			}
			if (error == "") {
				this.error_label.label = "Wrong password. Try again.";
			}
			this.busy(false);
			this.error_label.visible = true;
			this.entry.text = "";
			this.allow.sensitive = false;
			this.holding = false;
			this.label.visible = true;
			this.entry.visible = true;
			this.allow.label = "Allow (root)";
			try {
				Secret.password_clear_sync(this.schema, null,
					"user", GLib.Environment.get_user_name());
			} catch (GLib.Error e) {
			}
			this.entry.grab_focus();
		}

		/**
		 * Store @password in libsecret. Ignores store errors.
		 *
		 * @param password sudo password to save
		 */
		private void store(string password)
		{
			Secret.password_store.begin(this.schema, Secret.COLLECTION_DEFAULT,
				"OLLMchat sudo", password, null, (obj, res) => {
					try {
						Secret.password_store.end(res);
					} catch (GLib.Error e) {
					}
				}, "user", GLib.Environment.get_user_name());
		}

		/**
		 * Arm the two-second fill. No-op when not in hold mode.
		 *
		 * @param n_press unused (Gtk.GestureClick)
		 * @param x unused
		 * @param y unused
		 */
		private void on_hold_pressed(int n_press, double x, double y)
		{
			if (!this.holding) {
				return;
			}
			this.hold_fill.visible = true;
			this.hold_fill.width_request = 1;
			this.hold_start_us = GLib.get_monotonic_time();
			if (this.hold_timeout_src != 0) {
				GLib.Source.remove(this.hold_timeout_src);
			}
			this.hold_timeout_src = GLib.Timeout.add(50, this.on_hold_tick);
		}

		/**
		 * Grow the fill. At two seconds, {@link check} with hold false.
		 *
		 * @return true to keep the timeout
		 */
		private bool on_hold_tick()
		{
			var elapsed_ms = (GLib.get_monotonic_time() - this.hold_start_us) / 1000;
			this.hold_fill.width_request = (int) ((this.allow.get_width() * elapsed_ms) / 2000);
			if (elapsed_ms < 2000) {
				return true;
			}
			this.hold_timeout_src = 0;
			this.hold_fill.visible = false;
			this.hold_fill.width_request = 1;
			this.allow.sensitive = false;
			this.busy(true);
			this.check.begin(false);
			return false;
		}
	}
}
```

### 9. `libollmchatgtk/stub/Sudo.vala` — no-op stub (new file) ✔️

**Why:** `ChatPermission` constructs `Sudo` on every host. Android and Windows never prompt for sudo. Do **not** copy the password form.

**Where:** new file under `stub/` (non-Linux). Not `windows/` — Android compiles this too.

**Depends on:** **### 1**.

#### Add — compile-only API; Allow still packs via overlay

```vala
namespace OLLMchatGtk
{
	/**
	 * Non-Linux stub for {@link Sudo}.
	 *
	 * Same constructor, {@link prepare}, {@link reset}, {@link submit},
	 * {@link overlay}, and signals. Methods are empty. There is no password
	 * row and no sudo. {@link overlay} only re-parents Allow into the
	 * button row.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.sudo = new Sudo(this.allow_once_btn);
	 * this.button_box.append(this.sudo.overlay);
	 * }}}
	 */
	public class Sudo : Gtk.Box
	{
		public signal void checked(string password);
		public signal void busy(bool on);

		public Gtk.Overlay overlay;

		/**
		 * Re-parent Allow into {@link overlay}. No password widgets.
		 *
		 * @param allow the permission Allow button
		 */
		public Sudo(Gtk.Button allow)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, visible: false);
			this.overlay = new Gtk.Overlay();
			this.overlay.set_child(allow);
		}

		/**
		 * No-op. Root prompts do not run on this host.
		 */
		public async void prepare()
		{
		}

		/**
		 * No-op.
		 */
		public void reset()
		{
		}

		/**
		 * No-op.
		 */
		public void submit()
		{
		}
	}
}
```

---

## `ChatPermission.vala` ✔️

`ChatPermission` owns `Sudo`, packs `overlay` in the button row, and resumes on `checked`. No `#if LINUX`. No password widgets. No `validate_elevation_and_resume`.

### 10. `libollmchatgtk/ChatPermission.vala` — drop password fields; own `Sudo` ✔️

**Why:** Permission chrome stays here; sudo UI is the child widget.

**Where:** class fields after `allow_always_btn`; constructor (password widgets → sudo); `request()`; `create_button`; delete `validate_elevation_and_resume`.

**Depends on:** **### 8** / **### 9**.

##### Part 1 — fields

**Where:** replace the password widget fields with `sudo`. After `private Gtk.Button allow_always_btn;`.

#### Remove

```vala
		private Gtk.Label password_label;
		private Gtk.PasswordEntry password_entry;
		private Gtk.Label password_error_label;
		private Gtk.Box button_box;
```

#### Replace with

```vala
		private Gtk.Box button_box;
		private Sudo sudo;
```

##### Part 2 — constructor: build Sudo, pack overlay, connect signals

**Where:** from `this.password_label = new Gtk.Label("Your password (sudo):")` through `this.password_entry.activate.connect`; and the four `button_box.append` lines; `container.append` of password widgets.

#### Remove

```vala
			this.password_label = new Gtk.Label("Your password (sudo):") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4
			};
			this.password_entry = new Gtk.PasswordEntry() {
				hexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 4
			};
			this.password_entry.add_css_class("elevation-password-entry");
			this.password_error_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				margin_start = 12,
				margin_end = 12,
				margin_bottom = 8,
				wrap = true
			};
			this.password_error_label.add_css_class("elevation-password-error");
			
			// Create button row
```

#### Replace with

```vala
			// Create button row
```

#### Remove

```vala
			this.button_box.append(this.deny_always_btn);
			this.button_box.append(this.deny_once_btn);
			this.button_box.append(this.allow_once_btn);
			this.button_box.append(this.allow_always_btn);
```

#### Replace with

```vala
			this.sudo = new Sudo(this.allow_once_btn);
			this.sudo.checked.connect((password) => {
				this.pending_elevation_password = password;
				this.pending_response = OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE;
				if (this.resume_callback != null) {
					this.resume_callback();
				}
			});
			this.sudo.busy.connect((on) => {
				this.deny_once_btn.sensitive = !on;
				this.deny_always_btn.sensitive = !on && this.deny_always_btn.visible;
				this.allow_always_btn.sensitive = !on && this.allow_always_btn.visible;
			});
			this.button_box.append(this.deny_always_btn);
			this.button_box.append(this.deny_once_btn);
			this.button_box.append(this.sudo.overlay);
			this.button_box.append(this.allow_always_btn);
```

#### Remove

```vala
			container.append(this.command_label);
			container.append(this.question_label);
			container.append(this.password_label);
			container.append(this.password_entry);
			container.append(this.password_error_label);
			container.append(this.button_box);
```

#### Replace with

```vala
			container.append(this.command_label);
			container.append(this.question_label);
			container.append(this.sudo);
			container.append(this.button_box);
```

#### Remove

```vala
			this.password_label.set_visible(false);
			this.password_entry.set_visible(false);
			this.password_error_label.set_visible(false);
			this.set_visible(false);

			this.password_entry.changed.connect(() => {
				if (this.pending_high_risk) {
					this.allow_once_btn.sensitive = this.password_entry.get_text().strip() != "";
				}
				this.password_error_label.set_visible(false);
			});
			this.password_entry.activate.connect(() => {
				if (!this.pending_high_risk) {
					return;
				}
				if (!this.allow_once_btn.sensitive) {
					return;
				}
				this.validate_elevation_and_resume.begin(
					OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE);
			});
```

#### Replace with

```vala
			this.set_visible(false);
```

##### Part 3 — `request()`: `prepare()` / `reset()` instead of password widgets

**Where:** from `this.password_label.set_visible(high_risk);` through the high-risk `GLib.Idle.add`; and the post-yield password cleanup.

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
			if (high_risk) {
				this.add_css_class("high-risk");
				this.sudo.prepare.begin();
			}
			if (!high_risk) {
				this.remove_css_class("high-risk");
				this.sudo.reset();
			}
			
			// Show the widget
			this.set_visible(true);
```

#### Remove

```vala
			this.allow_once_btn.label = "Allow";
			this.allow_once_btn.sensitive = true;
			this.password_label.set_visible(false);
			this.password_entry.set_visible(false);
			this.password_error_label.set_visible(false);
			this.password_error_label.label = "";
			this.password_entry.text = "";
			this.pending_high_risk = false;
```

#### Replace with

```vala
			this.sudo.reset();
			this.pending_high_risk = false;
```

##### Part 4 — `create_button`: `submit()` instead of `validate_elevation_and_resume`

**Where:** `clicked` handler, `ALLOW_ONCE` / `ALLOW_ALWAYS` arm.

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
							this.sudo.submit();
							break;
						}
```

##### Part 5 — delete `validate_elevation_and_resume` from ChatPermission

**Where:** the whole private method (now `Sudo.check` on Linux).

#### Remove

```vala
		/**
		 * Verifies the sudo password with {@literal sudo -S true} before resuming
		 * the permission prompt. Wrong passwords stay in the dialog; the LLM never
		 * sees authentication failure.
		 */
		private async void validate_elevation_and_resume(
			OLLMchat.ChatPermission.PermissionResponse response)
		{
			this.allow_once_btn.sensitive = false;
			this.deny_once_btn.sensitive = false;
			this.deny_always_btn.sensitive = false;
			this.allow_always_btn.sensitive = false;

			var password = this.password_entry.get_text();
			var ok = false;
#if !G_OS_WIN32
			if (GLib.Environment.find_program_in_path ("sudo") != null) {
				try {
					var klauncher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.NONE);
					var kproc = klauncher.spawnv ({"sudo", "-k"});
					kproc.wait (null);
					var flags = GLib.SubprocessFlags.STDOUT_PIPE
						| GLib.SubprocessFlags.STDERR_PIPE
						| GLib.SubprocessFlags.STDIN_PIPE;
					var launcher = new GLib.SubprocessLauncher (flags);
					var proc = launcher.spawnv ({"sudo", "-S", "true"});
					var stdin = proc.get_stdin_pipe ();
					stdin.write_all ((password + "\n").data, null);
					stdin.close (null);
					yield proc.wait_async (null);
					ok = proc.get_successful ();
				} catch (GLib.Error e) {
					ok = false;
				}
			}
#endif
			this.deny_once_btn.sensitive = true;
			this.deny_always_btn.sensitive = this.deny_always_btn.visible;
			this.allow_always_btn.sensitive = this.allow_always_btn.visible;

			if (!ok) {
				this.password_error_label.label = "Wrong password. Try again.";
				this.password_error_label.set_visible(true);
				this.password_entry.text = "";
				this.allow_once_btn.sensitive = false;
				this.password_entry.grab_focus();
				return;
			}

			this.pending_elevation_password = password;
			this.pending_response = response;
			if (this.resume_callback != null) {
				this.resume_callback();
			}
		}
		
```

---

## Copy that currently says the password is not saved ✔️

- **💩** `✔️` User-facing root copy still says the password is not saved. Wording below is a proposal.

### 11. `liboctools/RunCommand/Request.vala` — `build_perm_question()` root copy ✔️

**Where:** last sentence of `this.permission_question` when `this.run_as_root`.

#### Remove

```vala
					+ "Enter your password below. It is used only for this command and is not saved.";
```

#### Replace with

```vala
					+ "If asked, enter your password. After a successful check it is stored in the system keyring.";
```

### 12. `liboctools/RunCommand/Tool.vala` — Root Access bullet ✔️

**Where:** `description` help text, bullet under `Root Access (Linux GTK app only):`.

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

- **🚫** Do not add a `Use a different password` control.
- **🚫** Do not put a password form in `stub/Sudo.vala`. Stub is overlay + empty methods only.
- **🚫** Do not put `#if LINUX` in `ChatPermission` for sudo. That is the stub’s job.
- **🚫** Do not `dependency('libsecret-1')` on Windows or Android meson.
- **🚫** Do not add `libsecret-1-dev` to Android host apt or R17.
- **🚫** Do not make Allow-Always remember root commands (still `one_time_only`).
- **🚫** Do not put libsecret in `liboctools`.
- **🚫** Do not treat a single click as “use saved password”.
- **🚫** Do not register `run_command` on Android in this plan.
- **🚫** Do not implement VTE — that is **2.6.6**.
- **🚫** Do not `yield Secret.password_store(...)`.
- **🚫** Do not add a `Check` class (nested or otherwise). `check(bool hold)` is a private method on `Sudo`.
- **ℹ️** `busy` is so Deny stays disabled during `check(false)` without `Sudo` pointing at `ChatPermission`.
- **🚫** Do not `find_program_in_path("sudo")`. Spawn failure is `e.message`, not “Wrong password.”
- **🚫** Do not name subprocess locals `klauncher` / `kproc`.
- **🚫** Do not arm hold in `prepare()` before `check(true)` succeeds.
