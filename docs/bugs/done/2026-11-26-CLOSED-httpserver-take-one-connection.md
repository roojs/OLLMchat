# HttpServer answers one already-accepted connection

**Status:** ✅

## User decisions required

None.

## User reported

- 🔷 Finch phase 6 forks for each request. The parent accepts the connection and does not answer. The child answers that one connection.
- 🔷 The child uses the existing `HttpServer` reply path. It does not copy `on_rpc` or `on_route`.
- 🔷 A change in this library waits until this report is reviewed.

## Success scenario

- A caller that already accepted a socket can pass that connection to `HttpServer`.
- That call does not listen and does not open a second port.
- `POST /rpc` and the registered routes, including `GET /file/{id}`, run as they do after `start`.
- The call returns when that message finishes or aborts.
- A paused message, such as the SSE watch, stays inside the call until the message ends.
- `start` is unchanged for every current caller.

## Current behavior

- Finch can accept a socket and fork. It cannot hand that socket to `HttpServer`.
- The only public entry that speaks HTTP is `start`, and `start` listens in the same process that answers.

## Codebase observed behavior

- [`libocrpc/Transport/HttpServer.vala`](../../libocrpc/Transport/HttpServer.vala) `start` registers `on_rpc` and `on_route`, then accepts on its own `SocketService`.

```vala
this.soup.add_handler(this.rpc_path, this.on_rpc);
this.soup.add_handler(null, this.on_route);
```

- The accepted stream is passed to Soup only inside that private callback.

```vala
this.soup.accept_iostream(connection, local, remote);
```

- `on_rpc` and `on_route` are private. `Soup.Server.accept_iostream` is not reachable from another project.
- Soup already has `request_finished` and `request_aborted` on `Soup.Server`.

## Debugging

### Current debug output

None yet.

### Debug code added (remove when complete)

None.

## Proposed fix

### ✔️ Add `take` on `HttpServer`

Remember that the two handlers are registered, so `start` and `take` do not register them twice.

#### Add

```vala
private bool routed = false;
```

Next to `private bool listening = false`.

#### Replace with

In `start`, replace the two `add_handler` lines with:

```vala
if (!this.routed) {
    this.soup.add_handler(this.rpc_path, this.on_rpc);
    this.soup.add_handler(null, this.on_route);
    this.routed = true;
}
```

#### Add

```vala
/**
 * Answer one accepted connection, then return.
 *
 * The caller already accepted ''connection''. This call does not
 * listen. A paused message stays inside this call until it finishes
 * or aborts.
 *
 * @param connection the accepted socket
 * @param local this end of the socket, or null when unknown
 * @param remote the peer, or null when unknown
 * @return false when Soup rejects the socket
 */
public bool take(
    GLib.IOStream connection,
    GLib.SocketAddress? local,
    GLib.SocketAddress? remote
) {
    if (!this.routed) {
        this.soup.add_handler(this.rpc_path, this.on_rpc);
        this.soup.add_handler(null, this.on_route);
        this.routed = true;
    }
    var loop = new GLib.MainLoop();
    var finished = this.soup.request_finished.connect((msg) => {
        loop.quit();
    });
    var aborted = this.soup.request_aborted.connect((msg) => {
        loop.quit();
    });
    try {
        this.soup.accept_iostream(connection, local, remote);
    } catch (GLib.Error e) {
        GLib.warning("accept failed: %s", e.message);
        GLib.SignalHandler.disconnect(this.soup, finished);
        GLib.SignalHandler.disconnect(this.soup, aborted);
        return false;
    }
    loop.run();
    GLib.SignalHandler.disconnect(this.soup, finished);
    GLib.SignalHandler.disconnect(this.soup, aborted);
    return true;
}
```

Place `take` immediately above `stop`.

#### Add

In `stop`, after the replacement `Soup.Server` is assigned:

```vala
this.routed = false;
```

- `stop` throws away the `Soup.Server` that owns the handlers.
- Leaving `routed` true would skip registration on the next `start`.

## LLM

- ✅ User closed this report on 2026-11-26.
- ✔️ User approved **Proposed fix**. Applied in [`libocrpc/Transport/HttpServer.vala`](../../libocrpc/Transport/HttpServer.vala).
- ✔️ `stop` clears `routed` after it replaces `soup`.
  - A later `start` still registers handlers.
- ℹ️ Finch side: `finchsync/docs/bugs/2026-11-25-FEATURE-phase6-fork-and-sse.md` Phase 2. `Dispatch` accepts and forks. `Handler` is the child and would call `take`.
- ℹ️ Nullable `local` and `remote` match `Soup.Server.accept_iostream`.
- ℹ️ `Soup.Server.disconnect()` takes no arguments.
  - Signal ids use `GLib.SignalHandler.disconnect`, same as [`libocrpc/Transport/Connection.vala`](../../libocrpc/Transport/Connection.vala).
- 🚫 Do not copy `on_rpc` or `on_route` into Finch.
- 🚫 This report does not change Finch.
