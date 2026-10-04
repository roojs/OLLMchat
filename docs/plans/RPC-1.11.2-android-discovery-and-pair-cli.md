# RPC-1.11.2 — Android discovery and pairing CLI

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** implemented, not confirmed on a device

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11-URGENT-vpn-local-pin-pairing.md`](RPC-1.11-URGENT-vpn-local-pin-pairing.md) — Phase 4

**Depends on:** Phase 3 in [`RPC-1.11.1`](RPC-1.11.1-pin-registration-and-android.md) (PIN check, CSR, signed cert, address list)

---

## Purpose

- **🔷** `✔️` A command-line program pairs against a running server while the PIN dialog is open, so the TLS bin path can be checked without a phone.
- **🔷** `✔️` Android **Add connection** finds that server over mDNS, then asks for the PIN. No typed IP.
- **🔷** `✔️` The phone dialog is its own file. Meson compiles that file on Android and the desktop file on the desktop. No `#if ANDROID` inside `FileConnectionAdd`.
- **🔷** `✔️` The phone stores every returned address and, on later starts, connects to one that answers.
- **ℹ️** The PIN dialog, listen choice, mDNS publish, and the registration reply are Phases 1–3.

---

## Phase 4 — Android discovery, route selection, and the pairing CLI

### Goal

- **🔷** `✔️` A command-line program connects to the TLS bin socket, sends the CSR file and the PIN, writes the signed certificate and the CA back onto the files `Cert.ensure()` already uses, then calls `RPC-Daemon.hello` with that certificate. A reply that only prints the PEMs is not a pass.
- **🔷** `✔️` **Add connection** on the phone shows **Listening for connection** and browses for the pairing service. No manual IP entry. The six-digit prompt waits until mDNS finds the server.
- **🔷** `✔️` Browse with Android `NsdManager` (`android.net.nsd`) through JNI, same pattern as `ollmapp/android/android-partial-wake-lock.c`. The service type is `_rpc._tcp`, the type `PairPublish` registers. `Avahi.ServiceBrowser` does not run on the phone.
- **🔷** `✔️` After discovery, prompt for the six digits.
- **🔷** `✔️` Connect the TLS bin socket, send CSR + PIN, read the signed cert and the address list.
- **🔷** `✔️` Store every returned address with the connection, including the VPN address and the local address.
- **🔷** `✔️` On each app start, probe the stored addresses and connect to one that answers.
  - 2-second timeout per address
  - In the house or the office the local address answers
  - Outside, the local network is absent, so the stored VPN address is the one that answers
- **🔷** `⏳` Later RPC stays on that bin socket so server notifications have a live connection.

### Notes

- **ℹ️** Phase 3 removed the HTTPS `request_registration` post from `FileConnectionAdd`. This phase puts the socket path (`FilesdClient.State.SOCKET`) in `ollmapp/android/FileConnectionAdd.vala`. The desktop file stays the URL dialog.
- **ℹ️** `OLLMchat.Settings.FilesdClient` stores one `url` today. This phase stores the full address list beside that connection. `url` stays the `tcp://host:port` that answered, so the existing “url is set” checks still run.
- **ℹ️** [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) sent the phone to HTTPS when it left the LAN. This plan does not add that downgrade. Notifications need the socket.
- **🔷** The program is `tests/rpc/filesd-pair-test.vala`, executable `test-rpc-filesd-pair`. It is a manual run, not a `meson test()`, same as `test-rpc-filesd-http-client`. The current build has `-Dtests=false`, so this target appears only after tests are turned on.
- **🔷** Flags are `--host`, `--port`, and `--pin`. An empty host reads `filesd.socket` from `config.2.json`. The PIN has no default.
- **ℹ️** The test does not generate a key or a CSR. `OLLMrpc.Transport.Cert.ensure()` already writes `client.pem` and `client-key.pem` for the app (`cn` `ollmchat-device`, dir `~/.local/share/ollmchat`). `request_registration` still wants a CSR PEM, and `Cert` does not write one today, so §1 adds that file next to the key. The test reads `client.csr`, and after a match writes the returned client PEM and CA PEM over `client.pem` and `ollmrpc-ca.pem`. The second `ensure()` loads those files. `product_ca_resource` stays false: a true value rewrites the trust file from the bundled product CA and would wipe the CA just returned.
- **ℹ️** The first handshake has no CA yet, so it accepts the server certificate. The PIN is the authorization. The second handshake presents the written client certificate and accepts the server only when `(errors & ~BAD_IDENTITY) == 0`, the same check the daemon uses once the PIN window is closed. Hello is `RPC-Daemon.hello` with `args("is", 1, "ollmchat")`, the call `OllmchatWindow.initialize_client` already sends.
- **ℹ️** `OLLMrpc.Client` TCP is plaintext, and on Android `Client.connect` drops the socket because the read watch is a Unix `IOChannel`. The test and the phone’s hello are a connect, handshake, write, read, close on the TLS bin socket. Holding that socket open for notifications is still the goal above; these fences do not add an Android read watch.
- **ℹ️** The requester string on `request_registration` is `ollmchat`, the same name hello already sends.

