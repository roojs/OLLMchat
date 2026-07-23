# Windows CI: ollmapp missing webview2gtk + ollmfilesd Unix stdio

**Status:** OPEN (fix in progress)

## Problem

[Windows build run 29933922706](https://github.com/roojs/OLLMchat/actions/runs/29933922706) failed after `ocwebkit.vapi` `--define=WINDOWS` landed:

1. **`ollmchat.exe`:** `Package 'webview2gtk-1' not found` — `octools` / `ocwebkit` `.deps` pull webview2gtk; `ollmapp` never passed `--vapidir` / `--pkg` for the staged prefix.
2. **`ollmfilesd.exe`:** `UnixInputStream` / `UnixOutputStream` do not exist on Windows; `StdioConnection` still used Unix APIs. Meson already skipped `gio-unix-2.0` on Windows but the Vala source was unconditional.

## Fix

1. On Windows, add `webview2gtk-1` dep + vapidir to `ollmapp` (app + CLI).
2. **`StdioConnection`:** use **`GLib.IOChannel`** for stdin/stdout NDJSON
   (`unix_new` / `win32_new_fd`) — no `UnixInputStream` / `Win32InputStream`,
   no `GetStdHandle` / `_get_osfhandle` extern. Drop `gio-unix` / `gio-windows`
   from `ollmfilesd` meson.

## Attempts

- GIO Win32 streams + `_get_osfhandle` / `GetStdHandle` — works but wrong layer;
  GLib has no portable stdin `GInputStream`, and this harness is text NDJSON.
- **IOChannel** is the GLib API already used for the watch; extend it to read/write.

## Conclusions

Root cause for webview2 was incomplete consumer vapidir wiring. Stdio failure was
using Unix-only GIO streams; fix is IOChannel, not Win32 HANDLE FFI.
