# `RPC-Daemon.hello` does not verify client and server build version.

**Status:** ⏳

## User decisions required

💩 Approve applying **Proposed fix** Topics 1–5 in order (Topic 6 at release cut).

## User reported

- 🔷 `RPC-Daemon.hello` should carry **`OLLMchat.VERSION`** (Meson `project()` version, same string in app and `ollmfilesd`). Missing version → **`0.0.0`**.
- 🔷 Same rules as Argus: newer client refused by server; older client accepted with warning; client refuses when server is **older** than client.
- 🔷 With **`ClientBoot`**, when the daemon binary is too old for this client, **`kill()` + `ensure_daemon()`** once, then hello again (at most one respawn per `connect`).
- 🔷 Bump root `meson.build` `project(..., version: …)` in the release that ships this handshake; follow `docs/creating-releases.md` for changelog/packages.

## Success scenario

- Hello uses args **`iss`** (protocol, client name, client version) and returns the server version string as **`retval`**, not a `Daemon` object.
- Client and server compare versions after hello; mismatches produce the Argus-style errors and warnings.
- Every caller sends **`OLLMchat.VERSION`** as the third hello arg; one compile-time constant is shared across app, daemon, examples, and tests.
- Local **`ClientBoot`**: stale daemon binary is replaced at most once per `connect`, then hello is retried.
- Remote connect (`boot == null`): compare only; no spawn.
- Tests and RPC script stubs match the new wire shape.

## Current behavior

- Hello is **`is`** only (`protocol`, client). Reply is a **`Daemon` object** with no version. No compare.
- `ClientBoot` only restarts when the socket is down, not when the binary is stale.
- Repro: install or leave an older `ollmfilesd` on the socket, run a newer desktop build; hello succeeds and RPC proceeds with mismatched semantics.

## Codebase observed behavior

- [`ollmfilesd/Daemon.vala`](../../ollmfilesd/Daemon.vala) registers hello as **`is`**; handler returns a **`Daemon` object**, not a version string.

```vala
"hello", "is",
```

```vala
request.reply(new OLLMrpc.Response() {
	retval = OLLMrpc.val("o", this)
});
```

- [`ollmapp/Window.vala`](../../ollmapp/Window.vala) (and CLI, Android, settings rows, tests, examples) send two args only — e.g. desktop:

```vala
args = OLLMrpc.args("is", 1, "ollmchat")
```

- [`libocrpc/Client.vala`](../../libocrpc/Client.vala) `connect`: hello succeeds when `response.error == null`; no read of version from `retval`.

```vala
if (hello.error != null) {
	…
}
GLib.debug("connect ok hello id=%d", hello_request.id);
return true;
```

- Argus reference (out of tree): hello args **`iss`**, reply **`retval` `s`**; server `strverscmp`; client `GLib.strcmp` + `collate_key_for_filename()`.
- [`ollmapp/version.vala.in`](../../ollmapp/version.vala.in) **`OLLMapp.APP_VERSION`** is git-date UI text, not the Meson release string used for pairing.

## Debugging

### Current debug output

No log capture yet — evidence so far is static inspection under **Codebase observed behavior**; planned runs are in **LLM**.

### Debug code added (remove when complete)

None.

## Proposed fix

Implement the Argus hello contract in this tree. **Do not** change unrelated RPC or add a parallel design.

Apply topics **in order** (1 → 7). Each topic owns its **Remove** / **Replace with** / **Add** fences.

---

### Topic 1 — `OLLMchat.VERSION` (Meson release)

**Why:** One compile-time string for app, daemon, examples, and tests — `meson.build` `project(..., version: '…')`, same pattern as Argus `paths.vala.in`.

**Where:** new `libollmchat/version.vala.in`; `libollmchat/meson.build`; optional `docs/meson.build` valadoc list (keep in sync with library sources).

#### Add — `libollmchat/version.vala.in`

```vala
namespace OLLMchat {
	public const string VERSION = "@VERSION@";
}
```

#### Add — `libollmchat/meson.build` (before `ollmchat_ollama_src`)

