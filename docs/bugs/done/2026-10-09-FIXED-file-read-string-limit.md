# File.read drops files longer than 32767 bytes

**Status:** ✔️ long string properties round-trip through the boxed blob; phone `File.read` was not re-run

**Related:** ℹ️ `docs/bugs/2026-10-08-android-remote-connection-lifecycle.md`, ℹ️ `docs/bin-rpc-protocol.md` §13, ℹ️ `docs/plans/done/RPC-8.4.5-DONE-rpc-ffi-leftovers.md`

## Problem

- **🔷** Opening a file whose body is longer than 32767 bytes must return the contents.
- **🔷** `File.read` id 9 on the phone failed instead. The daemon logged `connection write error: string value longer than 32767`, closed TLS, and the phone request aborted.
- **🔷** The same write path serves desktop RPC. This is not an Android lifecycle failure.

## Evidence

- **✔️** Physical browsing in the lifecycle session reached `File.read` id 9 and died on that write error.
- **ℹ️** `ollmfilesd/File.vala` `read` puts the file body in `Response.msg` (plain text, or base64 when the file is not text).
- **ℹ️** `Response.bin_write_prop` sends `msg` through `bin_default_write_prop`, which calls `StreamValue.write`.
- **ℹ️** `StreamValue.write` throws `string value longer than 32767` for every `GLib.Type.STRING` past that length.
- **ℹ️** `docs/bin-rpc-protocol.md` §13: a scalar string property longer than 32767 bytes is type byte `0x48` (`GLib.Type.BOXED`), then a big-endian `uint32` length, then the UTF-8 bytes. Read decodes that blob back into the string property.
- **ℹ️** RPC-8.4.5 removed that boxed write from `StreamValue.write` on purpose. Positional `values[]` keeps the compact string cap. Boxed values on that path are `GLib.Bytes` only. The plan left long string properties to `bin_read_prop`, which knows the property type.

## Root cause

- **✔️** `bin_default_write_prop` never took over the long-string case. It still calls `StreamValue.write`, so a long `Response.msg` is rejected before any boxed bytes are written.
- **✔️** `bin_default_read_prop` assigns the decoded value straight onto the property. A boxed blob comes back as `GLib.Bytes`, which cannot be stored in a `string` property until it is turned back into text.

## Proposed changes

- **💩** Write and read the long form only for string properties. Leave `StreamValue.write`'s 32767 throw in place.

### `libocrpc/Bin/Serializable.vala` — `bin_default_write_prop`

**Why:** Compact strings stay in `StreamValue`. A string property past 32767 bytes uses the §13 blob the protocol already defines.

**Where:** `bin_default_write_prop`, after the null-object return, in place of the unconditional `StreamValue.write` call.

#### Remove

```vala
			ctx.write_tag(tag);
			StreamValue.write(ctx, val);
```

#### Replace with

```vala
			if (val.type() == GLib.Type.STRING) {
				var s = val.get_string();
				s = s != null ? s : "";
				if (s.length > 32767) {
					/* Compact STRING stays in StreamValue. Long properties
					 * use the §13 blob. */
					ctx.write_tag(tag);
					ctx.out_stream.put_byte((uint8) GLib.Type.BOXED);
					ctx.out_stream.put_uint32((uint32) s.length);
					ctx.out_stream.write_all(((uint8[]) s)[0:s.length], null);
					return;
				}
			}
			ctx.write_tag(tag);
			StreamValue.write(ctx, val);
```

### `libocrpc/Bin/Serializable.vala` — `bin_default_read_prop`

**Why:** `StreamValue.read` of a boxed blob returns `GLib.Bytes`. A string property needs those bytes as text.

**Where:** `bin_default_read_prop`, immediately after `StreamValue.read`.

#### Remove

```vala
			var val = StreamValue.read(ctx, type_byte);
			if (prop.value_type.is_a(GLib.Type.ENUM) && val.type() == GLib.Type.INT) {
```

#### Replace with

```vala
			var val = StreamValue.read(ctx, type_byte);
			if (prop.value_type == GLib.Type.STRING && val.type() == typeof(GLib.Bytes)) {
				var bytes = (GLib.Bytes) val.get_boxed();
				var text = GLib.Value(typeof(string));
				if (bytes.get_size() == 0) {
					text.set_string("");
					this.set_property(prop.name, text);
					return;
				}
				/* (string) get_data() ignores the blob length. Same trailing
				 * NUL copy StreamValue uses for compact strings. */
				var n = (int) bytes.get_size();
				var raw = new uint8[n + 1];
				GLib.Memory.copy(raw, (!) bytes.get_data(), bytes.get_size());
				raw[n] = 0;
				text.set_string((string) raw);
				this.set_property(prop.name, text);
				return;
			}
			if (prop.value_type.is_a(GLib.Type.ENUM) && val.type() == GLib.Type.INT) {
```

- **🚫** Do not raise or remove the 32767 cap inside `StreamValue.write`. That cap is the `values[]` rule from RPC-8.4.5.
- **🚫** Do not change `File.read` to a second RPC or a side channel. `Response.msg` is already the file body.

## Attempts / changelog

- **✔️** Split out of the Android remote lifecycle log after the phone `File.read` failure.
- **✔️** `bin_default_write_prop` writes a string property longer than 32767 bytes as §13 `BOXED`. `bin_default_read_prop` copies that blob back into the string, including a trailing NUL, because `(string) Bytes.get_data()` drops the length.
- **✔️** `build/tests/test-rpc-bin` passed the existing 130-byte compact string check and the 40000-byte `TestPair.name` round-trip.
- **ℹ️** The same binary then stops on `second Request.method still carries full UTF-8`. That assertion also fails with this property change reverted, so it is not this fix.

## Next

- **✔️** Property write and read are in `libocrpc/Bin/Serializable.vala`.
- **✔️** The existing `tests/rpc/bin-test.vala` cases cover a string under 32767 bytes and one of 40000 bytes.