### 1. `libocrpc/Transport/Cert.vala` — write the CSR beside the key

**Why:** The test and the phone read a file. They do not call GnuTLS themselves. `request_registration` imports a certificate request, and `ensure()` today writes a certificate, not a request.

**Where:** `create_pem_files`, immediately before the `try` that writes `key_path` and `cert_path`. And `ensure()`, immediately after `this.certificate` is set from existing files, only when the CSR file is missing.

**Depends on:** Phase 3.

#### Add — inside `create_pem_files`, before `GLib.FileUtils.set_contents(key_path, ...)`

The key object is already in scope. `client.pem` becomes `client.csr` in the same directory. The server’s `server.pem` likewise gets a sibling `server.csr`; nothing reads that one.

```vala
			var csr_path = cert_path.substring(0, cert_path.last_index_of(".")) + ".csr";
			var crq = GnuTLS.X509.CertificateRequest.create();
			var crq_dn = crq.set_dn_by_oid("2.5.4.3", 0, this.cn, this.cn.length);
			if (crq_dn < 0) {
				GLib.error("crq set_dn: %s", ((GnuTLS.ErrorCode)crq_dn).to_string());
			}
			var crq_key = crq.set_key(key);
			if (crq_key < 0) {
				GLib.error("crq set_key: %s", ((GnuTLS.ErrorCode)crq_key).to_string());
			}
			var crq_sign = crq.sign2(key, GnuTLS.DigestAlgorithm.SHA256, 0);
			if (crq_sign < 0) {
				GLib.error("crq sign: %s", ((GnuTLS.ErrorCode)crq_sign).to_string());
			}
			var crq_len = (size_t)0;
			crq.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crq_len);
			var crq_pem = new uint8[crq_len];
			var crq_exp = crq.export(
				GnuTLS.X509.CertificateFormat.PEM, crq_pem, ref crq_len);
			if (crq_exp < 0) {
				GLib.error("crq export: %s", ((GnuTLS.ErrorCode)crq_exp).to_string());
			}
			try {
				GLib.FileUtils.set_contents(csr_path, (string) crq_pem);
			} catch (GLib.Error e) {
				GLib.error("write %s: %s", csr_path, e.message);
			}
```

#### Add — in `ensure()`, after a successful `from_files` on an existing key

A device that already has `client.pem` never re-enters `create_pem_files`. Load that key and write the CSR once.

```vala
				var csr_path = cert_path.substring(0, cert_path.last_index_of(".")) + ".csr";
				if (!GLib.FileUtils.test(csr_path, GLib.FileTest.EXISTS)) {
					string key_text;
					GLib.FileUtils.get_contents(key_path, out key_text);
					var init_ret = GnuTLS.global_init();
					if (init_ret < 0) {
						GLib.error("gnutls_global_init: %s",
							((GnuTLS.ErrorCode)init_ret).to_string());
					}
					var key = GnuTLS.X509.PrivateKey.create();
					var key_datum = GnuTLS.Datum() {
						data = (uint8[]) key_text.to_utf8(),
						size = key_text.length
					};
					var key_imp = key.import(
						ref key_datum, GnuTLS.X509.CertificateFormat.PEM);
					if (key_imp < 0) {
						GLib.error("key import: %s",
							((GnuTLS.ErrorCode)key_imp).to_string());
					}
					var crq = GnuTLS.X509.CertificateRequest.create();
					var crq_dn = crq.set_dn_by_oid(
						"2.5.4.3", 0, this.cn, this.cn.length);
					if (crq_dn < 0) {
						GLib.error("crq set_dn: %s",
							((GnuTLS.ErrorCode)crq_dn).to_string());
					}
					var crq_key = crq.set_key(key);
					if (crq_key < 0) {
						GLib.error("crq set_key: %s",
							((GnuTLS.ErrorCode)crq_key).to_string());
					}
					var crq_sign = crq.sign2(key, GnuTLS.DigestAlgorithm.SHA256, 0);
					if (crq_sign < 0) {
						GLib.error("crq sign: %s",
							((GnuTLS.ErrorCode)crq_sign).to_string());
					}
					var crq_len = (size_t)0;
					crq.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crq_len);
					var crq_pem = new uint8[crq_len];
					var crq_exp = crq.export(
						GnuTLS.X509.CertificateFormat.PEM, crq_pem, ref crq_len);
					if (crq_exp < 0) {
						GLib.error("crq export: %s",
							((GnuTLS.ErrorCode)crq_exp).to_string());
					}
					GLib.FileUtils.set_contents(csr_path, (string) crq_pem);
				}
```

### 2. `tests/rpc/filesd-pair-test.vala` — pair, write the files, hello

**Why:** Open **Allow New Device**, read the six digits, and run this program. A match writes the certificates and prints hello. A wrong PIN prints **number rejected** and does not hello.

**Where:** new file. Wired in `tests/meson.build` next to `test-rpc-filesd-http-client`.

**Depends on:** §1 and Phase 3.

#### Add — new file

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Manual TLS bin client against a live ollmfilesd. Sends
 * ClientCert.request_registration while the desktop PIN dialog
 * is open, writes the returned PEMs with Cert, then hello.
 */

