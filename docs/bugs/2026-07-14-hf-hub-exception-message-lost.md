# Hugging Face Hub tool returns useless "Exception has been thrown"

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval

**Related:**

- ℹ️ Session: `~/.local/share/ollmchat/history/2026/07/14/09-05-44.json`
  (`fid` `2026-07-14-09-05-44`)
- ℹ️ Log: `~/.cache/ollmchat/ollmchat.debug.log`
- ℹ️ Gee wrap already noted in
  [`docs/plans/8.2.1-libocrpc-auto-json-and-http-client.md`](../plans/8.2.1-libocrpc-auto-json-and-http-client.md)
  (criticals log real message *before* `wait_async` clobbers it)
- ℹ️ Hub tool: `liboctools/HuggingFace/Request.vala`
- ℹ️ RPC: `libocrpc/Client.vala` (`complete_pending`, `call`, `wait_response`)

---

## Problem

- 🔷 `huggingface_hub` (`detail` / `download`) failed in Chatter; tool reply to
  the LLM was only `ERROR: Exception has been thrown`.
- 🔷 Hub use is **public APIs** — no username/password required for public
  models; gated/private repos must stay omitted / rejected without implying
  login is configured.
- 🔷 When an error is rethrown or wrapped, **keep the original message** (or
  avoid wrapping). Do not replace a useful `GLib.Error` with a generic
  exception string.
- 🔷 Expected: tool result carries the real failure (e.g. HTTP status + URL /
  “repo not found or not public”), so the model can correct `model_ref` or
  tell the user something actionable.

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

- ✔️ Curl **without** credentials:

  - `GET …/api/models/unsloth/gemmable-4-31b-Q8_0-mtp` → **401** + same HF body
  - `GET …/api/models/Mia-AiLab/Gemmable-4-31B-MTP-GGUF` → **200**,
    `private: false`, `gated: false`

- ✔️ Hub client constructed as `new OLLMrpc.Client("", "", "https://huggingface.co")`
  — empty user/pass; we are not attaching Basic auth.
- ✔️ HF body `"Invalid username or password."` is Hub’s stock unauthenticated
  response for missing / inaccessible repos — **not** proof we sent a password.
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
4. ℹ️ Misleading HF 401 wording makes operators think auth is configured when
   the real case is often “repo missing / not public.”

## Proposed fix

### A — Preserve the real error across HTTP RPC failure (root)

- 🔷 Avoid relying on Gee `set_exception` → `wait_async` for HTTP transport
  failures when the useful message is already known at `complete_pending` /
  `send_http`.
- 💩 Prefer completing with a `Response` that carries `error` (status + URL +
  optional body snippet) **without** going through `set_exception`, **or**
  store the `GLib.Error` on the pending entry and rethrow **that** instance
  after wait (same domain/code/message), so wrapping is unnecessary.
- 🔷 If any wrap remains, pass through `e.message` (and prefer not wrapping at
  all when the outer type adds nothing).

### B — Hub tool: actionable public-API failures (symptom for LLM)

- 🔷 Map unauthenticated Hub **401/404** on `detail` / `download` to a clear
  tool string such as repo not found or not public on the public API — **not**
  “invalid username or password” and **not** a bare exception.
- 🚫 Do not add Hub token / login flows here; public-only remains the product
  rule.
- 💩 Optional: include HTTP status + URL in the tool error so the model can
  fix `model_ref` without staring at HF’s auth wording.

### C — Out of scope for this bug

- 🚫 Stopping the LLM from hallucinating authors (`unsloth/…`) — separate
  prompt/tool-discipline issue; fixing error surfacing is what lets the model
  recover after a bad `model_ref`.
- 🚫 Changing gated/private search omission (already works on real hits).

## Suggested order

1. 🔷 ⏳ §A — `libocrpc/Client.vala` HTTP failure path: keep original message
2. 🔷 ⏳ §B — `liboctools/HuggingFace/Request.vala` public 401/404 wording for
   tool replies
3. 🔷 ⏳ Reproduce with a missing `model_ref`; confirm tool + UI show real text,
   not `Exception has been thrown`
4. 💩 ⏳ After ✅: archive as `…-FIXED-…` under `docs/bugs/done/`

## Attempts / changelog

- ✔️ Log + session inspection only (no code change yet).
- ✔️ Confirmed HF 401 body without credentials via curl.

## Next

1. 🔷 ⏳ Approve §A / §B direction (and promote or drop 💩 items).
2. 🔷 ⏳ Apply only after approval — verbatim Remove / Replace / Add fences in
   this log when editing Vala.
