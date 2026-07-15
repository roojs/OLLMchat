# Hugging Face Hub tool returns useless "Exception has been thrown"

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ fixed — A.1–A.3 in `libocrpc/Client.vala`

**Related:**

- ℹ️ Session: `~/.local/share/ollmchat/history/2026/07/14/09-05-44.json`
  (`fid` `2026-07-14-09-05-44`)
- ℹ️ Log: `~/.cache/ollmchat/ollmchat.debug.log`
- ℹ️ Gee wrap already noted in
  [`docs/plans/8.2.1-libocrpc-auto-json-and-http-client.md`](../../plans/8.2.1-libocrpc-auto-json-and-http-client.md)
  (criticals log real message *before* `wait_async` clobbers it)
- ℹ️ Hub tool: `liboctools/HuggingFace/Request.vala`
- ℹ️ RPC: `libocrpc/Client.vala` (`complete_pending`, `call`, `wait_response`)
- ℹ️ Coding standard `line-length-breaking` — format-string calls (`throw` /
  error ctor / `GLib.debug`/`warning`/`critical`): message on the **same line
  as the call**; if too long, wrap remaining args **grouped** (not one
  argument per line). See `docs/coding-standards.md` (also router + compliance
  gate).

---

## Problem

- 🔷 `huggingface_hub` (`detail` / `download`) failed in Chatter; tool reply to
  the LLM was only `ERROR: Exception has been thrown`.
- 🔷 Hub use is **public APIs** only; gated/private repos must stay omitted /
  rejected. The HTTP client does not support Hub authentication.
- 🔷 When an error is rethrown or wrapped, **keep the original message** (or
  avoid wrapping). Do not replace a useful `GLib.Error` with a generic
  exception string.
- 🔷 Expected: tool result carries the real failure message from the transport
  (e.g. `HTTP 401 for …` and/or Hub’s response body), so the model can correct
  `model_ref` or tell the user something actionable.

## Reproduction

1. Chatter / Just Ask; ask to download a Gemma MTP GGUF from Hugging Face.
2. Let the agent `search` → `detail` / `download` on a **non-existent** or
   misspelled `model_ref` (session used e.g. `unsloth/gemmable-4-31b-Q8_0-mtp`,
   `Mia-AiLab/Gemmable-4-GGUF`).
3. Tool UI / tool role shows `ERROR: Exception has been thrown`.
4. Debug log still has the real line at `Client.vala` / `complete_pending`.

## Evidence

- ✔️ Session tool replies (multiple): `ERROR: Exception has been thrown`
  (content length 32).
- ✔️ Debug log pairs:

  - `Client.vala`: `recv body={"error":"Invalid username or password."}`
  - `Client.vala`: `RPC failed /api/models/… id=1: HTTP 401 for https://huggingface.co/api/models/…`
  - `RequestBase.vala`: `Tool 'huggingface_hub' threw error: Exception has been thrown`
  - `Base.vala`: tool error result `ERROR: Exception has been thrown`

- ✔️ Public GET (curl, no client auth — Hub HTTP client does **not** support
  authentication; that is by design, not a gap):

  - `GET …/api/models/unsloth/gemmable-4-31b-Q8_0-mtp` → **401** + same HF body
  - `GET …/api/models/Mia-AiLab/Gemmable-4-31B-MTP-GGUF` → **200**,
    `private: false`, `gated: false`

- ✔️ Hub calls use `new OLLMrpc.Client("", "", "https://huggingface.co")`
  (HTTP mode; first two args are unused for Hub).
- ✔️ HF body `"Invalid username or password."` is Hub’s stock wording on some
  public-API failures. Fine to pass that through to the tool/LLM — the bug is
  losing it, not that the wording exists.
- ✔️ `unsloth/gemmable-4-31b-Q8_0-mtp` was **not** in search results; the LLM
  hallucinated the author. Search correctly returned
  `Mia-AiLab/Gemmable-4-31B-MTP-GGUF` + file `gemmable-4-31b-Q8_0-mtp.gguf`.
  Help only mentions “unsloth” as a bad overloaded-query example.
- ✔️ Gated/private filtering on successful search/detail is already in place;
  missing refs fail at HTTP before that filter runs.

## Root cause

1. ✔️ **Gee `Promise` / `wait_async` message loss:**
   `complete_pending` calls `promise.set_exception(error)` with a useful
   `IOError` (`HTTP 401 for …`). `yield entry.promise.future.wait_async()` then
   surfaces Vala’s generic **`Exception has been thrown`**. Already called out
   in plan 8.2.1 (logging before wrap).
2. ✔️ **Further wrapping in `Client.call`:** catch of that generic message builds
   a new `Error(RpcErrorCode.INTERNAL_ERROR, e.message)` on the `Response`, so
   the caller only ever sees the clobbered string.
3. ✔️ **HuggingFace rethrow:** `throw new GLib.IOError.FAILED(detail_resp.error.message)`
   (and similar) — wraps again; when `message` is already generic, the tool/
   `RequestBase` path still returns `ERROR: Exception has been thrown`.

## Proposed fix

### A — Preserve the real error across HTTP RPC failure (root)

- 🔷 Avoid Gee `set_exception` → `wait_async` for pending completion failures —
  that path turns a good `GLib.Error.message` into **`Exception has been thrown`**.
- 🔷 Complete failures with `promise.set_value(Response { error = … })` using the
  **same** `error.message` string (HTTP line and Hub body when present).
  (`set_value` / `set_exception` are **libgee** `Gee.Promise` APIs, not ours.)
