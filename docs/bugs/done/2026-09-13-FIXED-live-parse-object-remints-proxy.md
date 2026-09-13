# Live `parse_object`: remints proxy every decode (breaks object identity)

**Status:** ✔️ FIXED — `proxy-reuse-gate` PASS  
**Hit:** 2026-09-13  
**Component:** `libocrpc/Bin/Stream.vala` — `parse_object` live-handle path  
**Consumer:** gnome-shell-rpc (messageList Cover/Header `===` CRITICALS)  
**Consumer gate:** [`gnome-shell-rpc/tests/call-sync-repro/proxy-reuse-gate`](file:///home/alan/git/gnome-shell-rpc/tests/call-sync-repro/proxy-reuse-gate.vala) — **PASS**  
**Consumer note:** [`gnome-shell-rpc/docs/bugs/2026-09-13-messagelist-cover-header-stack-critical.md`](file:///home/alan/git/gnome-shell-rpc/docs/bugs/2026-09-13-messagelist-cover-header-stack-critical.md)

**🚫** Do not “fix” in the consumer only and close this — consumer has a
workaround (`Runtime.register_handle`); OPC must still reuse `proxies`.

---

## Problem

🔷 With `live_handles`, decoding the **same lease id** twice must return the
**same** `GLib.Object` (pointer equality). Today `parse_object` always:

```vala
var live = GLib.Object.new(decode_type, "rpc-lid", handle);
this.client.proxies.set((int) handle, live);
return live;
```

No `proxies.has_key` check → every wire sighting mints a new proxy and
**overwrites** `Client.proxies`.

Consumers that keep a create-time reference (or GJS `===`) then see two
wrappers for one remote peer → wrong identity, lost per-instance state
(ThemeContext theme map was the same class of hole).

---

## Evidence

### Gate FAIL (2026-09-13)

From gnome-shell-rpc (links libocrpc):

```bash
cd /home/alan/git/gnome-shell-rpc
meson compile -C build proxy-reuse-gate
timeout 5 ./build/tests/call-sync-repro/proxy-reuse-gate
```

```text
FAIL proxy-reuse-gate: decode reminted — OPC parse_object must reuse proxies
# exit 1
```

Shape: server `export`s a `Live.Handle` peer → client decodes it on
`Gate.make` → decodes the **same** lid again on `Gate.get_peer` →
`a != b`.

### Site

`libocrpc/Bin/Stream.vala` ~276–283 (live branch of `parse_object`).

`Client.proxies` docs say the map is the handle→proxy table; notify path
already uses `proxies.has_key` — decode does not.

---

## Minimal repro (same shape as the gate)

Two processes, `live_handles = true`. Server:

```vala
class Peer : Object, OLLMrpc.Live.Handle {
	public uint64 rpc_lid { get; set construct; default = 0; }
}

class Gate : Object {
	public Peer? peer;

	public void make(OLLMrpc.Request request) {
		this.peer = new Peer();
		request.connection.export(this.peer);
		request.reply(new OLLMrpc.Response() {
			id = request.id,
			retval = OLLMrpc.val("o", this.peer),
		});
	}

	public void get_peer(OLLMrpc.Request request) {
		request.reply(new OLLMrpc.Response() {
			id = request.id,
			retval = OLLMrpc.val("o", this.peer),
		});
	}
}
```

Client:

```vala
var a = client.call_poll(new OLLMrpc.Request() { method = "Gate.make" })
	.retval.get_object();
var b = client.call_poll(new OLLMrpc.Request() { method = "Gate.get_peer" })
	.retval.get_object();
assert(a == b);  // FAILS today — two proxies, one lid
```

Full harness: consumer `proxy-reuse-gate.vala` (spawn server, hello, assert).

---

## Root cause

✔️ Live decode always `Object.new` + `proxies.set`, never return existing
entry. Identity is not preserved across replies that re-export the same
lease.

---

## Proposed fix

🔷 In `parse_object` live branch, **before** `Object.new`:

#### Replace with

```vala
var id = (int) handle;
if (this.client.proxies.has_key(id)) {
	return this.client.proxies.get(id);
}
var live = GLib.Object.new(decode_type, "rpc-lid", handle);
this.client.proxies.set(id, live);
return live;
```

**Done when:** `proxy-reuse-gate` prints `PASS` / exit 0.

**ℹ️** First sighting still mints. Create-time proxies the app inserts into
`proxies` before any decode must win (same `has_key` path).

🚫 Do not invent a second identity map inside OPC. 🚫 Do not change wire
format.

---

## Attempts / changelog

- ✔️ `libocrpc/Bin/Stream.vala` — live `parse_object` reuses `Client.proxies`
  when the lease id is already known; docblock notes reuse.
- ✔️ Gate: `PASS proxy-reuse-gate: same object` / exit 0 (2026-09-13).
