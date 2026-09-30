# HTTP 500 on async filesd RPC

**Status:** ✅ FIXED — user closed 2026-09-30. Soup stays paused until the async filesd reply is written.

## Problem

- **🔷** Tablet startup alert: `Could not load projects: HTTP 500 for https://192.168.0.16:8443/rpc: (NULL)`.
- **🔷** Expected: `RPC-ProjectManager.rpc_load_projects_from_db` returns the project list.
- **ℹ️** Server log `~/.cache/ollmchat/ollmfilesd.debug.log` records the method, then nothing. No `encode failed` line.

## Root cause

- **✔️** `rpc_load_projects_from_db` replies only after `yield` on the database query. The HTTPS handler returned first.
- **✔️** Soup was paused only when `reply.streaming` was already set. This call is one binary `Response`, so it was not paused.
- **✔️** Soup completes a handler that returns with no status as HTTP 500 and an empty body. The client prints that empty body as `(NULL)`. The TLS connection stays up.
- **✔️** `RPC-Daemon.hello` replies before the handler returns, so it stays HTTP 200. The same project-list method succeeds on the desktop socket.

## Proposed fix

- **🔷** Pause the Soup message whenever `dispatch()` returns and the reply is not finished. Do not set `streaming`.
- **🔷** `HttpReply.write` unpauses on every finished single response, including the binary body, the JSON body, and the 500 encode paths.
- **ℹ️** A missing handler that already set HTTP 404 returns before that pause, so the 404 is not held open.

#### Replace with — `libocrpc/Transport/HttpServer.vala`

Both dispatch sites use `if (!reply.finished)` before `pause_message`. The route 404 path returns after `set_status(404)`.

#### Add — `libocrpc/Transport/HttpReply.vala`

After each `this.finished = true` on a single response, unpause when `this.paused` is set. The NDJSON finish path already did this.

## Attempts

- **✔️** `ninja -C build libocrpc/libocrpc.so`.
- **ℹ️** `/usr/bin/ollmfilesd` loads `/lib/x86_64-linux-gnu/libocrpc.so`. Replacing that file needs root. The user unit drop-in `~/.config/systemd/user/ollmfilesd.service.d/build-libocrpc.conf` sets `LD_LIBRARY_PATH` to `build/libocrpc`. Restarted `ollmfilesd`; `/proc/<pid>/maps` shows that library.
- **✅** 2026-09-30 — User closed. Project list no longer returns HTTP 500.
