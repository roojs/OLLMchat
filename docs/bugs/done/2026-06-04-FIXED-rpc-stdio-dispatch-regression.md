# RPC stdio / script dispatch regression

**Status:** FIXED (2026-06-04) — `bash tests/test-rpc.sh build` all green.

**Started:** 2026-06-04

**Plan:** [`docs/plans/done/2.10.4.11-DONE-rpc-stdio-harness-fix.md`](../../plans/done/2.10.4.11-DONE-rpc-stdio-harness-fix.md)

---

## Problem

T0 RPC tests (`tests/test-rpc.sh` + `--interactive --rpc-script`) fail or crash after removing `Request.dispatch_line()` and inlining request read/dispatch at call sites.

## Root causes

### R1 — Dispatch without `params` node (FIXED)

**`Request.deserialize_property("params")`** intentionally stores a placeholder **`CallParam`**. Typed deserialize belongs in **`dispatch(params_node)`** when the call site passes **`obj.get_member("params")`**.

**Fix:** **`StdioConnection.run_script`** inline block (plan §3).

### R2 — NDJSON multi-line from `gobject_to_data` (FIXED)

**`Json.gobject_to_data`** hardcodes **`pretty=TRUE`** in json-glib.

**Fix:** **`Connection.write(GLib.Object)`** / **`Client.write`** — **`Json.Generator`**, **`set_pretty(false)`**.

### R3 — T0.1 test expected wrong wire shape (FIXED)

**Actual wire (json-glib default on plain **`Notification`** properties):**

```json
{"jsonrpc":"2.0","method":"Daemon.ready","object-type":"Daemon"}
```

**Was wrong:** test jq expected **`params.object_type`**. json-glib emits top-level kebab-case keys (**`object-type`**), not nested **`params`**.

**Fix:** T0.1 jq — **`.["object-type"] == "Daemon"`**. No **`Notification`** serialize overrides.

## Rejected fixes (do not re-propose)

- Changing **`deserialize_property("params")`** on **`Request`** (rejected twice)
- **`wire_params_node`**
- **`gobject_from_data`** + **`dispatch()`** without params node
- **`Request.dispatch_line()`** static
- **`Notification`** **`params`** serialize overrides to satisfy wrong test expectation

## Verification

```bash
bash tests/test-rpc.sh build
```

All T0 tests pass after R1–R3 fixes.
