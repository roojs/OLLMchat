# Settings dialog SIGSEGV on the SSL host dropdown

**Status:** ✔️ root cause confirmed from the backtrace and generated C; fix applied — await a settings-dialog open on device

## Problem

- **🔷** Opening Settings reaches `ConnectionsPage.load_config` and crashes.
- **🔷** Expected: the Desktop server rows fill, including the SSL host dropdown with `All` first.

### Evidence

- **ℹ️** gdb: `SIGSEGV` in `__strlen_avx2` ← `g_strdup` ← `gtk_string_object_new` ← `gtk_string_list_splice` ← `g_object_new` ← `FileServerRow.load_config` line 452 (`new Gtk.StringList(ssl_ips)`). Caller is `ConnectionsPage.load_config` line 597 from `MainDialog.show_dialog`.
- **ℹ️** GTK 4.18 `gtk_string_list_splice` calls `g_strv_length` on that array. It walks pointers until a `NULL` sentinel. A missing sentinel makes `g_strdup` run on the next heap word.
- **✔️** `build/ollmapp/ollmchat.p/SettingsDialog/FileServerRow.c` for the old prepend:
  - slice `_vala_array_dup1` allocates `n + 1` and writes the sentinel
  - `resize` does `g_renew(..., n + 1)` (no extra sentinel slot) and sets length to `n + 1`, so the old sentinel becomes a counted element
  - `_vala_array_move(..., 0, 1, n)` copies onto that slot and leaves `["All", …]` with length equal to the allocation and no trailing `NULL`
- **ℹ️** The HTTPS dropdown passes `ips` from `TcpListen.ifaces()` straight through. That array is still sentinel-terminated, which is why the crash is line 452 and not line 432.

### Root cause

- **✔️** Prepending `"All"` with `resize` + `move` drops the `NULL` that `Gtk.StringList` requires. The bad value is the array shape, not a null IP from `ifaces()`.

## Proposed fix

- **🔷** Keep the `resize` / `move` prepend. Follow it with a slice of the same length. That slice copies by length into a new array whose last slot is the sentinel `Gtk.StringList` walks to.
- **🚫** A `foreach` that appends each address. Same result, and it is the loop this prepend was written to avoid.

#### Remove

```vala
			var ips = OLLMrpc.Transport.TcpListen.ifaces();
			string[] ssl_ips = {};
			ssl_ips += "All";
			foreach (var ip in ips) {
				ssl_ips += ip;
			}
```

#### Replace with

```vala
			var ips = OLLMrpc.Transport.TcpListen.ifaces();
			var n = ips.length;
			var ssl_ips = ips[0:n];
			ssl_ips.resize(n + 1);
			ssl_ips.move(0, 1, n);
			ssl_ips[0] = "All";
			// resize+move drops the strv terminator; the slice puts it back.
			ssl_ips = ssl_ips[0:n + 1];
```

- **🚫** A null check around `Gtk.StringList`. That hides a non-terminated array and still drops `"All"` or the last address.

## Attempts / changelog

- **✔️** First pass replaced the prepend with `+=` inside `foreach`. That writes a sentinel, and it puts a per-address loop back in `load_config`.
- **✔️** `ollmapp/SettingsDialog/FileServerRow.vala` `load_config`: `resize` / `move` again, then `ssl_ips = ssl_ips[0:n + 1]`. Generated C copies with `g_new0(length + 1)` before freeing the shifted array.

## Next

- **⏳** **🔷** Open Settings and confirm the dialog stays up and the SSL host dropdown lists `All` plus the machine's non-loopback IPv4 addresses.
