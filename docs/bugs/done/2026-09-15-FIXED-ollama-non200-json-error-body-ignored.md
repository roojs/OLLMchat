# Ollama non-200 responses: JSON `error` body ignored (show 404 → “Endpoint not found”)

**Status:** ✅ FIXED — non-200 JSON `error` body used for the throw  
**Started:** 2026-09-15  
**Reporter:** Alan  
**Component:** `libollmchat/Call/Base.vala` (`send_request`, `handle_streaming_response`)  
**Process:** Follow **`docs/bug-fix-process.md`** — propose → approve → apply.

---

## Problem

🔷 Startup / tool-model checks can hit Ollama when a configured model is **not** on the server (here: analysis `qwen3-coder:30b` in `~/.config/ollmchat/config.2.json`).

🔷 For non-streaming calls such as **`POST /api/show`**, Ollama returns **HTTP 404** with a JSON body:

```json
{"error":"model 'qwen3-coder:30b' not found"}
```

🔷 Expected: throw / surface that server message (or an equivalent clear model-not-found error).

🔷 Actual: `Call.Base.send_request` only tries `parse_error_from_json` for **HTTP 400**. On **404** it skips the body and `handle_message_error` throws:

`fetch returned 404: Endpoint not found. Please check the server URL.`

That mislabels a missing **model** as a missing **endpoint**.

ℹ️ `/api/show` is **not** streamed. `ShowModel.exec_show()` uses `send_request()` (one-shot). Streaming is for chat / pull / create.

---

## Reproduction / evidence

✔️ Against default connection `http://192.168.88.14:11434` (2026-09-15):

- ✔️ Server up: `GET /` → `Ollama is running`, version `0.34.0`, 45 models on `/api/tags`.
- ✔️ `qwen3-coder:30b` **absent**; `bge-m3:latest`, `gemma4:26b`, `qwen3:1.7b` present.
- ✔️ Show missing model:

```
HTTP/1.1 404 Not Found
Content-Type: application/json; charset=utf-8
…
{"error":"model 'qwen3-coder:30b' not found"}
```

- ✔️ Show existing model: HTTP 200, single JSON object (`application/json`) — not NDJSON.
- ℹ️ Related (separate path): auto-pull of the same missing name streams HTTP **200** then:

```
{"status":"pulling manifest"}
{"error":"EOF"}
```

`~/.local/share/ollmchat/loading.json` left at `pending-retry` / `last-chunk-status: pulling manifest`. That is **pull NDJSON**, not show; see **Related follow-up** below.

ℹ️ Config still names analysis `qwen3-coder:30b` while code defaults in `VectorToolConfig.setup_defaults()` use `qwen3:1.7b`.

---

## Root cause

✔️ In `libollmchat/Call/Base.vala` `send_request`:

```vala
if (message.status_code != 200) {
	if (message.status_code == 400 && bytes != null && bytes.get_size() > 0) {
		this.parse_error_from_json((string)bytes.get_data(), "Bad request: ");
	}
	this.handle_message_error(message);
}
```

✔️ Ollama puts the real reason in the JSON **`error`** string (or object with `message`). Status (404 / 500 / …) only signals failure; there is **no** custom error header.

✔️ `parse_error_from_json` already throws `OllmError.FAILED` with that text when the body has `error`. It is just not called for show’s 404 (or other non-400 non-200 bodies).

✔️ `handle_message_error`’s 404 branch always says “Endpoint not found…”, which is wrong for `/api/show` model miss.

✔️ Same 400-only body parse exists in `handle_streaming_response` via `parse_streaming_error` (relevant when a stream endpoint returns non-200 with a JSON error body; **not** the pull-at-200 case).

---

## Fix applied

🔷 On non-200 responses with a non-empty body, always attempt `parse_error_from_json` (same as today’s 400 path) so the thrown message is the server’s `error` text. Then fall through to `handle_message_error` only if that call does not throw (unchanged structure).

🔷 Apply the same widening in `handle_streaming_response` for non-200 stream starts (`parse_streaming_error` for any non-200, not only 400).

💩 Soften the generic 404 string in `handle_message_error` only as a fallback when there is **no** parseable body (empty body / non-JSON). Prefer body text when present — do not invent a second message format.

