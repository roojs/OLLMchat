# Binary RPC wire format

**Version 3.0**

This document defines the on-the-wire byte layout for `OLLMrpc.Bin` object bodies. A message is one root object: a type header, a sequence of properties, and an end marker. Multi-byte integers are **big-endian** unless noted otherwise.

The **type byte** on the wire is always a `GLib.Type` fundamental value (optionally OR'd with the array flag). There is no separate compact wire-type enum.

---

## 1. Overview

A **connection** maintains a per-instance **wire-name** table on its `OLLMrpc.Bin.Stream`. **Type aliases → GType** live in a **process-wide** static map (`OLLMrpc.Bin.register`).

1. **Wire names (per connection)** — string → uint16 token map for **both** property keys (`"name"`, `"count"`, …) and object type aliases (`"TestPair"`, `"File"`, …). Tokens are learned on the wire via `TOKEN_REG_KEY` when a name is first sent.
2. **Type aliases → GType (process-wide)** — `OLLMrpc.Bin.register(alias, gtype)` (namespace function in `libocrpc/Bin/Stream.vala`), called from each type's `rpc_register()` before any channel opens. Both ends register every wire alias string they send or receive; each maps that alias to its **own** local `GLib.Type`. `register()` call order is not significant.

Every **property value**: name token → one-byte **type** (`GLib.Type` fundamental) → payload. When the type is `GLib.Type.OBJECT`, a **name token** (uint16) identifying the object alias follows before the nested property stream. Unknown token or unrecognized alias → protocol error.

### Type registration

```vala
// In each wire type's rpc_register() — before connect() / listen
OLLMrpc.Bin.register ("File", typeof (OLLMfiles.V2.File));
OLLMrpc.Bin.register ("Folder", typeof (OLLMfiles.V2.Folder));
```

Client and server each register the **same wire alias strings**; each maps an alias to whatever local `GLib.Type` implements that payload on that end. Property keys do not need `register()` — they appear on the wire and enter the per-connection name-token table via `TOKEN_REG_KEY`.

Domain types implement `OLLMrpc.Bin.Serializable` for bin encoding. **`rpc_register()`** calls **`Bin.register`** — **not** at channel setup.

### General usage

**Production** (`OLLMrpc.Transport.Connection`, `OLLMrpc.Client`):

1. Call each wire type's **`rpc_register()`** (which calls **`Bin.register`**) before **`connect()`** / listen.
2. Open the channel — create **one** **`Bin.Stream(in_stream, out_stream)`** for the connection lifetime.
3. **Send:** **`bin.write(serializable)`** — writes root type header + property stream.
4. **Receive:** **`bin.parse()`** — root type from wire; cast to **`Request`**, **`Response`**, etc.
5. Wire-name tokens (**`names[]`**) accumulate across messages on the same connection.

**Tests / memory round-trip** (`tests/rpc/bin-test.vala`):

```vala
OLLMrpc.Bin.register ("TestPair", typeof (TestPair));

var mem = new GLib.MemoryOutputStream.resizable ();
var out_stream = new GLib.DataOutputStream (mem);
var write_bin = new OLLMrpc.Bin.Stream (null, out_stream);
write_bin.write (original);
out_stream.close ();

var in_stream = new GLib.DataInputStream (
    new GLib.MemoryInputStream.from_bytes (mem.steal_as_bytes ())
);
var read_bin = new OLLMrpc.Bin.Stream (in_stream, null);
var parsed = read_bin.parse () as TestPair;
```

Pass **`null`** for the unused stream direction in memory-only tests.

---

## 2. Walkthrough: `TestPair`

Vala type (registered as `"TestPair"`):

```vala
public class TestPair : GLib.Object, OLLMrpc.Bin.Serializable {
    public string name { get; set; default = ""; }
    public int count { get; set; default = 0; }
}
```

Object on the wire:

```vala
new TestPair () { name = "alpha", count = 42 }
```

**First** message (type `"TestPair"` and keys `"name"`, `"count"` not yet seen on this connection):

```text
;; --- introduce type "TestPair" (first send of this type) ---
FF FE                    ;; TOKEN_REG_TYPE (0xFF then 0xFE)
00                       ;; reg_id 0
08                       ;; alias length
54 65 73 74 50 61 69 72  ;; "TestPair"

;; --- root object header ---
50                       ;; G_TYPE_OBJECT (80)
00                       ;; reg_id 0 → "TestPair"

;; --- property "name" = "alpha" (first sight of "name") ---
FF FF                    ;; TOKEN_REG_KEY
00 01                    ;; assigned token 1
04                       ;; name length
6E 61 6D 65              ;; "name"
00 01                    ;; name token 1 (reference)
40                       ;; type byte: G_TYPE_STRING (64)
00 05                    ;; UTF-8 length 5
61 6C 70 68 61           ;; "alpha"

;; --- property "count" = 42 ---
FF FF                    ;; TOKEN_REG_KEY
00 02                    ;; assigned token 2
05                       ;; name length
63 6F 75 6E 74           ;; "count"
00 02                    ;; name token 2 (reference)
18                       ;; type byte: G_TYPE_INT (24)
01                       ;; width: 1 byte payload
2A                       ;; value 42

;; --- end of object ---
FF FD                    ;; TOKEN_END
```

**Second** message on the same connection (names already cached):

```text
50                       ;; G_TYPE_OBJECT (80)
00                       ;; reg_id 0 → "TestPair"
00 01                    ;; name token 1 → "name"
40                       ;; G_TYPE_STRING (64)
00 05
61 6C 70 68 61           ;; "alpha"
00 02                    ;; name token 2 → "count"
18                       ;; G_TYPE_INT (24)
01 2A                    ;; width 1, value 42
FF FD                    ;; TOKEN_END
```

No `TOKEN_REG_KEY` blocks appear again until a new wire name is seen.

---

## 3. Root object layout

```text
50                              ;; GLib.Type.OBJECT (80), array flag clear
reg_id                          ;; 1 byte (0–127) or 2-byte escape (§6)
properties…                     ;; zero or more property encodings
FF FD                           ;; TOKEN_END (uint16)
```

A root message is **never** an object array (`0xD0` = `GLib.Type.OBJECT | 0x80`).

---

## 4. Property layout

Each property:

```text
name_token   uint16     ;; cached id, or TOKEN_REG_KEY introduction (§5)
type_byte    uint8      ;; GLib.Type fundamental + optional array flag (§7)
reg_id       0–2 bytes  ;; only when base type is GLib.Type.OBJECT (0x50)
payload      …          ;; depends on type (§8–§14)
```

The object ends with `FF FD` (`TOKEN_END`).

---

## 5. Wire names and tokens

Property keys and object type aliases share one **name index** table (`names[]` on the stream). Property keys use `TOKEN_REG_KEY` (uint16). Type aliases use `TOKEN_REG_TYPE` (`0xFF 0xFE` bytes) via `read_reg_gtype()`.

| Value | Meaning |
| ----- | ------- |
| `0xFFFF` | `TOKEN_REG_KEY` — introduce a new property key name |
| `0xFFFE` | `TOKEN_REG_TYPE` — introduce a type alias (`0xFF` byte then `0xFE`) |
| `0xFFFD` | `TOKEN_END` — end of property stream |

### Property key introduction

```text
FF FF           TOKEN_REG_KEY
00 02           assigned token 2
05              name length
6C 61 62 65 6C  "label"
00 02           reference token 2
…               type_byte + payload follow
```

**Cached reference**:

```text
00 02           name token 2 only
…               type_byte + payload
```

### Type alias introduction (`TOKEN_REG_TYPE`)

First time a type is sent on a connection:

```text
FF FE           TOKEN_REG_TYPE
00              reg_id 0 (1 or 2 byte encoding — §6)
08              alias length
54 65 73 …      "TestPair"
50              G_TYPE_OBJECT follows on write
00              reg_id 0 again
```

On read, `parse()` and `bin_read` use a single `if (b == 0xFF) read_reg_gtype()` before the type byte.

Wire names are limited to 255 bytes on introduction.

---

## 6. Object type registration

### `Bin.register(alias, gtype)` (process-wide)

Maps a wire alias string to a local `GLib.Type` for decode — **process-wide**, not per connection. Both peers must register every alias they send or receive; the **alias string** is the wire contract — each end may map it to a different GObject type. Per-connection wire indices for type aliases are learned via `TOKEN_REG_TYPE` / `read_reg_gtype()`; property keys via `TOKEN_REG_KEY`.

- Duplicate alias → error.
- `register()` call order is not significant.

Example (from `tests/rpc/bin-test.vala`):

```vala
OLLMrpc.Bin.register ("TestPair", typeof (TestPair));
OLLMrpc.Bin.register ("TestParent", typeof (TestParent));

var write_bin = new OLLMrpc.Bin.Stream (null, out_stream);
var read_bin = new OLLMrpc.Bin.Stream (in_stream, null);
// No per-connection type registration — aliases already in the static map
```

### `reg_id` encoding

| id range | Bytes |
| -------- | ----- |
| 0–127 | one byte, bit 7 clear — e.g. `00`, `7F` |
| ≥ 128 (rare) | two bytes: `(0x80 \| (id >> 8))`, then `(id & 0xFF)` |

### Object header on the wire

```text
50                       ;; G_TYPE_OBJECT
00                       ;; reg_id → names[0] → alias → GType
… properties …
FF FD
```

- `write_gtype()` emits optional `TOKEN_REG_TYPE`, then `50` + `reg_id`.
- `parse()` optionally calls `read_reg_gtype()` once, then reads `50` + `reg_id`.
- `parse_object()` reads `reg_id` after `0x50` was already consumed (or accepts a known element `GType` when decoding homogeneous object arrays — see §15).
- `parse_object_array()` reads element `reg_id`, count, then one property stream per element via `parse_object(element_gtype)`.

---

## 7. Type byte (uint8)

Always **exactly one byte** per property value. The low seven bits (when bit 7 is clear) are the **`GLib.Type` fundamental** value. Bit 7 (`0x80`) is the **array flag** only.

| `type_byte` | `GLib.Type` | Meaning |
| ----------- | ----------- | ------- |
| `0x00` | `INVALID` | heterogeneous array only (`0x80`) |
| `0x0C` | `CHAR` (12) | `char` / `int8` |
| `0x10` | `UCHAR` (16) | `uchar` |
| `0x14` | `BOOLEAN` (20) | `bool` |
| `0x18` | `INT` (24) | `int` |
| `0x1C` | `UINT` (28) | `uint` |
| `0x28` | `INT64` (40) | `int64` |
| `0x2C` | `UINT64` (44) | `uint64` |
| `0x30` | `ENUM` (48) | any `enum` |
| `0x34` | `FLAGS` (52) | any `flags` |
| `0x48` | `BOXED` (72) | large binary blob |
| `0x50` | `GObject` (80) | registered object — `reg_id` follows |

Array examples (set bit 7):

| `type_byte` | Meaning |
| ----------- | ------- |
| `0x8C` | `char[]` (`CHAR` \| `0x80`) |
| `0x98` | `int[]` (`INT` \| `0x80`) |
| `0xC0` | `string[]` (`STRING` \| `0x80`) |
| `0xD0` | `object[]` (`GObject` \| `0x80`) |
| `0x80` | `ANY[]` (`INVALID` \| `0x80`) — each element has its own type byte |

There is no two-byte type encoding.

Numeric values follow the platform's GObject fundamentals (shown here for a typical GLib 2.x build). The implementation writes `(uint8) GLib.Type.*` directly.

---

## 8. `bool`

Vala: `enabled = true`

```text
14        ;; G_TYPE_BOOLEAN (20)
01        ;; true (false = 00)
```

With name token prefix, a cached property looks like:

```text
00 03     ;; name token for "enabled"
14 01     ;; G_TYPE_BOOLEAN, true
```

---

## 9. `string`

Vala: `name = "hi"`

```text
40           ;; G_TYPE_STRING (64)
02           ;; length 2 (one byte — under 128)
68 69        ;; "hi"
```

**Length prefix** (UTF-8 byte count) — two forms only:

| length | Bytes |
| ------ | ----- |
| under 128 | one byte, bit 7 clear — e.g. `02`, `7F` |
| 128 or more | two bytes: `(0x80 \| (len >> 8))`, then `(len & 0xFF)` |

Example — 128-byte payload:

```text
40           ;; G_TYPE_STRING
80 80        ;; length 128 (two-byte form)
… 128 UTF-8 bytes …
```

Applies to scalar `string` props (type byte `0x40`) and each element of `string[]`.

**Large `string` props** (length greater than 32767, or whenever inline length does not fit): type byte `0x48` (`GLib.Type.BOXED`) then `uint32` BE length + UTF-8 bytes (§13) — not a third length-prefix form.

---

## 10. Narrow integer (`char`, `int8`, `uchar`)

Vala: `code = (int8) -3`

```text
0C     ;; G_TYPE_CHAR (12) — use 10 for G_TYPE_UCHAR (16)
FD     ;; raw byte (two's complement for signed types)
```

No width prefix — one payload byte only.

---

## 11. Signed wide integer

Used for `int`, `int64`, and `enum`. The type byte reflects the property's fundamental:

| Vala type | Type byte |
| --------- | --------- |
| `int` | `0x18` (`G_TYPE_INT`) |
| `int64` | `0x28` (`G_TYPE_INT64`) |
| `enum` | `0x30` (`G_TYPE_ENUM`) |

**Short** (fits in −128…127) — Vala: `count = 42`

```text
18     ;; G_TYPE_INT (24)
01     ;; width 1
2A     ;; 42
```

**Long** — Vala: `count = 1000`

```text
18     ;; G_TYPE_INT (24)
08     ;; width 8
00 00 00 00 00 00 03 E8   ;; int64 1000, big-endian
```

Only width bytes `01` and `08` are valid.

---

## 12. Unsigned wide integer

Used for `uint`, `uint64`, and `flags`. The type byte reflects the property's fundamental:

| Vala type | Type byte |
| --------- | --------- |
| `uint` | `0x1C` (`G_TYPE_UINT`) |
| `uint64` | `0x2C` (`G_TYPE_UINT64`) |
| `flags` | `0x34` (`G_TYPE_FLAGS`) |

**Short** (0…255) — Vala: `flags = 7`

```text
34     ;; G_TYPE_FLAGS (52)
01     ;; width 1
07
```

**Long** — Vala: `id = 1000`

```text
1C     ;; G_TYPE_UINT (28)
08     ;; width 8
00 00 00 00 00 00 03 E8
```

---

## 13. Blob

Large binary (`GLib.Type.BOXED`):

```text
48                       ;; G_TYPE_BOXED (72)
00 00 04 D2              ;; uint32 length 1234
… 1234 raw bytes …
```

**Default codec:** scalar `string` props longer than 32767 bytes are written as `BOXED` automatically by `bin_default_write_prop` (§9). On read, `BOXED` decodes back into a `string` property.

**Custom overrides:** opaque buffers (`uint8[]`, …) and other non-string blobs use the same wire layout in a `bin_write_prop` / `bin_read_prop` override on the owning type.

---

## 14. Nested object

Default `bin_write_prop` / `bin_read_prop` encode nested `Bin.Serializable` objects. Null object properties are omitted on write. The nested value's type must be registered via `Bin.register()`.

Single object — registered as `"Child"`, name token `1`:

```text
50           ;; G_TYPE_OBJECT (80)
00 01        ;; name token 1 → "Child"
…            ;; Child property stream
FF FD        ;; TOKEN_END
```

Full property (name token `4` for `"child"`):

```text
00 04        ;; name token
50 00 01     ;; G_TYPE_OBJECT + name token 1
… child props …
FF FD
```

`write_gtype()` emits `0x50` + uint16 name token, then `bin_write()` emits the property stream.

---

## 15. Arrays

Set bit 7 on the type byte, then a **count**, then elements.

**Vala:** native arrays (`string[]` is encoded by default on {@link Serializable}; `int[]`, …), `Gee.ArrayList<T>`, and `uint8[]` need `bin_write_prop` / `bin_read_prop` overrides on the owning type. Scalar element arrays use the layouts below; opaque byte buffers typically use §13 blob (`GLib.Type.BOXED` on the wire).

### Short list

Element **count** uses the same compact prefix as §9 string lengths (under 128: one byte; 128 or more: two bytes). Then each element.

**`string[]`** — `["a", "bb"]` (name token `5`):

```text
00 05        ;; name token
C0           ;; G_TYPE_STRING (64) | array (0x80)
02           ;; count 2
01 61        ;; length 1, "a"
02 62 62     ;; length 2, "bb"
```

Each element uses the §9 length prefix (not a per-element type byte).

**`int[]`** — `[1, 2]`:

```text
… key …
98           ;; G_TYPE_INT (24) | array (0x80)
02           ;; count
18 01 01     ;; G_TYPE_INT, width 1, value 1
18 01 02     ;; G_TYPE_INT, width 1, value 2
```

Each array element carries its own type byte and payload (same encoding as a scalar of that type).

### Object array

**`Child[]`** — two `Child` instances, name token `1`:

```text
… name token …
D0           ;; G_TYPE_OBJECT (80) | array (0x80)
00 01        ;; name token 1 → "Child"
02           ;; count 2
… child 1 property stream … FF FD
… child 2 property stream … FF FD
```

### Heterogeneous array (`ANY[]`)

Rare. Type byte `0x80` only (base `0` + array flag):

```text
80           ;; ANY[]
02           ;; count
40           ;; elem 0: G_TYPE_STRING (64)
00 01 78     ;; "x"
18           ;; elem 1: G_TYPE_INT (24)
01 0A        ;; width 1, value 10
```

Each element carries its own `type_byte` and payload.

### Root result arrays (`Response.result`)

List **results** (`fetch_files`, …) encode as an object array on the **`result`** property of **`OLLMrpc.Response`** — not as a separate root message.

**Property type:** **`Gee.ArrayList<GLib.Object>`** — **`default = new Gee.ArrayList<GLib.Object>()`**; never null. Handlers populate **`result`** (length 0, 1, or N). Single-row RPCs use a one-element list — **🚫** no bare object on **`result`**.

**Encode:** omit **`result`** when **`result.size == 0`**. When **`size > 0`**, **`Response.bin_write_prop`** writes reg-id-first object arrays (`0xD0` + element `reg_id` + count + bodies); element **`GType`** from **`result.get(0)`**. **🚫** no **`is_array`** / **`result_type`** on handlers.

**Decode:** property present → **`Stream.parse_object_array()`**; property absent → default empty list. Clients: guard **`response.error`** only — **🚫** no **`response.result == null`**; one **`(Gee.ArrayList<T>) response.result`** cast — **🚫** no **`(Gee.ArrayList<GLib.Object>)`** hop. Single-row methods use **`list.get(0)`** when **`list.size > 0`**.

See `libocrpc/Response.vala`.

---

## 16. Omitted and default-valued properties

**Default `bin_write` walk** iterates all GObject properties (except `g-type-instance` and `ref-count`) and writes each supported scalar with its **current value**, including zero, empty string, and false. It does **not** skip properties at default values.

Properties omitted on write:

- **Null** nested `Serializable` object references — no name token appears.
- **Explicit skips** via `bin_write_prop` override (e.g. transient `extra` in `TestSkipDefault`).

On read, any property not present on the wire keeps its GObject default (typically set by `default = …` in Vala).

Writers omit transient fields by overriding `bin_write_prop`. Unsupported types throw `OLLMrpc.Bin.SerializableError`. Readers throw on unknown keys or undecodable properties. Array-flagged type bytes (`0x80` on bit 7) require a `bin_read_prop` override on the receiving type.

### Override recipes

Overrides use **`switch (prop.name)`** with early **`return`** for special cases; the **`default:`** branch delegates to stock encoding:

```vala
public override void bin_write_prop (
    OLLMrpc.Bin.Stream ctx,
    GLib.ParamSpec prop
) throws GLib.Error
{
    switch (prop.name) {
        case "manager":
        case "buffer":
        case "parent":
            return;
        default:
            bin_default_write_prop (ctx, prop);
            return;
    }
}
```

Mirror the same prop names in **`bin_read_prop`** (ignore unknown wire keys for omitted props).

| Scenario | Approach | Example |
| -------- | -------- | ------- |
| Graph / runtime omits | **`switch`** + early **`return`** | `ollmfilesd/File.vala` — `manager`, `buffer`, `parent` |
| Skip unsupported prop | Override **`bin_write`** and skip the prop name, or omit in **`bin_write_prop`** | `TestSkipDefault` in `bin-test.vala` |
| **`Gee.ArrayList<T>`** on a property | Inline encode/decode in **`case`** — **`write_gtype(T, OBJECT \| 0x80)`**, count, **`child.bin_write`** per element | `TestListBag` in `bin-test.vala` |
| Root list **result** | Override on **`Response.bin_write_prop`** / **`bin_read_prop`**; omit **`result-type`** / **`is-array`** on write; decode via **`parse_object_array()`** | `libocrpc/Response.vala` |
| **`string[]`** param | Default codec — no override | `CallParam.args`, `TestPaths` |

**🚫** Do not call **`base.bin_write_prop`** — use **`bin_default_write_prop`** / **`bin_default_read_prop`** for the default branch.

---

## 17. Unsupported types

Not defined in version 3.0:

- `float`, `double`, `date`
- varint / LEB128 / zigzag integers
- raw `GType` numbers on the wire (name tokens + `register()` aliases only)

---

## 18. JSON bridge (`OLLMrpc.Bin.Json`)

**Purpose:** encode/decode json-glib nodes directly onto a **`Bin.Stream`** — for tests and tooling, **not** for production TCP/socket RPC.

**Caller today:** **`ollmfilesd/StdioConnection`** (`--interactive`, `--rpc-script`) — NDJSON lines on stdin are converted to bin **`Request`** objects via **`Bin.Json.write`**, then handled like any other connection. Outbound responses use **`bin.write`** → **`Bin.Json.parse`** → NDJSON line (symmetric bridge; not used on production TCP/socket path).

**No `Serializable` instances:** layout follows JSON node shape + wire type bytes only.

### Meta keys (not payload properties)

| Key | Meaning |
| --- | ------- |
| `"*type"` | Required on every object — wire alias (`"File"`, `"Request"`, …). Must be registered via **`Bin.register`**. |
| `"*array"` | Object-array wrapper — paired with `"items"` |
| `"items"` | Array body when `"*array"` is set |

Any key starting with **`*`** is meta only and is stripped before bin encode.

### JSON shapes → wire

| JSON shape | Wire |
| ---------- | ---- |
| `{ "*type": "File", "path": "…" }` | Root or nested object |
| `{ "*array": "File", "items": [ … ] }` | Object array (`0xD0`) |
| `[ "a", "bb" ]` | `string[]` (`0xC0`) |
| `[ { "*type": "File", … }, … ]` | Object array (element type from first object) |

### Example (stdio script line → bin)

```json
{"*type":"Request","id":1,"method":"Folder.fetch_files","param":{"*type":"FolderParams","path":"/tmp"}}
```

`StdioConnection.request_from_json_line` calls **`json_codec.write(encode_ctx, root)`**, then **`read_ctx.parse()`** as **`Request`**.

Implementation: `libocrpc/Bin/Json.vala`. Used by the stdio test harness only — not the production TCP/socket path.

---

## Quick reference

```text
TOKEN_REG_KEY   = FFFF (uint16)   ;; introduce property key name
TOKEN_REG_TYPE  = FFFE (uint16)   ;; type alias: FF FE + reg_id + alias (§5–§6)
TOKEN_END       = FFFD (uint16)

array flag = bit 7 (0x80) OR'd onto GLib.Type fundamental

GLib.Type fundamentals (typical GLib 2.x):
  INVALID  = 00
  CHAR     = 0C
  UCHAR    = 10
  BOOLEAN  = 14
  INT      = 18
  UINT     = 1C
  INT64    = 28
  UINT64   = 2C
  ENUM     = 30
  FLAGS    = 34
  BOXED    = 48
  OBJECT   = 50
  STRING   = 40
```
