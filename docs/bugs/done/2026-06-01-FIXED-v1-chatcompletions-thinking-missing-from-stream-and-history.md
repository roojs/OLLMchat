# v1 ChatCompletions: thinking missing from stream and session history

**Status:** FIXED (2026-06-01) — §1–§2 applied and verified on `qwen3.6:latest` via `oc-test-cli`

**Started:** 2026-06-01

**Pointer:** `docs/coding-standards.md`, `docs/guide-to-writing-plans.md`, `docs/bug-fix-process.md`.

**Related:**

- ℹ️ `docs/bugs/done/2026-05-30-FIXED-chatcompletions-streaming-ui-missing.md` — prior v1 stream fix claimed `reasoning` / `reasoning_content` mapping
- ℹ️ `docs/bugs/done/2026-06-01-FIXED-tool-calls-missing-history-and-out-of-order-stream-markers.md` — same session family (`12-50-30.json`)
- ℹ️ `docs/plans/done/1.24.3-DONE-openai-api-chat.md` — spec: v1 delta `reasoning_content` → `Message.thinking`

---

## Purpose

- 🔷 Thinking models (`qwen3.6:latest`) must stream reasoning into `think-stream` history rows and the UI thinking frame — same behaviour as legacy `/api/chat` (`--legacy`).
- 🔷 Default path is v1 `ChatCompletions`; `--legacy` is the A/B control.
- ✅ §1 — map v1 delta `reasoning` / `reasoning_content` → `Message.thinking` in `Chunk.vala` (applied in tree).
- ✅ §2 — remove dead `reasoning` cases from `Message.vala` (applied in tree).

---

## Problem

**Expected:** With a thinking-capable model, session history contains `think-stream` messages; CLI prints `[think]` chunks and a `Thinking:` summary (as `--legacy` does).

**Actual (v1 default):**

- Session `~/.local/share/ollmchat/history/2026/06/01/12-50-30.json` — **no** `think-stream` roles; only `content-stream` for assistant turns.
- CLI v1 run — **no** `[think]` markers; only final content visible.
- Wire **does** carry reasoning: Ollama v1 SSE deltas include `"reasoning":"…"` (39 chunks on a simple prompt).

**Actual (`--legacy`):** Thinking works — `[think]` on stderr, `Thinking:` block on stdout, reasoning text present.

---

## Verification environment

- 🔷 **Ollama:** `http://192.168.88.14:11434/api`
- 🔷 **Model:** `qwen3.6:latest`
- 🔷 **CLI:** `./build/examples/oc-test-cli` (user-built 2026-06-01 ~13:14)

**Reproduce A/B (repo root):**

```bash
# v1 default — thinking lost
./build/examples/oc-test-cli --debug \
  --url http://192.168.88.14:11434/api \
  -m qwen3.6:latest \
  "What is 2+2? Reply with just the number."

# legacy control — thinking present
./build/examples/oc-test-cli --legacy --debug \
  --url http://192.168.88.14:11434/api \
  -m qwen3.6:latest \
  "What is 2+2? Reply with just the number."
```

**Observed 2026-06-01:**

| Path | `[think]` count | `Thinking:` in stdout | SSE `"reasoning"` chunks |
|------|-----------------|----------------------|--------------------------|
| v1 (default) | 0 | no | 39 |
| `--legacy` | yes | yes | n/a (native `message.thinking`) |

**Example v1 wire (stderr `--debug`):**

```json
{"choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning":"The"},"finish_reason":null}]}
```

**Example v1 stdout:** `Content: 4` only.

**Example legacy stdout:** `Thinking: The user is asking…` + `Content: 4`.

---

## Root cause (verified)

### Request side — ✅ OK

- `Session` / `Agent` / `oc-test-cli` set `chat.think = model_obj.is_thinking` when the model has the `thinking` capability.
- `ChatCompletions.get_request_body()` maps `think` → `reasoning_effort: "medium"`.
- Evidence: Ollama returns `reasoning` deltas only when effort is enabled.

### Response side — 🔷 broken on v1 path

Pipeline:

1. `ChatCompletions.exec_stream()` deserializes SSE → `Response.Chunk` (`Chunk.vala` `choices` → `delta` → `Message`).
2. `Response.Chat.addChunk()` emits stream text when `chunk.message.thinking != ""` → `new_thinking`.
3. `Session.handle_stream_chunk(..., is_thinking=true)` persists `think-stream` rows.
4. `ChatCompletions.exec_stream()` skips chunks when `new_thinking` and `new_content` are both empty (`ChatCompletions.vala` ~432–438).

**Failure point:** After deserialize, `chunk.message.thinking` stays empty while wire `delta.reasoning` is non-empty → `new_thinking` never set → no `[think]`, no `think-stream`, UI thinking frame never opens.

**Verified deserialize gap (`Message.vala` + generated `Message.c`):**

- `Message.deserialize_property` contains `case "reasoning":` → `this.thinking = …`, but Vala emits `g_return_val_if_fail (pspec != NULL, FALSE)` at function entry.
- JSON key **`reasoning`** is **not** a GObject property on `Message` (property is **`thinking`**), so GLib passes **`pspec == NULL`** and the handler **returns before the switch**.
- Debug run (2026-06-01): `wire_reasoning.len=3`, `thinking.len=0` on every reasoning chunk — mapping code is **dead**, not wrong key spelling.

