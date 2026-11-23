# `Client.disconnect()` no-op leaves transport after `connected` is false

**Status:** ✅ 2026-11-23. User closed.

**Pointer:** `docs/bug-fix-process.md`, `libocrpc/Client.vala`

ℹ️ Filed from Argus Android offline-reconnect work.
ℹ️ Argus log: `/home/alan/gitlive/argusrm/docs/bugs/2026-11-22-android-controller-offline-reconnect.md`, `/home/alan/gitlive/argusrm/docs/bugs/2026-11-22-android-debpackages-disconnect.md`.

---

## Problem

- 🔷 After a protocol parse error or failed `connect`, `OLLMrpc.Client.connected` is **false** but a half-open **socket**, **read watch**, or **Bin.Stream** may still exist.
- 🔷 **Expected:** `disconnect()` always releases transport and clears pending state so a later `connect(hello)` starts on a clean TLS/TCP session.
- 🔷 **Actual:** `disconnect()` returns immediately when `!connected`, so **no** socket/watch/bin teardown runs.

---

## Evidence

- ✔️ `libocrpc/Client.vala` (`disconnect`, ~516–520): `if (!this.connected) return;`
- ✔️ Parse/HUP paths call `disconnect()` while `connected` is still true — those paths clean up. A **later** `disconnect()` from the app is then a no-op.
- ✔️ Failed `connect()` after `this.socket` is set but before `this.connected = true` (e.g. TLS handshake error) may leave `socket` set with `connected == false`.

---

## Root cause

- ✔️ `disconnect()` treats `connected` as the only guard for teardown. Transport lifetime is not tied to that flag alone.

---

## Proposed fix (**minor**)

**Where:** `libocrpc/Client.vala` `disconnect()`.

```vala
if (!this.connected
    && this.socket == null
    && this.read_watch_id == 0
    && this.bin == null) {
    return;
}
```

Run the existing teardown body (set `connected` false, clear pending, close socket, etc.).

---

## Attempts / changelog

- ⏳ 2026-11-22: described from Argus; not applied in OLLMchat yet.
- ✔️ 2026-11-22: `libocrpc/Client.vala` `disconnect()` — early return only when already fully idle (`!connected` and no socket, read watch, or bin); otherwise run full teardown.
- ✔️ 2026-11-22: release notes — `CHANGELOG.md` **1.4.16** (Fixed · libocrpc); **1.4.15** already tagged 2026-11-21.

---

## Next

- ✅ 2026-11-23 — User confirmed done; archived.