namespace OLLMrpcTests
{
	class TestRpcFilesdPair : RpcTestAppBase
	{
		protected static string opt_host = "";
		protected static int opt_port = 0;
		protected static string opt_pin = "";

		protected override string help { get; set; default = """
Usage: {ARG} [--host=IP] [--port=N] --pin=DIGITS

Talk to a running ollmfilesd TLS bin listener while Allow New
Device is open. Reads client.csr from the app cert directory,
writes the signed cert and CA back, then RPC-Daemon.hello.
"""; }

		public override int run(string[] args)
		{
			var context = new GLib.OptionContext(this.help);
			var entries = new GLib.OptionEntry[4];
			entries[0] = { "host", 0, 0, OptionArg.STRING, ref opt_host,
				"TLS bin host. Empty reads filesd.socket.", "IP" };
			entries[1] = { "port", 0, 0, OptionArg.INT, ref opt_port,
				"TLS bin port. 0 reads filesd.socket.", "N" };
			entries[2] = { "pin", 0, 0, OptionArg.STRING, ref opt_pin,
				"Six digits from Allow New Device.", "DIGITS" };
			entries[3] = { null };
			context.add_main_entries(entries, null);
			return base.run(args);
		}

		protected override void run_rpc_test(GLib.ApplicationCommandLine command_line)
		{
			var host = opt_host;
			var port = opt_port;
			if (host == "" || port == 0) {
				var socket = this.base_load_config().filesd.socket;
				var colon = socket.last_index_of(":");
				this.check(command_line, colon > 0, "filesd.socket has no port");
				if (host == "") {
					host = socket.substring(0, colon);
				}
				if (port == 0) {
					this.check(command_line,
						int.try_parse(socket.substring(colon + 1), out port),
						"filesd.socket port");
				}
			}
			this.check(command_line, opt_pin != "", "--pin is required");
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = false
			};
			tls_files.ensure();
			string csr;
			var csr_path = GLib.Path.build_filename(dir, "client.csr");
			this.check(command_line,
				GLib.FileUtils.get_contents(csr_path, out csr),
				"read " + csr_path);

			var client = new GLib.SocketClient();
			var conn = client.connect_to_host(host, (uint16) port);
			var tls = GLib.TlsClientConnection.@new(conn, null);
			tls.accept_certificate.connect((peer_cert, errors) => {
				return true;
			});
			tls.handshake();
			var bin = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls.get_input_stream()),
				new GLib.DataOutputStream(tls.get_output_stream())
			);
			bin.write(new OLLMrpc.Request() {
				method = "ClientCert.request_registration",
				args = OLLMrpc.args("sss", opt_pin, csr, "ollmchat")
			});
			var response = bin.parse() as OLLMrpc.Response;
			this.check(command_line, response != null, "reply was not a response");
			if (response.error != null) {
				command_line.print("%s\n", response.error.message);
				return;
			}
			this.check(command_line, response.msg == "ok", "msg=" + response.msg);
			var packed = (string[]) response.retval;
			this.check(command_line, packed.length >= 2,
				"reply needs a client cert and a CA");
			GLib.FileUtils.set_contents(
				GLib.Path.build_filename(dir, "client.pem"), packed[0]);
			GLib.FileUtils.set_contents(
				GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
			tls_files.ensure();
			for (var i = 2; i < packed.length; i++) {
				command_line.print("address %s\n", packed[i]);
			}

			var again = client.connect_to_host(host, (uint16) port);
			var tls2 = GLib.TlsClientConnection.@new(again, null);
			tls2.certificate = tls_files.certificate;
			tls2.database = tls_files.trust;
			tls2.accept_certificate.connect((peer_cert, errors) => {
				return peer_cert != null
					&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
			});
			tls2.handshake();
			var bin2 = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls2.get_input_stream()),
				new GLib.DataOutputStream(tls2.get_output_stream())
			);
			bin2.write(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			});
			var hello = bin2.parse() as OLLMrpc.Response;
			this.check(command_line, hello != null, "hello was not a response");
			this.check(command_line, hello.error == null,
				hello.error != null ? hello.error.message : "");
			this.check(command_line, hello.msg == "ok", "hello msg=" + hello.msg);
			command_line.print("hello ok\n");
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcFilesdPair().run(args);
}
```

### 3. `tests/meson.build` — build the pairing client

**Why:** Same manual executable pattern as `test-rpc-filesd-http-client`. The test does not call GnuTLS; `libocrpc` already does.

**Where:** on the line after the `test-rpc-filesd-http-client` `vala_args` block.

**Depends on:** §2.

#### Add

```meson
test_rpc_filesd_pair = executable('test-rpc-filesd-pair',
  'rpc/filesd-pair-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args,
)
```

### 4. `libollmchat/Settings/FilesdClient.vala` — store every address

**Why:** The registration reply is more than one `host:port`. Startup tries each one.

**Where:** after the `url` property.

**Depends on:** Phase 3.

#### Add

One `host:port` per line. JSON stays a string, same as `url`.

```vala
		/**
		 * Every ''host:port'' from the last successful pairing reply,
		 * one per line. Empty when this phone has not paired.
		 */
		public string addresses { get; set; default = ""; }
