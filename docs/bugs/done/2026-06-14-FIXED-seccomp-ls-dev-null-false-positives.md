# Seccomp false positives: ls redirect to /dev/null and failed commands

**Status:** FIXED (2026-06-14)

**Started:** 2026-06-14

---

## Problem

A benign demo command such as `ls > /dev/null` (often via `bash -c '…'`) appended seccomp fs evidence listing `/dev/tty`, suggesting the model needed `allow_write` when it did not.

Failed commands (e.g. `false`, bad redirects) could also append a network appendix (`socket (2×)`) from local `AF_UNIX` socket use, not actual network access.

**Expected:** No fs or network appendix for harmless read-only commands with output discarded to `/dev/null`.

**Actual:** `/dev/tty` in fs appendix (bash TTY probe on redirect); `socket (2×)` on some failing runs.

---

## Root cause

1. **bash** calls `openat("/dev/tty", O_RDWR)` before applying the redirect; seccomp NOTIFY records any write-mode open outside `can_write`, including terminal probes that `allow_write` cannot grant.
2. **`socket()`** NOTIFY counted all domains, including `AF_UNIX` used by shells internally — surfaced on the failure output path together with fs appendices.

---

## Fix

- `Bubble.is_reportable_blocked_write()` — omit `/dev/null`, `dev/null`, `/dev/tty`, `/dev/ptmx`, `/dev/pts/*` from fs evidence.
- `RunSeccomp` — only count `socket()` when domain is `AF_INET` or `AF_INET6`.
- Tests: `tests/test-bubble-5.sh`.

---

## Verification

```bash
meson compile -C build
build/examples/oc-test-bubble --project=. --expect=no-fs "/bin/bash -c 'ls > /dev/null'"
build/examples/oc-test-bubble --project=. --expect=no-net "false"
bash tests/test-bubble-5.sh build
```