```meson
version_vala = configure_file(
	input: 'version.vala.in',
	output: 'version.vala',
	configuration: { 'VERSION': meson.project_version() }
)
```

#### Replace with — `libollmchat/meson.build` `ollmchat_ollama_src` list (first entry)

```meson
ollmchat_ollama_src = files([
  version_vala,
  'ApplicationInterface.vala',
```

*(Keep the rest of the file list unchanged.)*

ℹ️ `ollmfilesd` already links `ollmchat_base_lib` / `--pkg=ollmchat`; no extra meson in `ollmfilesd/` beyond using `OLLMchat.VERSION` in `Daemon.vala`.

---

### Topic 2 — `ollmfilesd/Daemon.vala` server hello

**Why:** Match Argus `server/Daemon.vala`: third arg client version, string `retval`, `strverscmp` gate.

**Where:** top of `ollmfilesd/Daemon.vala`; `rpc_register`; replace `hello` method. `shutdown` and `Bin.Serializable` wire type stay.

#### Add — file scope (after `namespace OLLMfilesd {`)

```vala
	[CCode (cname = "strverscmp", cheader_filename = "string.h", feature_test_macro = "_GNU_SOURCE")]
	extern int strverscmp (string s1, string s2);
```

#### Remove — `rpc_register` hello signature

```vala
				"hello", "is",
```

#### Replace with

```vala
				"hello", "iss",
```

#### Remove — entire `hello` method

```vala
		public void hello(OLLMrpc.Request request, int protocol, string client)
		{
			if (protocol > 0) {
				this.protocol = protocol;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", this)
			});
		}
```

#### Replace with

```vala
		/**
		 * Answer the first RPC on the socket or TLS port.
		 *
		 * Compares the client version with {@link OLLMchat.VERSION}.
		 * A newer client is refused. An older client is warned and
		 * accepted. The reply value is this server's version string.
		 *
		 * @param request inbound RPC
		 * @param protocol client protocol number
		 * @param client client name
		 * @param version client {@link OLLMchat.VERSION}, or null from an older client
		 */
		public void hello(
			OLLMrpc.Request request,
			int protocol,
			string client,
			string? version = null
		)
		{
			var theirs = (version == null || version == "") ? "0.0.0" : version;
			GLib.debug("hello %s %d %s", client, protocol, theirs);
			var mine = OLLMchat.VERSION;
			var order = strverscmp(theirs, mine);
			if (order > 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_PARAMS(
						"The server is " + mine + ". This client is " + theirs + ".")
				});
				return;
			}
			var notice = "ok";
			if (order < 0) {
				notice = "This client is " + theirs + ". The server is " + mine + ".";
				GLib.warning("%s", notice);
			}
			request.reply(new OLLMrpc.Response() {
				msg = notice,
				retval = OLLMrpc.val("s", mine)
			});
		}
```

---

### Topic 3 — `libocrpc/Client.connect` version gate and one local respawn

**Why:** Central post-hello compare for every caller; local `ClientBoot` may replace a stale daemon once when the server is older than the client.

**Where:** `libocrpc/Client.vala` `connect`, bin/TCP path only (after HTTP early returns, from `hello_request.id = …` through successful hello). **No new methods or fields.** Inline only.

**Depends on:** Topic 2 (server returns `s`).

**Flow:**

1. After `wait_response` for hello, if `hello.error != null` and code is `INVALID_PARAMS` and `boot != null` and not yet respawned → `disconnect()`, `yield boot.kill()`, `yield boot.ensure_daemon()`, reopen socket and streams, **one** repeat of hello (not unbounded).
2. If hello still errors → existing fail path (`connect_error`, `disconnect`, `return false`).
3. On hello success: read `server_version` from `hello.retval` (`s`, default `0.0.0`); read `client_version` from `hello_request.args` index 2 (default `0.0.0`).
4. `order = GLib.strcmp(client_version.collate_key_for_filename(), server_version.collate_key_for_filename())`.
5. `order > 0` → fail with Argus message; if `boot != null` and not respawned, same respawn path as (1) once; else `disconnect`, `return false`.
6. `order < 0` → `GLib.warning` Argus warning; connect succeeds.
7. `order == 0` → connect succeeds.
8. Remote (`boot == null`): compare only; no `kill()`.

