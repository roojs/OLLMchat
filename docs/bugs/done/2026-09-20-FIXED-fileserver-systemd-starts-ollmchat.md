# systemd File Server starts ollmchat, not ollmfilesd

**Status:** ✅ FIXED — user archived 2026-09-20  
**Hit:** 2026-09-20 — Connections → File Server → systemd on  
**Component:** `libollmchat/Settings/Filesd.vala`

---

## Problem

🔷 Toggle systemd on. Toast: file server did not stay up. The user unit started **ollmchat**, not the file daemon.

**Expected:** `ExecStart=/usr/bin/ollmfilesd`, unit stays `active`, Unix socket up.

---

## Root cause

Three stacked misses:

1. ✔️ `Filesd.install()` wrote `ExecStart=` from `/proc/self/exe`. Settings runs inside **ollmchat**, so the unit launched the GUI.
2. ✔️ After ExecStart pointed at `ollmfilesd`, `install()` still skipped `enable --now` whenever `INVOCATION_ID` was set. GNOME sets that on the GUI, so the unit stayed **disabled**.
3. ✔️ `ollmfilesd` double-forks unless `OLLMFILESD_DAEMON=1`. `Type=simple` saw the parent exit (Duration ~40ms) and tore down the cgroup.

🚫 Do not bake `OLLM_OLLMFILESD` (meson build wrapper) into the unit. Manual spawn may use it; systemd must use PATH `ollmfilesd`.

---

## Landed

- ✔️ `ExecStart` = `GLib.Environment.find_program_in_path("ollmfilesd")`, fallback `ollmfilesd`.
- ✔️ Skip `enable --now` only when `GLib.Path.get_basename(GLib.FileUtils.read_link("/proc/self/exe")) == "ollmfilesd"` (not `INVOCATION_ID`).
- ✔️ Unit `[Service]` `Environment=OLLMFILESD_DAEMON=1`.