```

### 5. `android/PairBrowse.java` — browse `_rpc._tcp`

**Why:** The phone finds the desktop the PIN dialog is publishing. No typed IP.

**Where:** new file, next to `android/PartialWakeLock.java`.

**Depends on:** `PairPublish` service type `_rpc._tcp`.

#### Add — new file

Discovery runs on the Android main looper. Vala polls. The first resolved host and port win; the reply’s address list is what gets stored.

- **🔷** Two helpers, `browse` and `resolve`. `start` only posts `browse`. `onServiceFound` calls `resolve`, so the resolve listener is not nested inside the discovery listener.

```java
package org.roojs.ollmchat.androidpoc;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Handler;
import android.os.Looper;

public final class PairBrowse {
	private static NsdManager manager;
	private static NsdManager.DiscoveryListener listener;
	private static volatile String found = "";

	private PairBrowse() {
	}

	public static void start(Context context) {
		found = "";
		if (context == null) {
			found = "none";
			return;
		}
		new Handler(Looper.getMainLooper()).post(() -> browse(context));
	}

	private static void browse(Context context) {
		NsdManager nsd = (NsdManager) context.getApplicationContext()
			.getSystemService(Context.NSD_SERVICE);
		if (nsd == null) {
			found = "none";
			return;
		}
		manager = nsd;
		listener = new NsdManager.DiscoveryListener() {
			public void onDiscoveryStarted(String type) {
			}

			public void onDiscoveryStopped(String type) {
			}

			public void onStartDiscoveryFailed(String type, int error) {
				found = "none";
			}

			public void onStopDiscoveryFailed(String type, int error) {
			}

			public void onServiceLost(NsdServiceInfo info) {
			}

			public void onServiceFound(NsdServiceInfo info) {
				if (found != null && found.length() > 0 && !found.equals("none")) {
					return;
				}
				resolve(nsd, info);
			}
		};
		nsd.discoverServices("_rpc._tcp.", NsdManager.PROTOCOL_DNS_SD, listener);
		new Handler(Looper.getMainLooper()).postDelayed(() -> {
			if (found == null || found.length() == 0) {
				found = "none";
			}
			stop(context);
		}, 30000);
	}

	private static void resolve(NsdManager nsd, NsdServiceInfo info) {
		nsd.resolveService(info, new NsdManager.ResolveListener() {
			public void onResolveFailed(NsdServiceInfo failed, int error) {
			}

			public void onServiceResolved(NsdServiceInfo resolved) {
				if (resolved.getHost() == null) {
					return;
				}
				found = resolved.getHost().getHostAddress()
					+ ":" + resolved.getPort();
			}
		});
	}

	public static String poll() {
		return found == null ? "" : found;
	}

	public static void stop(Context context) {
		new Handler(Looper.getMainLooper()).post(() -> {
			if (manager != null && listener != null) {
				try {
					manager.stopServiceDiscovery(listener);
				} catch (IllegalArgumentException ignored) {
				}
				listener = null;
			}
		});
	}
}
```

### 6. `scripts/android/build-pixiewood-apk.sh` — install `PairBrowse.java`

**Why:** `install_poc_java` copies the POC Java sources into the Pixiewood tree. A new file that is not copied is not on the phone.

**Where:** `install_poc_java`, next to the `PartialWakeLock.java` copy.

**Depends on:** §5.

#### Add

```sh
  local browse_src="$ROOT_DIR/android/PairBrowse.java"
```

and, after the `PartialWakeLock.java` copy:

```sh
  if [ ! -f "$browse_src" ]; then
    echo "PairBrowse.java missing: $browse_src" >&2
    exit 1
  fi
  cp -a "$browse_src" "$dest_dir/PairBrowse.java"
```

### 7. `ollmapp/android/android-pair-browse.c` and header — JNI, same as the wake lock

**Why:** Vala starts the browse and polls it. `g_module_open` does not run `JNI_OnLoad`, so this file uses the same `JNI_GetCreatedJavaVMs` lookup as `android-partial-wake-lock.c`.

**Where:** new `ollmapp/android/android-pair-browse.h` and `ollmapp/android/android-pair-browse.c`. Add `'android/android-pair-browse.c'` to `android_poc_sources` in `ollmapp/meson.build` next to `android-partial-wake-lock.c`.

**Depends on:** §5.

#### Add — `ollmapp/android/android-pair-browse.h`

```c
#pragma once

#include <glib.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

void ollmapp_android_pair_browse_start (GtkWindow *window);
char *ollmapp_android_pair_browse_poll (void);
void ollmapp_android_pair_browse_stop (GtkWindow *window);

G_END_DECLS
```

#### Add — `ollmapp/android/android-pair-browse.c`

Copy `ollmapp_android_jni_env` and `ollmapp_android_load_class` from `android-partial-wake-lock.c` into this file (those functions are file-local). Then:

```c
static jobject
ollmapp_android_activity (GtkWindow *window, JNIEnv **env_out)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;

	*env_out = NULL;
	if (window == NULL) {
		return NULL;
	}
	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return NULL;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		return NULL;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		(*env)->DeleteLocalRef (env, activity);
		return NULL;
	}
	*env_out = env;
	return activity;
}