Apply **Part 1** then **Part 2** (ordered chunk).

#### Part 1 — loop shell and respawn flag

**Where:** immediately before `hello_request.id = this.next_id++;` in `connect`.

##### Add

```vala
			var respawned = false;
```

##### Add — after socket, TLS, `read_watch` setup, **replace** the single hello send/wait block with a `for` that allows at most two passes when `boot != null`:

Outer shape (pseudo — implementer merges with existing setup **without** extracting helpers):

```vala
			var passes = boot != null ? 2 : 1;
			for (var pass = 0; pass < passes; pass++) {
				if (pass > 0) {
					this.disconnect();
					try {
						yield boot.kill();
						yield boot.ensure_daemon();
						this.socket = yield boot.connect();
					} catch (GLib.Error e) {
						this.connect_error = e.message != ""
							? e.message
							: "could not start or reach the filesystem daemon (ollmfilesd)";
						GLib.critical("connect %s: %s",
							this.socket_path, this.connect_error);
						return false;
					}
					var bin_in = this.socket.get_input_stream();
					var bin_out = this.socket.get_output_stream();
					/* repeat TLS branch, input/output/bin, read_channel watch
					 * from the existing connect body — same text as first pass */
					this.connected = true;
				}

				hello_request.id = this.next_id++;
				/* existing PendingWrite + send_head + wait_response */

				/* Part 2 version gate — break loop on success;
				 * continue loop on respawn; return false on hard fail */
			}
```

#### Part 2 — post-`wait_response` version gate

**Where:** inside the loop, replacing the block from `if (hello.error != null) {` through `return true` after `connect ok hello`.

##### Remove

```vala
			if (hello.error != null) {
				this.connect_error = hello.error.message != ""
					? hello.error.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				GLib.critical(
					"hello failed id=%d: %s",
					hello_request.id,
					this.connect_error
				);
				this.disconnect();
				return false;
			}

			GLib.debug("connect ok hello id=%d", hello_request.id);
			this.connect_error = "";
			return true;
```

##### Replace with

```vala
			if (hello.error != null) {
				if (boot != null && !respawned
					&& hello.error.code == (int) RpcErrorCode.INVALID_PARAMS) {
					respawned = true;
					continue;
				}
				this.connect_error = hello.error.message != ""
					? hello.error.message
					: "could not start or reach the filesystem daemon (ollmfilesd)";
				GLib.critical(
					"hello failed id=%d: %s",
					hello_request.id,
					this.connect_error
				);
				this.disconnect();
				return false;
			}

			var client_version = "0.0.0";
			if (hello_request.args.size >= 3
				&& hello_request.args.get(2).holds(typeof(string))
				&& hello_request.args.get(2).get_string() != "") {
				client_version = hello_request.args.get(2).get_string();
			}
			var server_version = "0.0.0";
			if (hello.retval.holds(typeof(string))
				&& hello.retval.get_string() != "") {
				server_version = hello.retval.get_string();
			}
			var order = GLib.strcmp(
				client_version.collate_key_for_filename(),
				server_version.collate_key_for_filename());
			if (order > 0) {
				if (boot != null && !respawned) {
					respawned = true;
					continue;
				}
				this.connect_error = "The server is " + server_version
					+ ". This client is " + client_version + ".";
				GLib.critical(
					"hello version id=%d: %s",
					hello_request.id,
					this.connect_error
				);
				this.disconnect();
				return false;
			}
			if (order < 0) {
				GLib.warning(
					"This client is %s. The server is %s.",
					client_version, server_version);
			}

			GLib.debug("connect ok hello id=%d", hello_request.id);
			this.connect_error = "";
			return true;
```

#### Part 3 — doc examples in `libocrpc/Client.vala`

##### Remove (both doc examples)

```vala
	 *     args = OLLMrpc.args("is", 1, "my-app")
```

