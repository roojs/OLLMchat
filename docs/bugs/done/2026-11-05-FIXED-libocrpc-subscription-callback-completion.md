# Stock callback reply cannot complete a blocking subscription

**Status:** ✔️ fixed; native regression and consumer gate pass

## Problem

- 🔷 `OLLMrpc.Live.Callback.reply` must complete the waiter created by a
  blocking `OLLMrpc.Live.Subscription`.
- ✔️ Before the fix, a typed callback reply containing `uint` value `7` was
  rejected, and the original signal call timed out instead of returning `7`.
- ℹ️ The current reproduction is
  `/home/alan/gitlive/gnome-shell-rpc/tests/call-sync-repro/subscription-stock-callback-reply-gate.vala`.
- ℹ️ Run it from `gnome-shell-rpc` with:

```bash
meson compile -C build subscription-stock-callback-reply-gate
timeout 5 ./build/tests/call-sync-repro/subscription-stock-callback-reply-gate
```

## Evidence

- ✔️ On 2026-11-05 the gate compiled and failed with:

```text
WARNING: RPC-Live-Callback.reply id=4:
WARNING: call timed out Gate.fire id=3 after 2 s
FAIL subscription-stock-callback-reply-gate: returned=0 callback-error= outer-error=call timed out
```

- ✔️ The gate uses stock `OLLMrpc.Live.Callback`, a real blocking
  `OLLMrpc.Live.Subscription`, and a remote `uint` reply of `7`.
- ✔️ The consumer replacement callback service completes the same operation.
- ✔️ Replacing the native test's direct waiter mutation with stock
  `Callback.reply` produced `counted return mismatch` before the fix.
- ℹ️ `test-rpc-subscribe` reports thrown test failures but exits `0`, so its
  executable output—not Meson's status—is the reliable failure signal.

## Root cause

- ✔️ `Subscription.emit` creates a `Hook` waiter in
  `Transport.Connection.callbacks`, stores the correlation in the row-wide
  `reply_id`, and waits for `replied`.
- ✔️ `Callback.reply` only calls `Hook.complete(correlation, values)`.
- ✔️ `Hook.complete` searches nested emit frames. The subscription waiter has
  no frame, so the reply is rejected as invalid.

## Proposed fix

- 🔷 Move callback completion to the connection that owns the callback
  registry. The operation completes either a `Hook.emit` correlation frame or
  the row-wide waiter currently created by `Subscription.emit`.
- 🔷 Make stock `Callback.reply` use that operation.
- 🚫 Do not require consumers to duplicate knowledge of callback registry
  internals.

### `libocrpc/Transport/Connection.vala`

#### Add

```vala
/**
 * Complete the callback wait identified by ''correlation''.
 *
 * Nested {@link Live.Hook.emit} calls own correlation frames. Blocking
 * {@link Live.Subscription} signals use the hook row itself as their waiter.
 *
 * @param correlation reply id sent to the peer
 * @param args values returned by the peer
 * @return true when a callback wait accepted the reply
 */
public bool complete_callback(
	int correlation,
	Gee.ArrayList<GLib.Value?> args
) {
	foreach (var id in this.callbacks.keys) {
		var row = this.callbacks.get(id);
		if (row.complete(correlation, args)) {
			return true;
		}
		if (row.reply_id != correlation) {
			continue;
		}
		row.reply_args.clear();
		foreach (var arg in args) {
			row.reply_args.add(arg);
		}
		row.replied = true;
		return true;
	}
	return false;
}
```

### `libocrpc/Live/Callback.vala`

#### Remove

```vala
foreach (var id in request.connection.callbacks.keys) {
	var row = request.connection.callbacks.get(id);
	if (!row.complete(correlation, values)) {
		continue;
	}
	request.reply(new Response());
	return;
}
```

#### Replace with

```vala
if (request.connection.complete_callback(correlation, values)) {
	request.reply(new Response());
	return;
}
```

### `tests/rpc/subscribe-test.vala`

#### Remove

```vala
if (this.reply_uint) {
	var reply = GLib.Value(typeof(uint));
	reply.set_uint(7);
	this.callbacks.get(this.next_handle - 2).reply_args.add(reply);
}
this.callbacks.get(this.next_handle - 2).replied = true;
```

#### Replace with

```vala
var request = new OLLMrpc.Request() {
	method = "RPC-Live-Callback.reply",
	args = OLLMrpc.args("t", (uint64) this.last.reply_id),
	connection = this
};
if (this.reply_uint) {
	var reply = GLib.Value(typeof(uint));
	reply.set_uint(7);
	request.args.add(reply);
}
request.dispatch();
```

#### Add

```vala
OLLMrpc.Live.Callback.rpc_register();
OLLMrpc.Request.register_live(
	"RPC-Live-Callback", new OLLMrpc.Live.Callback());
```

## Attempts / changelog

- ✔️ 2026-11-05 17:33 HKT: added the consumer integration gate and reproduced
  the timeout without replacing stock `Callback.reply`.
- ✔️ 2026-11-05 18:12 HKT: rebuilt and reran the gate; it still failed with
  `returned=0` and `outer-error=call timed out`.
- ✔️ 2026-11-05 18:15 HKT: moved the owning bug record to the OLLMchat/libocrpc
  project.
- ✔️ 2026-11-05 18:27 HKT: changed the native subscription test to send a
  typed `uint` through stock `Callback.reply`; it reproduced `counted return
  mismatch`.
- ✔️ 2026-11-05 18:31 HKT: added
  `Transport.Connection.complete_callback` and routed `Callback.reply`
  through it.
- ✔️ 2026-11-05 18:34 HKT: rebuilt and ran the native subscription test; it
  completed without failure output.
- ✔️ 2026-11-05 18:36 HKT: rebuilt and ran the consumer gate against the
  OLLMchat build tree; it passed with `returned 7`.

## Next

- ✔️ Fix implemented and regression verified.
