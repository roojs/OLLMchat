# `call_sync` nested wait hangs: single IO watch cannot re-enter dispatch

**Status:** ✔️ applied — await consumer verify  
**Hit:** 2026-09-09 / 2026-09-10 — gnome-shell-rpc nested Wayland (`remove_child` 120s timeout)  
**Component:** `libocrpc` / `Client.call_sync` wait loop & IO watch lifecycle  
**Consumer:** gnome-shell-rpc layout relay `Live.Invoke` → `RPC-Live-Callback.reply`  
**Related:**  
- `2026-09-09-call-sync-pending-head-blocks-nested.md` (write first unsent — fixed)  
- `done/2026-09-09-FIXED-call-sync-mid-wait-live-invoke-flow.md` (same-context nested wait)  

---

## Symptom

Consumer is in an outer `call_sync` (e.g. `id=44`, `Clutter-Actor.remove_child`).
During the request, server emits a `Live.Invoke` callback (layout allocate).
The client’s `on_read` receives the invoke and dispatches it to the consumer handler, which initiates a nested `call_sync` (`id=45`, `RPC-Live-Callback.reply`).

The nested request `id=45` is transmitted immediately to the server.
The server receives `id=45` and replies with `Response(id=45)` within microseconds.

**However, the client never reads or dispatches `Response(id=45)`.**
The nested `call_sync` sits inside `sync_loop.run()` until the 120s call timeout of `id=44` expires:

```text
23:40:40.366260: Client: id=44 method=Clutter-Actor.remove_child
23:40:40.366442: Server: recv id=44 method=Clutter-Actor.remove_child
23:40:40.366587: Client: id=45 method=RPC-Live-Callback.reply
23:40:40.366722: Server: recv id=45 method=RPC-Live-Callback.reply
... 120s total silence ...
23:42:40.726631: Client: call timed out Clutter-Actor.remove_child id=44 after 120 s
```

---

## Root Cause

### 1. GLib `G_HOOK_FLAG_IN_CALL` blocks recursive `GSource` dispatch

In `libocrpc/Client.vala` (`call_sync`), a single `sync_watch` is attached only when `outer == true`:

```vala
var outer = (this.sync_loop == null);
GLib.IOSource? sync_watch = null;
if (outer) {
    this.sync_loop = new GLib.MainLoop(new GLib.MainContext(), false);
    sync_watch = this.read_channel.create_watch(
        GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
    );
    sync_watch.set_callback(this.on_read);
    sync_watch.attach(this.sync_loop.get_context());
}
```

When `Live.Invoke` arrives, GLib’s main context invokes `sync_watch`'s callback (`this.on_read`).
Inside GLib (`gmain.c`, `g_main_dispatch`):
```c
was_in_call = source->flags & G_HOOK_FLAG_IN_CALL;
source->flags |= G_HOOK_FLAG_IN_CALL;

if (!was_in_call)
    dispatch = source->source_funcs->dispatch;
else
    dispatch = NULL;
```

While `sync_watch` is in the middle of executing `this.on_read`:
1. The consumer’s invoke handler synchronously invokes nested `call_sync`.
2. Because `outer == false`, no new `sync_watch` is created.
3. Nested `call_sync` calls `this.sync_loop.run()`.
4. The server sends `Response(id=45)`. The socket file descriptor becomes readable (`POLLIN`).
5. `g_main_context_iterate()` polls the descriptor, finds it ready, and attempts to dispatch `sync_watch`.
6. But `sync_watch` has `G_HOOK_FLAG_IN_CALL` set because it is **already on the call stack running `this.on_read`**!
7. GLib observes `was_in_call == true`, sets `dispatch = NULL`, and skips `sync_watch`.

**Result:** The incoming `Response(id=45)` is never read off the socket by the nested loop. It sits in the OS socket buffer until timeout aborts the call.

### 2. Shared `sync_loop` instance prevents independent frame unblocking

`this.sync_loop` is currently a single field shared across outer and nested frames.
In GLib, `g_main_loop_quit()` sets `loop->is_running = FALSE`. Reusing the same `MainLoop` instance across nested levels causes quitting the nested wait to also terminate or corrupt the running state of the outer wait.

---

## Solution

1. Maintain `private GLib.MainContext? sync_context` for the session (created by outer, cleared when outer exits).
2. **Every frame (outer and nested)** creates its own `sync_watch` attached to `this.sync_context`, and destroys it in `finally`.
   - Because each nested level has its own distinct `GSource` instance, its `G_HOOK_FLAG_IN_CALL` is false, and GLib dispatches it immediately when data arrives.
3. **Every frame** creates its own `my_loop = new GLib.MainLoop(this.sync_context, false)`.
   - `this.sync_loop` tracks the innermost loop: `var saved_loop = this.sync_loop; this.sync_loop = my_loop;`.
   - In `finally`, `this.sync_loop = saved_loop;`.
   - When `complete_pending` calls `this.sync_loop.quit()`, only the active nested loop unblocks.