- 🔷 Format-string calls in A.1–A.3 (`throw` / `new Error` / `GLib.critical` /
  `GLib.warning`): message on the **same line as the call**; if wrapping,
  remaining args stay **grouped** — not one-per-line (`line-length-breaking`).
- 🔷 Passing Hub’s body through (including `"Invalid username or password."`) is
  OK — do not rewrite it into a different story.
- 🚫 Do not add Hub authentication — the client does not support it and this
  bug must not imply that we should.
- 🚫 Do not remap HF 401 wording in the Hub tool for this bug.

#### Direction

1. 💩 `send_http` — on non-2xx, throw with status, URL, **and** response body
   (body is already in the debug log; include it in the `GLib.Error` so callers
   see Hub’s text).
2. 💩 `complete_pending` — on `error != null`, `set_value` a `Response` whose
   `Error.message` is `error.message`; **never** `set_exception` here.
3. 💩 `disconnect` — same: abort pending with `set_value` + `Response.error`,
   not `set_exception` (same Gee clobber).
4. ℹ️ `call()` already returns `Response.error` to Hub callers; once (2) lands,
   HuggingFace `detail_resp.error.message` stays useful. Leave Hub rethrows as-is
   for this bug (they pass `message` through).

### A.1 `libocrpc/Client.vala` — `send_http()`: include body in HTTP failure

**Why:** Today the thrown message is only `HTTP %u for %s`; Hub’s JSON body
(`Invalid username or password.`) is logged but not returned to the tool.

**Where:** `send_http` — the non-2xx `throw` after `recv body` debug.

**Depends on:** none.

#### Remove

```vala
			if (message.status_code < 200 || message.status_code >= 300) {
				throw new GLib.IOError.FAILED("HTTP %u for %s", message.status_code, url);
			}
```

#### Replace with — same check; message includes stripped body (string on call line; args wrap).

```vala
			if (message.status_code < 200 || message.status_code >= 300) {
				throw new GLib.IOError.FAILED("HTTP %u for %s: %s",
					message.status_code, url, body.strip());
			}
```

### A.2 `libocrpc/Client.vala` — `complete_pending()`: fail via `Response.error`

**Why:** `set_exception` + `wait_async` is what produces **`Exception has been
thrown`**. Put the transport message on `Response.error` and `set_value` so
`call()` returns it intact.

**Where:** `complete_pending` — the `if (error != null)` branch only.

**Depends on:** A.1 optional for richer text; A.2 alone already fixes the
generic message.

#### Remove

```vala
				if (error != null) {
					GLib.critical(
						"RPC failed %s id=%d: %s",
						entry.request.method,
						id,
						error.message
					);
					entry.promise.set_exception(error);
				} else {
					entry.promise.set_value(response);
				}
```

#### Replace with — log the same critical; complete with wire `Error`, no Gee exception.

```vala
				if (error != null) {
					GLib.critical("RPC failed %s id=%d: %s",
						entry.request.method, id, error.message);
					entry.promise.set_value(new Response() {
						id = entry.request.id,
						error = new Error((int) RpcErrorCode.INTERNAL_ERROR, error.message)
					});
				} else {
					entry.promise.set_value(response);
				}
```

### A.3 `libocrpc/Client.vala` — `disconnect()`: abort pending without `set_exception`

**Why:** Same Gee clobber on disconnect-aborted waits.

**Where:** `disconnect` — the `foreach (var entry in this.pending)` abort loop.

**Depends on:** none (same pattern as A.2).

#### Remove

```vala
			foreach (var entry in this.pending) {
				GLib.warning(
					"disconnect abort %s id=%d socket_path=%s",
					entry.request.method,
					entry.request.id,
					this.socket_path
				);
				entry.promise.set_exception(
					new GLib.IOError.FAILED("Client: disconnected")
				);
			}
```

#### Replace with — `set_value` + `Response.error` with the same disconnect string.

```vala
			foreach (var entry in this.pending) {
				GLib.warning("disconnect abort %s id=%d socket_path=%s",
					entry.request.method, entry.request.id, this.socket_path);
				entry.promise.set_value(new Response() {
					id = entry.request.id,
					error = new Error((int) RpcErrorCode.INTERNAL_ERROR, "Client: disconnected")
				});
			}
```

### B — Out of scope for this bug

- 🚫 Remapping HF 401 wording to a friendlier “repo not found” string.
- 🚫 Stopping the LLM from hallucinating authors (`unsloth/…`) — separate
  prompt/tool-discipline issue; fixing error surfacing is what lets the model
  recover after a bad `model_ref`.
- 🚫 Changing gated/private search omission (already works on real hits).
- 🚫 Changing HuggingFace `throw new IOError.FAILED(detail_resp.error.message)`
  wrappers — message is preserved once A.2 lands.

## Suggested order

1. 🔷 ✔️ A.1 — `send_http` body in HTTP error message
2. 🔷 ✔️ A.2 — `complete_pending` `set_value` + `Response.error`
3. 🔷 ✔️ A.3 — `disconnect` abort without `set_exception`
4. 🔷 ✅ Reproduce / user closed — real HTTP/Hub text surfaced
5. 🔷 ✅ Archived under `docs/bugs/done/`

## Attempts / changelog

- ✔️ Log + session inspection only (no code change yet).
- ✔️ Confirmed HF 401 body on public GET via curl.
- ✔️ §A verbatim fences written (A.1–A.3); A.1 keeps the message on the
  `throw` call line per `line-length-breaking`.
- ✔️ 2026-07-15 — Applied A.1–A.3 in `libocrpc/Client.vala`.
- ✅ 2026-07-15 — Closed; moved to `docs/bugs/done/`.
