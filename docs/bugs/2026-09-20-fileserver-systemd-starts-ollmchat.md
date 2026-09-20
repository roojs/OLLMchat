# systemd File Server starts ollmchat, not ollmfilesd

**Status:** ✔️ ExecStart + no GUI `INVOCATION_ID` skip + `OLLMFILESD_DAEMON=1` — await user verify  
**Hit:** 2026-09-20 — Connections → File Server → systemd on  
**Component:** `libollmchat/Settings/Filesd.vala`

---

## Problem

🔷 Toggle systemd on. Toast: file server did not stay up. systemd shows it is starting **ollmchat**, not the file daemon.

**Expected:** user unit runs `/usr/bin/ollmfilesd`.

**Actual:** `ExecStart=/usr/bin/ollmchat`.

---

## Evidence

- ✔️ `~/.config/systemd/user/ollmfilesd.service` `ExecStart=/usr/bin/ollmchat` (written 10:44 when Settings called `install()`).
- ✔️ `/usr/bin/ollmfilesd` exists (installed 11:09). Unit does not point at it.
- ℹ️ `Filesd.install()` used `readlink("/proc/self/exe")`. The GUI is that process.
- ℹ️ `ollmfilesd/Application.vala` also calls `install()` on start — there `/proc/self/exe` would be the daemon. The Settings handoff runs `install()` first from ollmchat and writes the wrong unit.
- ℹ️ Manual spawn (`ClientBoot`) already uses `OLLM_OLLMFILESD` or PATH `ollmfilesd`. The unit must not copy the GUI path, and must not bake the meson build-tree env into systemd.

---

## Root cause

✔️ `install()` wrote `ExecStart=` of whatever binary called it. Settings → ollmchat.

---

## Proposed fix

🔷 `ExecStart` = `GLib.Environment.find_program_in_path("ollmfilesd")`, fallback `ollmfilesd`. Do **not** use `/proc/self/exe`. Do **not** use `OLLM_OLLMFILESD` (that is the build wrapper for manual spawn only).

### `libollmchat/Settings/Filesd.vala` `install()`

#### Remove

```vala
			var exe_buf = new char[4096];
			var exe_len = Posix.readlink("/proc/self/exe", exe_buf);
			var exe = exe_len > 0
				? ((string)exe_buf).substring(0, (int)exe_len)
				: "ollmfilesd";
```

#### Replace with

```vala
			var exe = GLib.Environment.find_program_in_path("ollmfilesd");
			if (exe == null || exe == "") {
				exe = "ollmfilesd";
			}
```

- 🔷 2026-09-20: still did not stay up after ExecStart fix.

✔️ ollmchat PID has `INVOCATION_ID` (GNOME launched the GUI). `install()` treated that as “already the systemd daemon” and skipped `enable --now`. Unit stayed **disabled**.

✔️ `systemctl --user enable --now` from the shell: Active 40ms, `ExecStart` exited 0. `ollmfilesd` **double-forks** unless `OLLMFILESD_DAEMON=1`. `Type=simple` sees the parent exit and tears down the cgroup (child never keeps the socket).

### Stay-up

#### Unit `[Service]`

#### Add

`Environment=OLLMFILESD_DAEMON=1` so the process stays in the foreground.

#### `install()` skip `enable --now`

#### Remove

Skip when `INVOCATION_ID` is set (true for the GUI).

#### Replace with

Skip only when `/proc/self/exe` basename is `ollmfilesd`.

---

## Next

- 🔷 Toggle systemd off then on. Confirm `is-active` stays `active`, socket exists, no “did not stay up”.
