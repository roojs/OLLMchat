# 8.2.3.6 — HTTPS client (trust private server cert)

**Status:** **PROPOSED** — draft for review; implement after user approval

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md) — Phase 4 HTTPS

**Depends on:** [`done/RPC-8.2.3.4-DONE-http-client.md`](done/RPC-8.2.3.4-DONE-http-client.md); peer [`RPC-8.2.3.5-https-server.md`](RPC-8.2.3.5-https-server.md) (`Transport.Cert`)

**Related:** Parent Phases 5–6; [`docs/android-tls.md`](../android-tls.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** `⏳` `HttpClient` POSTs to **`https://`** with the same JSON / bin / session behaviour as HTTP.
- **🔷** `⏳` Trust the **private** server PEM from **`Cert.trust_pem_path`** (app↔app) — not public CA / Let’s Encrypt.
- **🔷** `⏳` Joint smoke with **8.2.3.5** after `Cert.ensure`.
- **ℹ️** Phase 4 does not present a client certificate (Phase 6).

---

## Trust model

- **🔷** Client: `TlsFileDatabase.@new(cert.trust_pem_path)` → `HttpClient.tls_database`.
- **🔷** System/public roots are not the trust path for our RPC HTTPS smoke.
- **🚫** Let’s Encrypt / public CA install.
- **🚫** Disabling verification as the normal path.

---

## Design

### Named APIs

- **🔷** `HttpClient.tls_database` (`GLib.TlsDatabase?`).
- **🔷** Existing `call` / `reset` / `bin_body` / `session_id` / `sequence` — no new methods.

### Pairing with server

```vala
var cert = OLLMrpc.Transport.Cert.ensure(tls_dir);
http.tls_certificate = cert.certificate;
http.start();
var client = new OLLMrpc.Transport.HttpClient(
	"https://127.0.0.1:%u".printf(http.port)
) {
	tls_database = GLib.TlsFileDatabase.@new(cert.trust_pem_path)
};
```

**ℹ️** How a remote phone receives `trust_pem_path` bytes is app pairing — not this plan.

### Out of scope

- **🚫** Generating the server cert on the client.
- **🚫** Client cert presentation (Phase 6).
- **🚫** Hub `OLLMrpc.Client` changes.

---

## Suggested implement order

1. **Phase 0** — `tls_database` on `HttpClient`.
2. **Phase 1** — `test-rpc-http-https` (server + client).

---

## Phase 0 — `HttpClient.tls_database` — **⏳**

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Transport/HttpClient.vala` — property

**Where:** after the `bin` property block (before `private Soup.Session soup`).

#### Add

```vala
		/**
		 * Trust store for private HTTPS peers ({@link Cert.trust_pem_path}).
		 * Null → Soup platform default (not used for self-signed RPC smoke).
		 */
		public GLib.TlsDatabase? tls_database { get; set; default = null; }
```

### 2. `libocrpc/Transport/HttpClient.vala` — apply in `call`

**Where:** first lines of `call`, after `request.id = this.next_id++;` and before `var url = …`.

#### Add

```vala
			if (this.tls_database != null) {
				this.soup.set_tls_database(this.tls_database);
			}
```

### 3. `libocrpc/Transport/HttpClient.vala` — class docblock example

**Where:** `== Example ==` at top of class.

#### Remove

```vala
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpClient("http://127.0.0.1:8080");
	 * var resp = yield http.call(new OLLMrpc.Request() {
	 *     method = "RPC-Hello.world"
	 * });
	 * http.bin_body = true;
	 * var bin_resp = yield http.call(new OLLMrpc.Request() {
	 *     method = "RPC-Hello.world"
	 * });
	 * }}}