**Legacy path (`Call.Chat` / `/api/chat`):** Native chunks use top-level `message.thinking` — real property, non-null `pspec` — works today.

---

## Impact

- 🔷 App chat UI: no thinking frame during v1 streaming (same code path as CLI).
- 🔷 Session JSON: no `think-stream` rows → thinking lost on restore.
- 🔷 Tool-heavy turns (e.g. `12-50-30.json`) show content-only assistant streams despite model reasoning before tool calls.

---

## Concrete code proposals

Hunks are **Remove** / **Replace with** from the tree. Verify surrounding context before applying.

### §1. `libollmchat/Response/Chunk.vala` — `deserialize_property()` `case "choices"`: map v1 delta reasoning → `thinking`

**Status:** ✅ Applied in tree.

**Why:** `Message.deserialize_property` never runs for wire key `reasoning` (`pspec == NULL`). Map aliases on the delta object after `gobject_deserialize` so `addChunk` / stream / history receive thinking text.

**Where:** `deserialize_property()`, `case "choices":`, inside the `for` over `array`, block that handles `choice_obj.has_member("delta")`, immediately after `Json.gobject_deserialize(typeof(Message), delta_node)`.

**Depends on:** none.

#### Remove

```vala
						var delta_node = choice_obj.get_member("delta");
						var msg = Json.gobject_deserialize(typeof(Message), delta_node) as Message;
						if (msg != null) {
							this.choices.add(msg);
						}
```

#### Replace with

```vala
						var delta_node = choice_obj.get_member("delta");
						var msg = Json.gobject_deserialize(typeof(Message), delta_node) as Message;
						if (msg == null) {
							continue;
						}
						this.choices.add(msg);
						if (msg.thinking != "") {
							continue;
						}
						var delta_obj = delta_node.get_object();
						if (delta_obj.has_member("reasoning")) {
							msg.thinking = delta_obj.get_member("reasoning").get_string();
							continue;
						}
						if (delta_obj.has_member("reasoning_content")) {
							msg.thinking = delta_obj.get_member("reasoning_content").get_string();
							continue;
						}
```

---

### §2. `libollmchat/Message.vala` — `deserialize_property()`: remove dead `reasoning` alias cases

**Status:** ✅ Applied in tree.

**Why:** `case "reasoning":` / `case "reasoning_content":` never execute (`pspec == NULL` guard). Keeping them implies a working path; v1 alias mapping lives in `Chunk.vala` §1.

**Where:** `deserialize_property()`, switch before `default:`.

**Depends on:** §1.

#### Remove

```vala
				case "reasoning_content":
				case "reasoning":
					this.thinking = property_node.get_string();
					value = Value(typeof(string));
					value.set_string("");
					return true;
				default:
```

#### Replace with

```vala
				default:
```

---

## Test plan (after §1)

- 🔷 Rebuild `examples/oc-test-cli`.
- 🔷 v1 run (no `--legacy`): expect `[think]` on stderr and `Thinking:` in stdout summary — same prompt as **Verification environment** above.
- 🔷 New session JSON: at least one `think-stream` row for the assistant turn.
- 🔷 `--legacy` A/B unchanged (control).

---

## Attempts / changelog

| Date | Action | Result |
|------|--------|--------|
| 2026-06-01 | Inspected session `12-50-30.json` | No `think-stream` / `thinking` fields |
| 2026-06-01 | CLI A/B v1 vs `--legacy` on `qwen3.6:latest` | v1: 0 `[think]`, 39 wire `reasoning` chunks; legacy: thinking OK |
| 2026-06-01 | Traced `ChatCompletions` → `Chunk` → `Message` → `addChunk` → `Session` | Request OK; response mapping empty |
| 2026-06-01 | Bug log written | Awaiting approval before code change |
| 2026-06-01 | Temporary debug in `Chunk.vala`, `ChatCompletions.vala` | Confirmed `wire_reasoning.len>0`, `thinking.len=0`; removed from tree and bug log |
| 2026-06-01 | Applied §1 `Chunk.vala`, §2 `Message.vala` | v1 CLI: `Thinking:` + `[think]` stream; matches legacy behaviour |

---

## Open questions

- 💩 ⏳ Should final `assistant` history rows also store accumulated thinking in a `thinking` field (non-stream path)? Confirm after stream fix.

---

## Conclusions

- 🔷 **Not** a “thinking turned off” config bug — v1 **requests** reasoning and Ollama **returns** it.
- 🔷 **Verified 2026-06-01** (rebuilt `oc-test-cli`, `--debug`, `qwen3.6:latest`):

  `thinking.len=0 wire_reasoning.len=3` on every reasoning chunk — wire has `delta.reasoning`, deserialized `Message.thinking` stays empty.

- 🔷 **Root cause:** Vala emits `g_return_val_if_fail (pspec != NULL, FALSE)` at the top of `Message.deserialize_property`. JSON key **`reasoning`** is not a GObject property (`thinking` is), so GLib passes **`pspec == NULL`** and the handler returns **before** `case "reasoning":` runs. The mapping code exists but is dead.

- 🔷 **`--legacy`** works because `/api/chat` uses `message.thinking` — a real property with non-null `pspec`.

- ⏳ **Fix:** §1–§2 applied and verified; archived under `docs/bugs/done/`.
