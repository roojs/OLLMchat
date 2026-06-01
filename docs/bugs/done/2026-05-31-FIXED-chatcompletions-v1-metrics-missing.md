# ChatCompletions v1: performance metrics missing in UI

**Status:** FIXED (2026-05-31) — CLI verified (`Total Duration`, non-zero Tokens In/Out, t/s). GUI smoke recommended.

**Started:** 2026-05-31

**Related:** `docs/bugs/done/2026-05-30-FIXED-chatcompletions-streaming-ui-missing.md`

**Plan shape:** `docs/guide-to-writing-plans.md` — **`## Concrete code proposals`** is the contract.

---

## Purpose

- **🔷** v1 streaming shows **`Response completed (metrics not available)`** instead of duration / token summary.
- **🔷** Use **client wall-clock** for total duration and **approx t/s** (`eval_count / duration`) when the server sends no nanosecond timings.
- **🔷** Request **`stream_options.include_usage`** so token counts arrive on the final SSE line.
- **🔷** Do **not** run session/UI finalize on v1 **`finish_reason:"stop"`** — only when the **v1 stream** is actually finished.

---

## Scope

| In scope | Out of scope |
|----------|----------------|
| `Chunk.vala` — `finish_reason` sets `done_reason` only, not `done` | New helpers / new public methods on `ChatBase` |
| `ChatCompletions.exec_stream` — usage chunk, wall clock, single terminal `done` | `Session` branching on call type (not needed if v1 never sets `done` early) |
| `ChatCompletions.get_request_body` — `stream_options` | NDJSON fallback on v1 |
| `Response.Chat.get_summary` + `tokens_per_second` — wall-clock + token fallback | Changing legacy `Call.Chat` behaviour |

---

## How we know it is ChatCompletions (not Session magic)

- **🔷** Every live stream has **`Response.Chat.call`** set to the owning **`Call.ChatBase`** (`ChatCompletions.vala` assigns `chat.connection` / agent path).
- **🔷** Detect with **`response.call is Call.ChatCompletions`** (or **`!(response.call is Call.Chat)`** for “not native”).
- **ℹ️** `Call.ChatCompletions` sets protected **`is_openai = true`** on `Call.Base`; prefer **`is` type check** on **`response.call`** — no new surface on `ChatBase`.
- **🔷** **Do not** finalize in **`Session`** based on **`response.done`** for v1 mid-stream: fix at source — v1 must not set **`response.done = true`** until **`exec_stream`** ends (after usage chunk + wall clock).

Legacy **`Call.Chat`** keeps **`chunk.done == true`** only on the final NDJSON line (`"done": true` with durations). **`Session.handle_stream_chunk`** unchanged.

---

## Acceptance criteria

- **🔷** CLI/GUI metrics line: **`Total Duration: X.XXs | Tokens In: N Out: M | Y.YY t/s`** (not “metrics not available”) for v1 stream.
- **🔷** One **`content-stream`** + one metrics **`ui`** per reply (no duplicate finalize on `"stop"`).
- **🔷** Legacy **`--legacy`** path unchanged (native durations still used when present).
- **🔷** Request body includes **`"stream_options":{"include_usage":true}`** when streaming.

---

## Evidence (wire)

**Middle chunk** — `finish_reason` is JSON null (key present, not a string):

```json
"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]
```

**Stop chunk** — string `stop`, still no usage/durations:

```json
"choices":[{"delta":{"content":""},"finish_reason":"stop"}]
```

**Usage chunk** (only if `stream_options.include_usage`) — after stop:

```json
"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":16,"total_tokens":20}
```

---

## Concrete code proposals

Hunks are **Remove** / **Replace with** from the tree; verify surrounding context before applying.

### 1. `libollmchat/Response/Chunk.vala` — `choices`: `finish_reason` must not set `done`

**Why:** `"stop"` ends the message, not the SSE stream; usage may follow.

**Where:** `deserialize_property`, `case "choices"`, `finish_reason` block.

**Depends on:** none.

#### Keep

```vala
						if (choice_obj.has_member("finish_reason") &&
							choice_obj.get_member("finish_reason").get_node_type() == Json.NodeType.VALUE) {
							this.done_reason = choice_obj.get_member("finish_reason").get_string();
							this.done = this.done_reason != "";
						}
```

#### Replace with

```vala
						if (choice_obj.has_member("finish_reason") &&
							choice_obj.get_member("finish_reason").get_node_type() == Json.NodeType.VALUE) {
							this.done_reason = choice_obj.get_member("finish_reason").get_string();
						}
```

(`Chunk.done` stays false for v1 deltas; stream completion is set in `ChatCompletions.exec_stream`.)

---

### 2. `libollmchat/Call/ChatCompletions.vala` — `get_request_body()`: `stream_options.include_usage`

**Why:** Ollama sends token counts on a trailing SSE line when this is set.

**Where:** `get_request_body()`, after `obj.set_boolean_member("stream", ...)`.

**Depends on:** none.

#### Keep

```vala
			obj.set_boolean_member("stream", this.stream);
			var generator = new Json.Generator();
```

#### Replace with