🚫 Do not add defensive null checks or swallow errors.  
🚫 Do not change `ShowModel` to streaming.  
🚫 Do not “fix” startup by silently swapping the configured analysis model name in this bug (config is user data).  
🚫 Do not treat this bug as fixed solely by clearing `loading.json`.

### 1. `libollmchat/Call/Base.vala` — `send_request`: parse JSON error for any non-200

**Why:** Show (and other one-shot calls) return 404/500 with `{"error":"…"}`; only 400 is parsed today.

**Where:** `send_request`, status check after `send_and_read_async`.

**Depends on:** none.

#### Remove

```vala
			if (message.status_code != 200) {
				if (message.status_code == 400 && bytes != null && bytes.get_size() > 0) {
					this.parse_error_from_json((string)bytes.get_data(), "Bad request: ");
				}
				this.handle_message_error(message);
			}
```

#### Replace with

```vala
			if (message.status_code != 200) {
				if (bytes != null && bytes.get_size() > 0) {
					var prefix = message.status_code == 400 ? "Bad request: " : "";
					this.parse_error_from_json((string)bytes.get_data(), prefix);
				}
				this.handle_message_error(message);
			}
```

### 2. `libollmchat/Call/Base.vala` — `handle_streaming_response`: same for non-200

**Why:** Keep stream open and one-shot error handling consistent when the status line is already an error.

**Where:** `handle_streaming_response`, after `send_async`, `status_code != 200` branch.

**Depends on:** none.

#### Remove

```vala
			if (message.status_code != 200) {
				if (message.status_code == 400) {
					this.parse_streaming_error(input_stream, "Bad request: ");
				}
				this.handle_message_error(message);
			}
```

#### Replace with

```vala
			if (message.status_code != 200) {
				var prefix = message.status_code == 400 ? "Bad request: " : "";
				this.parse_streaming_error(input_stream, prefix);
				this.handle_message_error(message);
			}
```

### 3. `libollmchat/Call/Base.vala` — `handle_message_error` 404 fallback wording (optional)

**Why:** 💩 Empty-body 404 should not claim the **URL endpoint** is wrong when callers often mean “resource missing”.

**Where:** `handle_message_error` `case 404:`.

**Depends on:** §1 (body parse remains primary).

#### Remove

```vala
				case 404:
					throw new OllmError.FAILED("fetch returned 404: Endpoint not found. Please check the server URL.");
```

#### Replace with

```vala
				case 404:
					throw new OllmError.FAILED("fetch returned 404: Not found.");
```

---

## Related follow-up (not this bug’s apply scope unless approved)

💩 **Streaming pull at HTTP 200** with a later NDJSON line `{"error":"EOF"}`:

- ℹ️ Headers stay `200 OK` / `application/x-ndjson` — no status remap possible.
- ℹ️ `Response.Chunk` has no `error` property; `PullManagerThread` only treats failure via `status` (`success` / `error*` / `failed`).
- ℹ️ That leaves `loading.json` at `pending-retry` / `pulling manifest` and blocks `Initialize.ensure_required_models` until retries fail.
- ⏳ Separate fix if wanted: deserialize/handle chunk `error`, mark pull failed with that text, emit `model_failed` without treating it as a flaky network retry forever.

ℹ️ Soft unblock without code: point analysis at a present model (e.g. `qwen3:1.7b`) and clear the stuck `qwen3-coder:30b` entry in `loading.json`.

---

## Attempts / changelog

- ✔️ 2026-09-15 — Probed LAN Ollama; confirmed show 404 body vs pull stream 200+`error`; traced `send_request` 400-only parse and `ShowModel` non-stream path.
- ✔️ 2026-09-15 — Applied §1–§3 in `libollmchat/Call/Base.vala` (user approved apply). Single-use `prefix` local from the proposal was inlined at the call site (coding-standards `temporary-variables`).
- ✔️ Moved to `docs/bugs/done/2026-09-15-FIXED-ollama-non200-json-error-body-ignored.md`.

---

## Next

- ℹ️ Pull NDJSON `{"error":"EOF"}` at HTTP 200 is a separate follow-up (not this bug).