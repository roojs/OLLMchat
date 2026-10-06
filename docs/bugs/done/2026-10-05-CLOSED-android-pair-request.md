# Add Remote Desktop — Request toasts a missing client.csr

**Status:** 🚫 CLOSED — a phone tap completed registration, stored the signed certificate and CA, and reached hello. The remaining failure is the separate Android live RPC read watch.

**Device:** SM-S9380, `adb-R5CY134DA0W`.  
**Related:** ℹ️ `ollmapp/android/FileConnectionAdd.vala`, `libocrpc/android/Cert.vala`, `libocrpc/Transport/Cert.vala`

---

## Problem

- **🔷** After the desktop is found and the six digits are entered, Request does nothing useful. A toast keeps appearing: failed to open a file under `/storage/emulated/...`.
- **🔷** When the PIN row appears, focus should move to it so the keyboard opens, and the keyboard should be the number pad.

---

## Evidence

- **✔️** `GLib.FileUtils.get_contents` reports `Failed to open file “…”: No such file or directory`. `FileConnectionAdd.request` reads `{user_data_dir}/ollmchat/client.csr` and emits `error_occurred`. `ConnectionsPage` shows that message as an `Adw.Toast`.
- **✔️** On this phone `XDG_DATA_HOME` is `/storage/emulated/0/Android/data/org.roojs.ollmchat.androidpoc/files/share`. That is the path in the toast.
- **✔️** Desktop `OLLMrpc.Transport.Cert.ensure` writes `client.csr` next to `client.pem`. Android `libocrpc/android/Cert.vala` stops after the PEM pair. `ocrpc_cert_create_pem_files` never writes a CSR.
- **✔️** GTK Android maps `Gtk.InputPurpose.DIGITS` to `TYPE_CLASS_NUMBER` (`gtkimcontextandroid.c`). `PIN` is the same pad but masked.

---

## Root cause

- **✔️** Request fails before the socket connect because the CSR file the registration call reads is never created on Android. Each tap emits the same toast.

---

## Proposed fix

- **🔷** Android `Cert.ensure` writes `client.csr` from the client key with OpenSSL, same file the desktop GnuTLS path writes.
- **🔷** The PIN entry uses `Gtk.InputPurpose.DIGITS` and grabs focus when a `host:port` hit arrives.

### 1. `libocrpc/android/Cert.vala` — write the CSR after the PEM pair

**Why:** Request reads `client.csr`.  
**Where:** `ensure`, after `create_pem_files`.  
**Depends on:** `ocrpc_cert_write_csr` in `cert-openssl.c`.

#### Add

```vala
			var csr_path = cert_path.substring(0, cert_path.last_index_of(".")) + ".csr";
			if (!GLib.FileUtils.test(csr_path, GLib.FileTest.EXISTS)) {
				try {
					ocrpc_cert_write_csr(key_path, csr_path, this.cn);
				} catch (GLib.Error e) {
					GLib.error("write %s: %s", csr_path, e.message);
				}
			}
```

### 2. `ollmapp/android/FileConnectionAdd.vala` — number pad and focus

**Why:** The IME reads input purpose. Focus is what shows the keyboard.  
**Where:** PIN entry construction, and the browse hit that shows the row.

#### Replace with

```vala
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "Six digits",
				max_length = 6,
				input_purpose = Gtk.InputPurpose.DIGITS
			};
```

```vala
					this.pin_row.visible = true;
					this.pin_entry.grab_focus();
```

---

## Registration (2026-10-05, later)

- **🔷** Request still does not complete device registration. The number keyboard is not part of this pass.
- **✔️** On SM-S9380 after the CSR build: `client.csr` exists (14:23), `client.pem` and `client-key.pem` are still the 14:14 self-signed pair, and `ollmrpc-ca.pem` is absent. Registration never wrote the signed cert.
- **✔️** `tests/rpc/filesd-pair-test.vala` calls `Request`, `Response`, `Error`, `Notification`, and `Daemon` `rpc_register()` before ensure/connect. `FileConnectionAdd.request` did not. `AndroidApplication` registers `OLLMfiles` and `ClientCert` only. `OLLMrpc.Client`'s static constructor registers the bin types, and that constructor runs only after a desktop is already connected.
- **✔️** `Bin.Stream.write` throws `Unregistered class type schema` for an unregistered `Request`. That toast is not written to logcat.

### `ollmapp/android/AndroidApplication.vala` — register wire types once

**Why:** `OLLMrpc.rpc_register` registers `Request`, `Response`, `Error`, and `Notification` for the process. `OLLMfiles.rpc_register` already registers `Daemon`.  
**Where:** Application constructor, with the other `rpc_register` calls.

#### Add

```vala
			OLLMrpc.rpc_register();
```
