# 8.3.7 — DONE — `Response` + `SCM_RIGHTS` buffer

**Status:** **DONE** ✅

**Parent:** [`RPC-8.3-libocrpc-live-handles-and-signals.md`](RPC-8.3-libocrpc-live-handles-and-signals.md)

**Depends on:** [`RPC-8.3.4-DONE-scm-rights-fds.md`](RPC-8.3.4-DONE-scm-rights-fds.md)

---

## Purpose (landed)

- **🔷** `✔️` Pair an fd with a successful **`Response`** (fd-first, then bin — same as `Notification`).
- **🔷** `✔️` Server: `Request.reply` / `Connection.reply` can pass an optional `Live.Buffer`.
- **🔷** `✔️` Client: on `Response` dispatch, `take_pending()` → `Response.buffer` (receive-side only).

**Tree:** `libocrpc/` (`Response`, `Request.reply`, `Connection.reply`, `Client` dispatch), `tests/rpc/`.

**Consumer:** gnome-shell-rpc `WindowActor.paint_to_content` (fd paint on sync call).
