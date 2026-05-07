# FIXED: `run_command` — bubblewrap path hangs with no stdout in UI

**Status: FIXED** (2026-04-28)

## Problem

When the agent runs **`run_command`** and **`Bubble.can_wrap()`** is true, the app could appear stuck after **`running command:`** (full **`bwrap`** line in logs): **no execution results**, **no further debug**, **`spawnv`** never returning from the caller’s perspective.

## Root cause

**Spawn-time deadlock in `RunSeccomp` handshake.** The child **`child_setup`** path passed the seccomp notify FD then **blocked on `read(sock)`** waiting for a sync byte. The parent only sent that byte in **`finish_handshake()`**, which runs **after** **`SubprocessLauncher.spawnv()`** returns. GLib’s spawn path can wait for child setup to complete before returning to the parent, so child blocks on read while parent is still inside **`spawnv`** — neither side can proceed.

## Fix

**`liboctools/RunCommand/RunSeccomp.vala`:** Remove the round-trip sync. After **`pass_unix_fd`**, the child **closes the socket and returns** (no wait for parent). **`finish_handshake()`** only **`receive_unix_fd`** and closes the parent end — **no** **`write(..., 'S')`**.

## Verification

Manual **`run_command`** under **`bwrap`** (e.g. shell pipelines, **`php -r`**) completes; UI shows execution results and the app no longer blocks inside **`spawnv`**.

---

## Historical notes (pre-fix)

### Hypotheses that were secondary

1. Stdout pipe fill / **`IOChannel.read_line`** — possible for other stalls **after** **`spawnv`** returns; not the primary cause for “hang immediately after **`running command:`**”.
2. Main-loop / **`wait_async`** — same.
3. Seccomp notify backlog on **`openat`** — different failure mode.

### GDB

Backtrace showed **`g_subprocess_launcher_spawnv`** / **`__libc_read`** — consistent with **blocked inside spawn**, matching the handshake deadlock.

### Affected code (reference)

- **`Bubble.exec()`** — **`spawnv`**, then **`read_subprocess_output`**.
- **`RunSeccomp`** — **`wire_launcher`**, **`child_seccomp_handshake`**, **`finish_handshake`**.

### Follow-up (optional hardening)

If long-line / no-newline output ever causes pipe stalls **after** spawn, consider byte-oriented reads for stdio (separate from this fix).
