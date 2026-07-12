# HTTP RPC pending queue stall on second call

## Problem

Hub `detail` succeeds (RPC id=1, `/api/models/{repo}`) but the follow-up
`fetch_siblings` tree call (id=2, `/api/models/{repo}/tree/main`) times out
after 120 s even though the same URL returns in <1 s via curl.

```
RPC failed /api/models/.../tree/main id=2: call timed out
```

Expected: tree call completes quickly and merges file sizes into siblings.

## Reproduction

1. Run Just Ask with `huggingface_hub` detail on any public GGUF repo.
2. Observe id=1 detail OK, id=2 tree times out at `call_timeout_seconds`.

## Root cause

`OLLMrpc.Client.send_head()` HTTP branch returns after the first request
without draining the pending queue. `complete_pending()` calls
`send_head.begin()` while `sending` is still true, so that nested invocation
no-ops. After the first HTTP response, later queued calls never run until the
per-call timeout fires.

Socket transport already chains pending work after `sending = false`; HTTP did
not.

## Fix

Mirror socket chaining at the end of the HTTP branch in `send_head()`.

## Other log lines (same session)

- `HTTP 401` on gated repo detail — expected without Hub token; surfaced as
  `RPC failed` critical from `complete_pending`.
- `unknown bin property 'base-model-relation'` — new Hub `cardData` field;
  hyphen wire tag not mapped to GObject property name.
- `model_ref` ending in `.gguf` — LLM passed a filename as repo id (invalid).

## Changelog

- `libocrpc/Client.vala` — chain HTTP pending after first response.
- `libocrpc/Bin/Serializable.vala` — AUTO hyphen→underscore property lookup;
  `IGNORE_UNKNOWN` logs debug not critical.
- `libochf/ModelHubTypes.vala` — `base_model_relation` on `ModelCardData`.
- `liboctools/HuggingFace/Request.vala` — reject `.gguf` in `model_ref`.