```vala
			obj.set_boolean_member("stream", this.stream);
			if (this.stream) {
				var stream_opts = new Json.Object();
				stream_opts.set_boolean_member("include_usage", true);
				var stream_opts_node = new Json.Node(Json.NodeType.OBJECT);
				stream_opts_node.set_object(stream_opts);
				obj.set_member("stream_options", stream_opts_node);
			}
			var generator = new Json.Generator();
```

---

### 3. `libollmchat/Call/ChatCompletions.vala` — `exec_stream()`: usage chunk, wall clock, one terminal `done`

**Why:** Usage must merge before finalize; duration/t/s when server sends no ns fields.

**Where:** `exec_stream()` — start monotonic timer after `resp` is ready; adjust skip `continue`; replace loop tail.

**Depends on:** §1, §2.

#### Add — after `var resp = (Response.Chat) this.streaming_response;`

Record stream start (microseconds; convert to ns for `total_duration`):

```vala
			int64 stream_start_us = GLib.get_monotonic_time();
```

#### Keep

```vala
				if (resp.new_thinking.length == 0 &&
					resp.new_content.length == 0 &&
					!resp.done &&
					token == "") {
					continue;
				}
```

#### Replace with

```vala
				bool usage_only = chunk.prompt_eval_count > 0 || chunk.eval_count > 0;
				if (resp.new_thinking.length == 0 &&
					resp.new_content.length == 0 &&
					!resp.done &&
					token == "" &&
					!usage_only) {
					continue;
				}
```

#### Keep

```vala
			if (!resp.done) {
				resp.done = true;
			}
			return resp;
```

#### Replace with

```vala
			int64 elapsed_us = GLib.get_monotonic_time() - stream_start_us;
			if (resp.total_duration <= 0) {
				resp.total_duration = elapsed_us * 1000;
			}
			resp.done = true;
			this.stream_chunk("", false, resp);
			if (this.agent != null) {
				this.agent.handle_stream_chunk("", false, resp);
			}
			return resp;
```

---

### 4. `libollmchat/Response/Chat.vala` — `tokens_per_second` + `get_summary()` wall-clock / token fallback

**Why:** v1 has counts and client `total_duration`, not `eval_duration`.

**Where:** computed `tokens_per_second` getter; `get_summary()`.

**Depends on:** §3 (sets `total_duration` from wall clock).

#### Keep

```vala
		public double tokens_per_second {
			get {
				if (this.eval_duration_s > 0) {
					return (double)this.eval_count / this.eval_duration_s;
				}
				return 0.0;
			}
		}
```

#### Replace with

```vala
		public double tokens_per_second {
			get {
				if (this.eval_duration_s > 0) {
					return (double)this.eval_count / this.eval_duration_s;
				}
				if (this.total_duration_s > 0 && this.eval_count > 0) {
					return (double)this.eval_count / this.total_duration_s;
				}
				return 0.0;
			}
		}
```

#### Keep

```vala
		public string get_summary()
		{
			if (this.eval_duration <= 0) {
				// Return meaningful message when metrics aren't available
				// This ensures users always see feedback that the response completed
				return "Response completed (metrics not available)";
			}
			return "Total Duration: %.2fs | Tokens In: %d Out: %d | %.2f t/s".printf(
				this.total_duration_s,
				this.prompt_eval_count,
				this.eval_count,
				this.tokens_per_second
			);
		}
```

#### Replace with

```vala
		public string get_summary()
		{
			if (this.eval_duration > 0 || this.total_duration > 0) {
				return "Total Duration: %.2fs | Tokens In: %d Out: %d | %.2f t/s".printf(
					this.total_duration_s,
					this.prompt_eval_count,
					this.eval_count,
					this.tokens_per_second
				);
			}
			if (this.prompt_eval_count > 0 || this.eval_count > 0) {
				return "Tokens In: %d Out: %d".printf(
					this.prompt_eval_count,
					this.eval_count
				);
			}
			return "Response completed (metrics not available)";
		}
```

---

### 5. `Session` — no change (detection note only)

**Why:** After §1 + §3, **`response.done`** is true only once at v1 stream end, same as legacy’s single final line.

**🔷** If debugging: **`response.call is Call.ChatCompletions`** confirms v1 path; **`finalize_streaming`** should run once per reply.

**🚫** Do not add **`Session.handle_stream_chunk`** branches on call type unless a future regression sets **`done`** early again.

---

## Test plan

```bash
ninja -C build examples/oc-test-cli ollmapp/ollmchat

./build/examples/oc-test-cli --url http://127.0.0.1:11434/api -m MODEL "Say hi"
# ui line: Total Duration + Tokens In/Out + t/s; one content-stream in session dump

./build/examples/oc-test-cli --legacy --url http://127.0.0.1:11434/api -m MODEL "Say hi"
# still native metrics when eval_duration present
```

---

## Conclusions

- **🔷** **`Chunk.usage`** property required so `Json.gobject_deserialize` invokes usage handling (custom `deserialize_property` alone is not enough without a registered property).
- **🔷** v1 **`finish_reason:"stop"`** must not set **`Chunk.done`**; terminal **`done`** + **`stream_chunk`** only in **`ChatCompletions.exec_stream`**.
- **🔷** **`response.call is Call.ChatCompletions`** is how you tell v1 from native in debug; production fix is in the call layer, not **`Session`**.
- **💩** Wall-clock **`total_duration`** is an estimate (monotonic us × 1000 → ns); good enough for UI t/s when Ollama omits timings.