```

#### Replace with

```vala
	 * {{{
	 * var cert = OLLMrpc.Transport.Cert.ensure(tls_dir);
	 * var http = new OLLMrpc.Transport.HttpClient("https://127.0.0.1:8080") {
	 *     tls_database = GLib.TlsFileDatabase.@new(cert.trust_pem_path)
	 * };
	 * var resp = yield http.call(new OLLMrpc.Request() {
	 *     method = "RPC-Hello.world"
	 * });
	 * }}}
```

---

## Phase 1 — Smoke — **⏳**

### 4. `tests/rpc/http-https-test.vala` — new file

**Why:** Prove `Cert.ensure` + HTTPS server + trusting client.

**Where:** new test file.

#### Add — full file

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * HTTPS Rpc smoke — Cert.ensure + HttpServer + HttpClient trust.
 */

namespace RpcDummy
{
	public class Hello : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Hello", typeof(Hello),
				"world", ""
			);
		}

		public void world(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "Hello World"
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcHttpHttps : RpcTestAppBase
	{
		public TestRpcHttpHttps()
		{
			base("com.roojs.ollmchat.test-rpc-http-https");
		}

		protected override string get_app_name()
		{
			return "test-rpc-http-https";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Request.rpc_register();
			OLLMrpc.Response.rpc_register();
			OLLMrpc.Error.rpc_register();
			OLLMrpc.Notification.rpc_register();
			RpcDummy.Hello.rpc_register();
			OLLMrpc.Request.register("RPC-Hello", new RpcDummy.Hello());

			var tls_dir = GLib.DirUtils.make_tmp("ollmrpc-https-XXXXXX");
			var cert = OLLMrpc.Transport.Cert.ensure(tls_dir);
			var http = new OLLMrpc.Transport.HttpServer(0) {
				tls_certificate = cert.certificate
			};
			this.check(command_line, http.start(), "https server start");
			var base_url = "https://127.0.0.1:%u".printf(http.port);

			var client = new OLLMrpc.Transport.HttpClient(base_url) {
				tls_database = GLib.TlsFileDatabase.@new(cert.trust_pem_path)
			};
			OLLMrpc.Response? response = null;
			var err_msg = "";
			var loop = new GLib.MainLoop();
			client.call.begin(new OLLMrpc.Request() {
				method = "RPC-Hello.world"
			}, (obj, res) => {
				try {
					response = client.call.end(res);
				} catch (GLib.Error e) {
					err_msg = e.message;
				}
				loop.quit();
			});
			loop.run();
			this.check(command_line, err_msg == "", "https call error: %s".printf(err_msg));
			this.check(command_line, response != null, "https null response");
			this.check(
				command_line,
				response.msg == "Hello World",
				"https msg=%s".printf(response.msg)
			);
			this.check(
				command_line,
				client.session_id != "",
				"https missing session_id"
			);
			this.check(
				command_line,
				client.sequence == 1,
				"https sequence want 1 got %u".printf(client.sequence)
			);

			http.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcHttpHttps().run(args);
}
```

### 5. `tests/meson.build` — wire test

**Where:** after the `test-rpc-http-client` block.

#### Add

```meson
test_rpc_http_https = executable('test-rpc-http-https',
  'rpc/http-https-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('libsoup-3.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args + [
    '--pkg=libsoup-3.0',
  ],
)
test('test-rpc-http-https',
  test_rpc_http_https,
  suite: 'rpc',
  timeout: 30,
)
```

**ℹ️** Timeout 30s — first `Cert.ensure` may mint via GnuTLS (CPU, not a subprocess).

---

## Backlog

- **🔷** `⏳` Implement with **8.2.3.5**.
- **🔷** `⏳` Phase 6 — client cert on reconnect.
- **💩** `⏳` App pairing UX that copies `trust_pem_path` to the phone.

---

## LLM notes

- **🚫** Do not implement until user approves.
- **ℹ️** `GLib.TlsFileDatabase.@new` is the Vala name for `g_tls_file_database_new`.
- **ℹ️** After implement, mark **✔️**; user promotes **✅**.