```vala
	 *     args = OLLMrpc.args("is", 1, "ollmchat")
```

##### Replace with

```vala
	 *     args = OLLMrpc.args("iss", 1, "my-app", OLLMchat.VERSION)
```

```vala
	 *     args = OLLMrpc.args("iss", 1, "ollmchat", OLLMchat.VERSION)
```

ℹ️ Doc-only references use `OLLMchat.VERSION` as the illustrative constant; `libocrpc` does not link `libollmchat`.

---

### Topic 4 — Callers: send `OLLMchat.VERSION` on hello

**Why:** Server and client compares need the third arg.

**Pattern:** In every file below, each hello uses:

```vala
args = OLLMrpc.args("iss", 1, "<client-name>", OLLMchat.VERSION)
```

Keep existing client name strings (`"ollmchat"`, `"ollmchat-cli"`, `"oc-test-source-diff"`, `"review-flow"`, etc.).

| File | Client name (unchanged) |
| ---- | ------------------------- |
| `ollmapp/Window.vala` | `ollmchat` |
| `ollmapp/ollmchat-cli.vala` | `ollmchat-cli` |
| `ollmapp/android/OllmchatWindow.vala` (3 sites) | `ollmchat` |
| `ollmapp/SettingsDialog/FileConnectionRow.vala` (2) | `ollmchat` |
| `ollmapp/SettingsDialog/FileServerRow.vala` | `ollmchat` |
| `libollmchat/Settings/FilesdClient.vala` | `ollmchat` |
| `examples/oc-vector-index.vala` | `oc-vector-index` |
| `examples/oc-vector-search.vala` | `oc-vector-search` |
| `examples/oc-test-source-diff.vala` (4) | `oc-test-source-diff` |
| `tests/source-diff/deletion-bands-baseline.vala` (4) | `oc-test-source-diff` |
| `tests/source-diff/deletion-bands-current.vala` (4) | `oc-test-source-diff` |
| `tests/review-flow-test.vala` | `review-flow` |
| `tests/rpc/filesd-pair-test.vala` | `ollmchat` |

**Example — `ollmapp/Window.vala`**

#### Remove

```vala
				args = OLLMrpc.args("is", 1, "ollmchat")
```

#### Replace with

```vala
				args = OLLMrpc.args("iss", 1, "ollmchat", OLLMchat.VERSION)
```

#### Part — `libocrpc/namespace.vala` and `libocrpc/android/namespace.vala` doc examples

Same **Remove** / **Replace with** as Topic 3 Part 3 (`my-app` name).

#### Part — `libocrpc/Ffi.vala` doc example

#### Remove

```vala
	 *     "RPC-Daemon", typeof(Daemon), "hello", "is"
```

#### Replace with

```vala
	 *     "RPC-Daemon", typeof(Daemon), "hello", "iss"
```

---

### Topic 5 — Tests and stubs (string `retval`)

**Why:** Hello no longer returns `Daemon` object; stubs must answer `s` or empty success where appropriate.

#### `tests/review-flow-test.vala` — stub `RPC-Daemon.hello`

##### Remove

```vala
			case "RPC-Daemon.hello":
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", new OLLMrpc.Daemon() {
						ready = true,
						server = "review-flow"
					})
				});
				break;
```

##### Replace with

```vala
			case "RPC-Daemon.hello":
				request.reply(new OLLMrpc.Response() {
					msg = "ok",
					retval = OLLMrpc.val("s", OLLMchat.VERSION)
				});
				break;
```

##### Remove — connect args in same file

```vala
			args = OLLMrpc.args("is", 1, "review-flow")
```

##### Replace with

```vala
			args = OLLMrpc.args("iss", 1, "review-flow", OLLMchat.VERSION)
```

#### NDJSON RPC scripts under `tests/rpc/*.script.in` and `tests/rpc/t0.script`

**Why:** Wire args for hello must include version string (literal OK for scripts).

##### Replace with — line 2 pattern in each script (example `t1.script.in`)