void
ollmapp_android_pair_browse_start (GtkWindow *window)
{
	JNIEnv *env = NULL;
	jobject activity;
	jclass cls;
	jmethodID mid;

	activity = ollmapp_android_activity (window, &env);
	if (activity == NULL) {
		return;
	}
	cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "start",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, cls, mid, activity);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
	(*env)->DeleteLocalRef (env, cls);
	(*env)->DeleteLocalRef (env, activity);
}

char *
ollmapp_android_pair_browse_poll (void)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jstring value;
	const char *utf;
	char *copy;

	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return g_strdup ("");
	}
	cls = (*env)->FindClass (env, "org/roojs/ollmchat/androidpoc/PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
	mid = (*env)->GetStaticMethodID (env, cls, "poll",
		"()Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, cls);
		return g_strdup ("");
	}
	value = (*env)->CallStaticObjectMethod (env, cls, mid);
	if (value == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, cls);
		return g_strdup ("");
	}
	utf = (*env)->GetStringUTFChars (env, value, NULL);
	copy = g_strdup (utf != NULL ? utf : "");
	if (utf != NULL) {
		(*env)->ReleaseStringUTFChars (env, value, utf);
	}
	(*env)->DeleteLocalRef (env, value);
	(*env)->DeleteLocalRef (env, cls);
	return copy;
}

void
ollmapp_android_pair_browse_stop (GtkWindow *window)
{
	JNIEnv *env = NULL;
	jobject activity;
	jclass cls;
	jmethodID mid;

	activity = ollmapp_android_activity (window, &env);
	if (activity == NULL) {
		return;
	}
	cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "stop",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, cls, mid, activity);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
	(*env)->DeleteLocalRef (env, cls);
	(*env)->DeleteLocalRef (env, activity);
}
```

`poll` uses `FindClass` because it has no activity. If that returns null on the phone, switch it to `load_class` with the activity the same way `start` does, and pass the window in.

### 8. `ollmapp/meson.build` — compile the phone dialog, not the desktop one

**Why:** The phone Add connection dialog and the desktop one differ enough that they are two files. The phone build lists the phone file. The desktop build lists the desktop file. Neither file contains `#if ANDROID`.

**Where:** `android_poc_sources`, after `android/AndroidBootstrapConnectionAdd.vala`. And `android_poc_settings_sources`, the `FileConnectionAdd.vala` line.

**Depends on:** none.

#### Remove

```meson
    'android/AndroidBootstrapConnectionAdd.vala',
    'android/AndroidToolsRegistration.vala',
```

#### Replace with

Phone sources gain the phone dialog.

```meson
    'android/AndroidBootstrapConnectionAdd.vala',
    'android/FileConnectionAdd.vala',
    'android/AndroidToolsRegistration.vala',
```

#### Remove

```meson
    'SettingsDialog/ConnectionRow.vala',
    'SettingsDialog/FileConnectionAdd.vala',
    'SettingsDialog/FileConnectionRow.vala',
```

#### Replace with

The phone source list no longer compiles the desktop dialog.

```meson
    'SettingsDialog/ConnectionRow.vala',
    'SettingsDialog/FileConnectionRow.vala',
```

`ollmchat_sources` still lists `SettingsDialog/FileConnectionAdd.vala`. That is the desktop executable.

### 9. `ollmapp/android/FileConnectionAdd.vala` — listen, PIN, write certs, hello

**Why:** Android Add connection browses, then asks for the six digits, then does the same file read / file write / hello as the CLI. This file is that dialog. It is not an ifdef inside the desktop file.

**Where:** new file. Same namespace and class name as the desktop dialog, so `ConnectionsPage` calls it unchanged.

**Depends on:** §1, §4, §7, §8.

- **🔷** Browse starts from an idle queued in `show_add`. `ConnectionsPage` calls `show_add` before `present`, so `get_root()` is still null in `show_add` itself. The idle runs after `present`.
- **🔷** Each call that throws sits in its own `try`. Setup and the reply checks stay outside.

