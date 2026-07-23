# Windows CI: ollmapp missing webview2gtk + ollmfilesd Unix stdio

**Status:** OPEN (fix in progress)

## Problem

[Windows build run 29933922706](https://github.com/roojs/OLLMchat/actions/runs/29933922706) failed after `ocwebkit.vapi` `--define=WINDOWS` landed:

1. **`ollmchat.exe`:** `Package 'webview2gtk-1' not found` — `octools` / `ocwebkit` `.deps` pull webview2gtk; `ollmapp` never passed `--vapidir` / `--pkg` for the staged prefix.
2. **`ollmfilesd.exe`:** `UnixInputStream` / `UnixOutputStream` do not exist on Windows; `StdioConnection` still used Unix APIs. Meson already skipped `gio-unix-2.0` on Windows but the Vala source was unconditional.

## Fix

1. On Windows, add `webview2gtk-1` dep + vapidir to `ollmapp` (app + CLI).
2. `#if G_OS_WIN32` in `StdioConnection`: `IOChannel.win32_new_fd` for the watch channel;
   `Win32InputStream` / `Win32OutputStream` via **`GetStdHandle`** (not `_get_osfhandle`);
   meson `--pkg=gio-windows-2.0`.

## Attempts

- `0bd39f69` — Win32 streams via `_get_osfhandle` as `void*`; CI: `intptr_t` → `void*` without cast.
- `7520a70a` — `int64` + `(void*)` cast — compiles but is CRT kludge.
- Next: replace with `GetStdHandle(STD_INPUT/OUTPUT_HANDLE)` — proper Win32 HANDLE API.

## Conclusions

Root cause is incomplete Windows consumer wiring (same class as ocwebkit vapi defines), not the earlier CRLF issue.
