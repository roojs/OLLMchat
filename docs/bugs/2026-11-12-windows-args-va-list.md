# Windows args() repeats the first value

**Status:** ⏳ fix applied in `libocrpc/namespace.vala`. Awaiting a Windows registration check.

**Pointer:** `docs/bug-fix-process.md`

**Seen:** Argus agent registration on Windows, 2026-11-12. `OLLMrpc.args("ssssbss", ...)` from `shared/Register.vala`.

---

## Problem

- 🔷 `args` with more than one value sends the first value in every slot on Windows.
- 🔷 Linux packs each argument once.

## Evidence

- ✔️ A Windows program that called `OLLMrpc.args("ssssbss", pin, csr, requester, family, is_controller, username, hostname)` wrote a 120-byte frame. Every string was the PIN.
- ✔️ The same call on Linux wrote 450 bytes and included the certificate request (`40 81 4e`, string length 334).
- ✔️ Building the `Gee.ArrayList` of `GLib.Value` one argument at a time produced the 450-byte frame on Windows, and the server accepted that registration.
- ✔️ `libocrpc/namespace.vala` `to_value` takes `va_list` by value and calls `l.arg`. `args` and `val` call it once per signature letter.
- ✔️ On Windows x64, `va_list` is a pointer passed by value. `arg()` advances the copy. The caller's list stays on the first argument.
- ✔️ On System V AMD64 the callee updates the caller's list, so the Linux call already walks the arguments.
- ℹ️ `libocrpc/android/namespace.vala` already takes `va_list*` for the same reason on aarch64. Meson compiles that file instead of `namespace.vala`. Desktop Windows still compiles `namespace.vala`.
- ℹ️ `libocrpc/meson.build` defines `G_OS_WIN32` when `is_windows`.

## Root cause

- ✔️ `to_value(string tag, va_list l)` takes the cursor by value. On Windows that does not move the caller's `va_list`, so every letter reads the first argument.

## Proposed fix

- 🔷 Under `#if G_OS_WIN32`, `to_value` takes `ref va_list`. `args` and `val` pass `ref l`.
- 🔷 The Linux signature stays `va_list`. The function body stays `l.arg`.
- 🚫 A second packer at the call site. `args` is the packer.
- 🚫 A Windows copy of `namespace.vala`. Android already has one. This stays in `namespace.vala`.

### `libocrpc/namespace.vala` — `to_value`

**Why:** a by-value `va_list` on Windows leaves every `arg()` on the first argument.

**Where:** the `to_value` signature.

#### Remove

```vala
	private GLib.Value to_value(string tag, va_list l)
```

#### Replace with

```vala
#if G_OS_WIN32
	private GLib.Value to_value(string tag, ref va_list l)
#else
	private GLib.Value to_value(string tag, va_list l)
#endif
```

### `libocrpc/namespace.vala` — `args`

**Why:** `args` calls `to_value` once per letter and has to pass the same cursor.

**Where:** `packed.add(to_value(tag, l))`.

#### Remove

```vala
			packed.add(to_value(tag, l));
```

#### Replace with

```vala
#if G_OS_WIN32
			packed.add(to_value(tag, ref l));
#else
			packed.add(to_value(tag, l));
#endif
```

### `libocrpc/namespace.vala` — `val`

**Why:** `val` is the other caller.

**Where:** `var v = to_value(tag, l)`.

#### Remove

```vala
		var v = to_value(tag, l);
```

#### Replace with

```vala
#if G_OS_WIN32
		var v = to_value(tag, ref l);
#else
		var v = to_value(tag, l);
#endif
```

## Attempts / changelog

- ✔️ `libocrpc/namespace.vala`: under `#if G_OS_WIN32`, `to_value` takes `ref va_list`. `args` and `val` pass `ref l`. Linux stays by value. Body stays `l.arg`.
- ✔️ Valac 0.56.18 accepts `ref va_list` and emits `va_arg(*l, …)` with the caller passing `&l`. That advances one cursor across letters. Linux `namespace.vala` still type-checks aside from sibling types omitted from a single-file compile.

## Next

- ⏳ On Windows, register again with `OLLMrpc.args("ssssbss", …)` and confirm the frame is the long one (CSR present, not the PIN repeated).