#### Add — new file

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMapp.SettingsDialog
{
	/**
	 * Phone dialog for the outbound file-server connection.
	 *
	 * Listens for the pairing service, then asks for the six digits.
	 */
	public class FileConnectionAdd : Adw.PreferencesDialog
	{
		/**
		 * ''tcp://host:port'' that answered hello. Null until then.
		 * {@link ConnectionsPage} reads this on {@link dialog_closed}.
		 */
		public string? registered_url { get; private set; }

		/**
		 * Every ''host:port'' from the reply, one per line.
		 */
		public string registered_addresses { get; private set; default = ""; }

		private Gtk.Label listen_label;
		private Gtk.Entry pin_entry;
		private Gtk.Button request_button;
		private Adw.PreferencesGroup group;
		private string found = "";
		private uint browse_id = 0;

		public signal void error_occurred(string error_message);
		public signal void dialog_closed();

		public FileConnectionAdd()
		{
			this.title = "Add Remote Desktop Environment";
			this.set_content_height(360);
			this.set_content_width(720);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup() {
				description = "Listening for connection"
			};
			this.listen_label = new Gtk.Label("Listening for connection") {
				wrap = true,
				xalign = 0
			};
			this.group.add(this.listen_label);
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "Six digits",
				visible = false,
				max_length = 6
			};
			var pin_row = new Adw.ActionRow() {
				title = "PIN"
			};
			pin_row.add_suffix(this.pin_entry);
			this.group.add(pin_row);
			page.add(this.group);

			this.request_button = new Gtk.Button() {
				label = "Request",
				css_classes = {"suggested-action"},
				sensitive = false
			};
			var footer = new Adw.PreferencesGroup();
			footer.add(this.request_button);
			page.add(footer);
			this.add(page);

			this.pin_entry.changed.connect(() => {
				this.request_button.sensitive = this.pin_entry.text.length == 6;
			});
			this.request_button.clicked.connect(() => {
				this.request.begin();
			});
			this.closed.connect(() => {
				this.can_close = true;
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				var root = this.get_root() as Gtk.Window;
				if (root != null) {
					android_pair_browse_stop(root);
				}
				this.pin_entry.text = "";
				this.request_button.sensitive = false;
				this.dialog_closed();
			});
		}

		/**
		 * Prepares the dialog before {@link Gtk.Window.present}.
		 */
		public void show_add()
		{
			this.registered_url = null;
			this.registered_addresses = "";
			this.found = "";
			this.pin_entry.text = "";
			this.pin_entry.visible = false;
			this.listen_label.label = "Listening for connection";
			this.request_button.sensitive = false;
			if (this.browse_id != 0) {
				GLib.Source.remove(this.browse_id);
				this.browse_id = 0;
			}
			this.browse_id = GLib.Idle.add(() => {
				this.browse_id = 0;
				var window = this.get_root() as Gtk.Window;
				if (window == null) {
					this.listen_label.label = "No desktop found";
					return false;
				}
				android_pair_browse_start(window);
				this.browse_id = GLib.Timeout.add(200, () => {
					var hit = android_pair_browse_poll();
					if (hit == "") {
						return true;
					}
					var root = this.get_root() as Gtk.Window;
					if (root != null) {
						android_pair_browse_stop(root);
					}
					this.browse_id = 0;
					if (hit == "none") {
						this.listen_label.label = "No desktop found";
						return false;
					}
					this.found = hit;
					this.listen_label.label = hit;
					this.pin_entry.visible = true;
					return false;
				});
				return false;
			});
		}

		private async void request()
		{
			if (this.found == "") {
				this.error_occurred("No desktop found");
				return;
			}
			var pin = this.pin_entry.text.strip();
			if (pin.length != 6) {
				this.error_occurred("Enter the six digits");
				return;
			}
			var colon = this.found.last_index_of(":");
			if (colon <= 0) {
				this.error_occurred("Bad address");
				return;
			}
			var port = 0;
			if (!int.try_parse(this.found.substring(colon + 1), out port)) {
				this.error_occurred("Bad address");
				return;
			}
			var host = this.found.substring(0, colon);
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = false
			};
			tls_files.ensure();
			var csr = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "client.csr"), out csr);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			var client = new GLib.SocketClient();
			GLib.SocketConnection conn;
			try {
				conn = client.connect_to_host(host, (uint16) port);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			GLib.TlsClientConnection tls;
			try {
				tls = GLib.TlsClientConnection.@new(conn, null);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			tls.accept_certificate.connect((peer_cert, errors) => {
				return true;
			});
			try {
				tls.handshake();
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			OLLMrpc.Bin.Stream bin;
			try {
				bin = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(tls.get_input_stream()),
					new GLib.DataOutputStream(tls.get_output_stream())
				);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			try {
				bin.write(new OLLMrpc.Request() {
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, "ollmchat")
				});
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			OLLMrpc.Serializable parsed;
			try {
				parsed = bin.parse();
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			var response = parsed as OLLMrpc.Response;
			if (response == null) {
				this.error_occurred("reply was not a response");
				return;
			}
			if (response.error != null) {
				this.error_occurred(response.error.message);
				return;
			}
			var packed = (string[]) response.retval;
			if (packed.length < 2) {
				this.error_occurred("reply needs a client cert and a CA");
				return;
			}
			try {
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(dir, "client.pem"), packed[0]);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			try {
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			tls_files.ensure();
			this.registered_addresses = string.joinv("\n", packed[2:packed.length]);
			GLib.SocketConnection again;
			try {
				again = client.connect_to_host(host, (uint16) port);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			GLib.TlsClientConnection tls2;
			try {
				tls2 = GLib.TlsClientConnection.@new(again, null);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			tls2.certificate = tls_files.certificate;
			tls2.database = tls_files.trust;
			tls2.accept_certificate.connect((peer_cert, errors) => {
				return peer_cert != null
					&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
			});
			try {
				tls2.handshake();
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			OLLMrpc.Bin.Stream bin2;
			try {
				bin2 = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(tls2.get_input_stream()),
					new GLib.DataOutputStream(tls2.get_output_stream())
				);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			try {
				bin2.write(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			OLLMrpc.Serializable hello_parsed;
			try {
				hello_parsed = bin2.parse();
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return;
			}
			var hello = hello_parsed as OLLMrpc.Response;
			if (hello == null) {
				this.error_occurred("hello failed");
				return;
			}
			if (hello.error != null) {
				this.error_occurred(hello.error.message);
				return;
			}
			if (hello.msg != "ok") {
				this.error_occurred("hello failed");
				return;
			}
			this.registered_url = "tcp://" + host + ":" + port.to_string();
			this.close();
		}
	}

	[CCode (cname = "ollmapp_android_pair_browse_start", cheader_filename = "android-pair-browse.h")]
	private extern void android_pair_browse_start(Gtk.Window window);

	[CCode (cname = "ollmapp_android_pair_browse_poll", cheader_filename = "android-pair-browse.h")]
	private extern string android_pair_browse_poll();

	[CCode (cname = "ollmapp_android_pair_browse_stop", cheader_filename = "android-pair-browse.h")]
	private extern void android_pair_browse_stop(Gtk.Window window);
}
```

The externs sit in the namespace, same as `OllmchatWindow.vala`. An instance `extern` would pass `this` into the C call.

### 10. `ollmapp/SettingsDialog/FileConnectionAdd.vala` — desktop dialog only

**Why:** This file stays the desktop URL dialog. The phone build does not compile it (§8), so the Android URL-suffix branch is removed rather than left as an ifdef.

**Where:** the `registered_url` property, the `#if ANDROID` URL suffix, and `show_add`.

**Depends on:** §8.

#### Remove

```vala
		public string? registered_url { get; private set; }
```

#### Replace with

`ConnectionsPage` writes `registered_addresses` on both builds. The desktop dialog leaves it empty.

```vala
		public string? registered_url { get; private set; }

		/**
		 * Every ''host:port'' from the last pairing reply, one per line.
		 */
		public string registered_addresses { get; private set; default = ""; }
```

#### Remove

```vala
#if ANDROID
			var url_suffix = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) {
				halign = Gtk.Align.END
			};
			url_suffix.append(this.url_entry);
			url_suffix.append(new Gtk.Label("Host:port or HTTPS URL of the desktop") {
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				xalign = 1.0f,
				justify = Gtk.Justification.RIGHT,
				css_classes = {"dim-label"},
				max_width_chars = 45
			});
			url_row.add_suffix(url_suffix);
#else
			url_row.subtitle = "Host:port or HTTPS URL of the desktop";
			url_row.add_suffix(this.url_entry);
#endif
```

#### Replace with

```vala
			url_row.subtitle = "Host:port or HTTPS URL of the desktop";
			url_row.add_suffix(this.url_entry);
```

#### Remove

```vala
			this.registered_url = null;
			this.url_entry.text = "";
```

#### Replace with

```vala
			this.registered_url = null;
			this.registered_addresses = "";
			this.url_entry.text = "";
```

`request()` stays the URL rewrite and return.

### 11. `ollmapp/SettingsDialog/ConnectionsPage.vala` — save the address list

**Why:** A finished pair is a socket connection with every returned address, not a pending HTTPS registration.

**Where:** the `add_file_dialog.dialog_closed` handler.

**Depends on:** §4, §9, and §10.

#### Remove

```vala
			this.add_file_dialog.dialog_closed.connect(() => {
				if (this.add_file_dialog.registered_url == null) {
					this.render_file_connection();
					return;
				}
				this.dialog.app.config.filesd_client.url = this.add_file_dialog.registered_url;
				this.dialog.app.config.filesd_client.state = FilesdClient.State.REQUESTED;
				this.dialog.app.config.save();
				this.render_file_connection();
				this.toast_overlay.add_toast(new Adw.Toast(
					"Registration pending — accept the request on the desktop"
				) {
					timeout = 5
				});
			});
```

#### Replace with

The pending-registration toast goes away. The desktop already approved the certificate when it signed it.

```vala
			this.add_file_dialog.dialog_closed.connect(() => {
				if (this.add_file_dialog.registered_url == null) {
					this.render_file_connection();
					return;
				}
				this.dialog.app.config.filesd_client.url = this.add_file_dialog.registered_url;
				this.dialog.app.config.filesd_client.addresses =
					this.add_file_dialog.registered_addresses;
				this.dialog.app.config.filesd_client.state = FilesdClient.State.SOCKET;
				this.dialog.app.config.save();
				this.render_file_connection();
			});
```

### 12. `ollmapp/android/OllmchatWindow.vala` — probe stored addresses

**Why:** On later starts the phone tries each stored `host:port` for 2 seconds and keeps the one whose hello succeeds. That probe is `probe_addresses`. An empty `addresses` string does not enter the block, so startup does not connect and does not run the old HTTPS hello.

**Where:** `initialize_client`, the `if` that currently requires `config.filesd_client.url != ""`. The new method goes immediately after `initialize_client`, still inside the class.

**Depends on:** §1 and §4.

- **🔷** `probe_addresses` holds the probe. `initialize_client` only calls it.
- **🔷** The `if` tests `addresses`, not `url`. No stored address means no probe, no HTTPS hello, and `desktop_checked` stays false.
- **🔷** Each throwing call in `probe_addresses` has its own `try`. A failure warns and `continue`s. The reply check is outside the `try`.

#### Remove

```vala
			if (config.filesd_client.url != ""
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.UNREACHABLE
					|| config.filesd_client.state == FilesdClient.State.SOCKET)) {
				desktop_checked = true;
				this.startup_status_label.label = "Checking desktop environment…";
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				http.soup.timeout = 15;
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) { 
						http = http 
					}
				);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				desktop_reached = yield this.project_manager.rpc.connect(hello);
				http.soup.timeout = 0;
				if (!desktop_reached) {
					var msg = this.project_manager.rpc.connect_error;
					if (msg == "") {
						msg = "could not reach the file server";
					}
					GLib.warning("%s", msg);
				}
				this.startup_status_label.label = "Opening chat…";
			}
```

#### Replace with

Empty `addresses` makes this `if` false. Nothing in the block runs.

```vala
			if (config.filesd_client.addresses != ""
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.UNREACHABLE
					|| config.filesd_client.state == FilesdClient.State.SOCKET)) {
				desktop_checked = true;
				this.startup_status_label.label = "Checking desktop environment…";
				desktop_reached = yield this.probe_addresses(config);
				this.startup_status_label.label = "Opening chat…";
			}
```

#### Add — `probe_addresses`, immediately after `initialize_client`

The caller only reaches this when `addresses` is non-empty. A hello that succeeds stores that `tcp://host:port` and returns true. None succeeding returns false. `initialize_client` already marks the desktop unreachable in that case.

```vala
		/**
		 * Tries each stored host:port for 2 seconds.
		 *
		 * The url becomes the address whose hello succeeded.
		 *
		 * @return true when a hello succeeds
		 */
		private async bool probe_addresses(OLLMchat.Settings.Config2 config)
		{
			var tls = new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat"),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = false
			};
			tls.ensure();
			var lines = config.filesd_client.addresses.split("\n");
			for (var i = 0; i < lines.length; i++) {
				var line = lines[i].strip();
				var colon = line.last_index_of(":");
				if (colon <= 0) {
					continue;
				}
				var port = 0;
				if (!int.try_parse(line.substring(colon + 1), out port)) {
					continue;
				}
				var host = line.substring(0, colon);
				var client = new GLib.SocketClient();
				client.timeout = 2;
				GLib.SocketConnection conn;
				try {
					conn = yield client.connect_to_host_async(
						host, (uint16) port, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				GLib.TlsClientConnection link;
				try {
					link = GLib.TlsClientConnection.@new(conn, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				link.certificate = tls.certificate;
				link.database = tls.trust;
				link.accept_certificate.connect((peer_cert, errors) => {
					return peer_cert != null
						&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
				try {
					link.handshake();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				OLLMrpc.Bin.Stream bin;
				try {
					bin = new OLLMrpc.Bin.Stream(
						new GLib.DataInputStream(link.get_input_stream()),
						new GLib.DataOutputStream(link.get_output_stream())
					);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				try {
					bin.write(new OLLMrpc.Request() {
						method = "RPC-Daemon.hello",
						args = OLLMrpc.args("is", 1, "ollmchat")
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				OLLMrpc.Serializable parsed;
				try {
					parsed = bin.parse();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				var hello = parsed as OLLMrpc.Response;
				if (hello == null) {
					continue;
				}
				if (hello.error != null) {
					continue;
				}
				if (hello.msg != "ok") {
					continue;
				}
				config.filesd_client.url =
					"tcp://" + host + ":" + port.to_string();
				config.filesd_client.state = FilesdClient.State.SOCKET;
				return true;
			}
			return false;
		}
```

---

## LLM notes

- **ℹ️** Avahi stays on the Linux server as the mDNS publisher. The Android browser is `NsdManager` via JNI. Do not link `Avahi.ServiceBrowser` into the phone build.
- **🚫** Do not `#if ANDROID` inside `FileConnectionAdd`. The phone build compiles `ollmapp/android/FileConnectionAdd.vala`. It does not compile `ollmapp/SettingsDialog/FileConnectionAdd.vala`.
- **🚫** Do not run the HTTPS `HttpClient` hello when `addresses` is empty. No stored address means startup does not contact a desktop.
- **ℹ️** Do not add an HTTPS registration or steady-state fallback. [`RPC-8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) still describes HTTPS outside the LAN. The parent wins for pairing and for notifications.
- **ℹ️** `test-rpc-filesd-http-client` still posts the old one-string HTTPS registration. This plan does not keep that path.
- **ℹ️** `Client.connect` on Android still bails with “unix IO watch is not available” after a TCP connect. The probe hello above is one-shot. A live notification socket needs a read path that is not `IOChannel.unix_new`, and that is not in these fences.