```json
{"id":1,"method":"RPC-Daemon.hello","*type":"Request","args":[1,"test-rpc","1.4.12"]}
```

ℹ️ Tests that use a minimal `hello` with signature `""` (`client-drop-on-reply-test.vala`, `values-test.vala`) stay as-is unless FFI routing requires `iss` on a live daemon test.

---

### Topic 6 — Release bump (when shipping)

**Why:** Pairing only bites when versions differ across installs.

- Bump root `meson.build` `project(..., version: …)` in the release that ships this handshake; follow `docs/creating-releases.md` for changelog/packages.

## LLM

**Started:** 2026-11-21

**Pointer:** `docs/bug-fix-process.md` · `docs/guide-to-writing-plans.md` — **Checklist for plans**, **Edit syntax contract**. Proposed Vala follows `docs/coding-standards.md`. Shape: `docs/guide-to-writing-bug-reports.md`.

**Copy from Argus:** `/home/alan/gitlive/argusrm/server/Daemon.vala`, `/home/alan/gitlive/argusrm/docs/rpc-commands.md` § `RPC-Daemon.hello`, post-hello compare in `/home/alan/gitlive/argusrm/agent/linux/Application.vala` and `/home/alan/gitlive/argusrm/agent/Connection.vala`, `Argus.VERSION` in `/home/alan/gitlive/argusrm/paths.vala.in`.

### Root cause (analysis)

- ✔️ Hello checks reachability only, not release pairing.
- ✔️ No shared **`OLLMchat.VERSION`** embedded in app and daemon at build time.

### Ruled out

- 🚫 Using `OLLMapp.APP_VERSION` for the handshake (wrong semantics).
- 🚫 Returning a hybrid hello reply (Daemon object **and** version string).
- 🚫 Adding libocrpc → libollmchat dependency for version (`Client.connect` reads version from `hello_request` args and `retval` only).

### Implementation notes

- 💩 First pass keeps today's code path (`boot.ensure_daemon` / `boot.connect` or TCP/socket) **before** the loop; second pass (`pass > 0`) only runs the `kill` / `ensure_daemon` / reconnect / stream re-init block. Do not call `ensure_daemon` twice on the first successful path.
- 💩 Use current `meson.build` `project()` version at apply time for RPC scripts; scripts are not generated.
- ℹ️ Repeat the same **Remove** / **Replace with** for every site in the Topic 4 table. ℹ️ When applying `docs/bugs/2026-10-27-filesd-restart-drops-client.md`, use **`iss`** + `OLLMchat.VERSION` in its reconnect hello block too.
- ℹ️ `ollmfilesd` already links `ollmchat_base_lib` / `--pkg=ollmchat`; no extra meson in `ollmfilesd/` beyond using `OLLMchat.VERSION` in `Daemon.vala`.

### Test plan

- ⏳ Local: old `ollmfilesd` on socket, new app + `ClientBoot` → one kill/spawn, second hello, matching versions → `connect` true.
- ⏳ Remote TLS (`boot == null`): server older → `connect` false, `connect_error` names both versions; no spawn.
- ⏳ Server newer, client older → warning in log, session connects.
- ⏳ `build/oc-test-rpc` (or affected scripts) after `.script.in` arg updates.

### Attempts / changelog

- ✔️ 2026-11-21 — Opened; aligned proposal with Argus `server/Daemon.vala` (string `retval`, no hybrid object).
- ✔️ 2026-11-21 — Expanded bug log with full **Remove** / **Replace with** / **Add** proposal per `docs/guide-to-writing-plans.md`.
- ✔️ 2026-11-23 — Restructured per `docs/guide-to-writing-bug-reports.md`; renamed to `2026-11-21-FEATURE-rpc-daemon-hello-version-mismatch.md`.

### Next

- ⏳ Apply Topics 1–5 in order after approval (Topic 6 at release cut).

### Related

- 🚫 Using hello version mismatch work as the explanation for desktop startup hang after file nav — separate issue (`docs/bugs/done/2026-11-21-FIXED-desktop-startup-hang-after-file-nav.md`).