4. **Every frame** attaches its own `TimeoutSource` to `this.sync_context` (when `call_timeout_seconds > 0`), ensuring nested calls also have appropriate timeouts instead of inheriting the outer call's timer.

---

## Proposed Changes to `libocrpc/Client.vala`

### 1. Fields in `libocrpc/Client.vala`

```diff
 		private GLib.IOChannel? read_channel;
 		private uint read_watch_id = 0;
+		/** Private context shared across outer and nested {@link call_sync} frames. */
+		private GLib.MainContext? sync_context;
 		/** Non-null while {@link call_sync} runs a private {@link GLib.MainLoop}. */
 		private GLib.MainLoop? sync_loop;
 		/** Nesting depth of {@link call_sync} on {@link sync_loop} (0 = idle). */
 		private int sync_depth = 0;
```

### 2. `call_sync` implementation in `libocrpc/Client.vala`

```diff
 			var entry = new PendingWrite(request);
 			this.pending.add(entry);
 
-			var outer = (this.sync_loop == null);
-			GLib.IOSource? sync_watch = null;
-			GLib.Source? timeout_source = null;
+			var outer = (this.sync_context == null);
 			if (outer) {
 				if (this.read_watch_id != 0) {
 					GLib.Source.remove(this.read_watch_id);
 					this.read_watch_id = 0;
 				}
-				this.sync_loop = new GLib.MainLoop(new GLib.MainContext(), false);
-				sync_watch = this.read_channel.create_watch(
-					GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
-				);
-				sync_watch.set_callback(this.on_read);
-				sync_watch.attach(this.sync_loop.get_context());
-				if (this.call_timeout_seconds > 0) {
-					timeout_source = new GLib.TimeoutSource.seconds(this.call_timeout_seconds);
-					timeout_source.set_callback(() => {
-						GLib.warning("call timed out %s id=%d after %u s",
-							entry.request.method, entry.request.id, this.call_timeout_seconds);
-						this.complete_pending(
-							entry.request.id, null, new GLib.IOError.TIMED_OUT("call timed out"));
-						return false;
-					});
-					timeout_source.attach(this.sync_loop.get_context());
-				}
+				this.sync_context = new GLib.MainContext();
 			}
+
+			var saved_loop = this.sync_loop;
+			var my_loop = new GLib.MainLoop(this.sync_context, false);
+			this.sync_loop = my_loop;
+
+			var sync_watch = this.read_channel.create_watch(
+				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
+			);
+			sync_watch.set_callback(this.on_read);
+			sync_watch.attach(this.sync_context);
+
+			GLib.Source? timeout_source = null;
+			if (this.call_timeout_seconds > 0) {
+				timeout_source = new GLib.TimeoutSource.seconds(this.call_timeout_seconds);
+				timeout_source.set_callback(() => {
+					GLib.warning("call timed out %s id=%d after %u s",
+						entry.request.method, entry.request.id, this.call_timeout_seconds);
+					this.complete_pending(
+						entry.request.id, null, new GLib.IOError.TIMED_OUT("call timed out"));
+					return false;
+				});
+				timeout_source.attach(this.sync_context);
+			}
+
 			this.sync_depth++;
 			try {
 				while (entry.done_response == null) {
 					if (!this.sending && this.pending.size > 0) {
 						var sent_one = false;
 						for (var i = 0; i < this.pending.size; i++) {
 							var p = this.pending.get(i);
 							if (p.sent) {
 								continue;
 							}
 							this.sending = true;
 							GLib.debug("id=%d method=%s", p.request.id, p.request.method);
 							this.bin.write(p.request);
 							this.output.flush(null);
 							p.sent = true;
 							this.sending = false;
 							sent_one = true;
 							break;
 						}
 						if (sent_one) {
 							continue;
 						}
 					}
 					if (entry.done_response != null) {
 						break;
 					}
-					this.sync_loop.run();
+					my_loop.run();
 				}
 			} catch (GLib.Error e) {
 				this.sending = false;
 				this.complete_pending(
 					this.pending.size > 0 ? this.pending.get(0).request.id : entry.request.id,
 					null, e);
 			} finally {
 				this.sync_depth--;
+				if (timeout_source != null) {
+					timeout_source.destroy();
+				}
+				sync_watch.destroy();
+				this.sync_loop = saved_loop;
 				if (outer) {
-					if (timeout_source != null) {
-						timeout_source.destroy();
-					}
-					if (sync_watch != null) {
-						sync_watch.destroy();
-					}
-					this.sync_loop = null;
+					this.sync_context = null;
 					if (this.connected && this.read_channel != null) {
 						this.read_watch_id = this.read_channel.add_watch(
 							GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
 							this.on_read
 						);
 						if (this.pending.size > 0 && !this.pending.get(0).sent) {
 							this.send_head.begin();
 						}
 					}
 				}
 			}
```
