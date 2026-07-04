# Binary RPC wire format

**Version 3.0**

This document defines the on-the-wire byte layout for `OLLMrpc.Bin` object bodies. A message is one root object: a type header, a sequence of properties, and an end marker. Multi-byte integers are **big-endian** unless noted otherwise.

The **type byte** on the wire is always a `GLib.Type` fundamental value (optionally OR'd with the array flag). There is no separate compact wire-type enum.

---

## 1. Overview

A **connection** maintains three tables on its `OLLMrpc.Bin.Stream` instance:

1. **Property names** — learned on the wire via `TOKEN_REG_KEY` (`"name"`, `"count"`, … → uint16 key tokens).
2. **Object type aliases** — registered locally via `Stream.register(alias, gtype)` before decode. Each end maps alias strings to `GLib.Type`; **registration order does not matter**.
3. **Wire `reg_id` ↔ alias** — learned on the wire via `TOKEN_REG_TYPE` when a type is first sent. The sender assigns numeric `reg_id`s JIT; the receiver records the mapping from the introduction block.

Every **property value**: key token → one-byte **type** (`GLib.Type` fundamental) → payload. When the type is `GLib.Type.OBJECT`, a **`reg_id`** follows before the nested property stream. Unknown key or unknown `reg_id` (with no prior `TOKEN_REG_TYPE` for that id) → protocol error.

### Registration vs JSON RPC

Bin registration is **per connection** and maps **alias → GType**:

```vala
var bin = new OLLMrpc.Bin.Stream (in_stream, out_stream);
bin.register ("File", typeof (OLLMfiles.V2.File));
bin.register ("Folder", typeof (OLLMfiles.V2.Folder));
```

Client and server each call `register()` with the **same alias strings** and matching `GLib.Type` values. Call order on either side is arbitrary. Numeric `reg_id`s are **not** assigned at `register()` time — they are negotiated on the wire per connection when a type is first encoded.

JSON RPC today uses a separate, **process-wide** map via `OLLMrpc.register(name, gtype)` keyed by string names in `Response.result_type`. The two APIs coexist until bin cutover (see plan 8.1). Aliases should match JSON wire names where both apply.

Domain types implement `OLLMrpc.Bin.Serializable` (often by extending `OLLMrpc.Bin.Object`) for bin encoding. JSON `rpc_register()` does **not** register types on a `Stream` — that happens at channel setup.

---

## 2. Walkthrough: `TestPair`

Vala type (registered as `"TestPair"`):

```vala
public class TestPair : OLLMrpc.Bin.Object {
    public string name { get; set; default = ""; }
    public int count { get; set; default = 0; }
}
```

Object on the wire:

```vala
new TestPair () { name = "alpha", count = 42 }
```

**First** message (keys `"name"` and `"count"` not yet seen on this connection; type `"TestPair"` not yet sent):

```text
;; --- introduce type "TestPair" (first send on this connection) ---
FF FE                    ;; TOKEN_REG_TYPE
00                       ;; assigned reg_id 0
08                       ;; alias length
54 65 73 74 50 61 69 72  ;; "TestPair"

;; --- root object header ---
50                       ;; G_TYPE_OBJECT (80)
00                       ;; reg_id 0 → TestPair

;; --- property "name" = "alpha" (first sight of key "name") ---
FF FF                    ;; TOKEN_REG_KEY
00 00                    ;; assigned key token 0
04                       ;; name length
6E 61 6D 65              ;; "name"
00 00                    ;; key token 0 (reference)
40                       ;; type byte: G_TYPE_STRING (64)
00 05                    ;; UTF-8 length 5
61 6C 70 68 61           ;; "alpha"

;; --- property "count" = 42 (first sight of key "count") ---
FF FF                    ;; TOKEN_REG_KEY
00 01                    ;; assigned key token 1
05                       ;; name length
63 6F 75 6E 74           ;; "count"
00 01                    ;; key token 1 (reference)
18                       ;; type byte: G_TYPE_INT (24)
01                       ;; width: 1 byte payload
2A                       ;; value 42

;; --- end of object ---
FF FD                    ;; TOKEN_END
```

**Second** message of the same type on the same connection (keys and alias already cached):

```text
50                       ;; G_TYPE_OBJECT (80)
00                       ;; reg_id 0
00 00                    ;; key token 0 → "name"
40                       ;; G_TYPE_STRING (64)
00 05
61 6C 70 68 61           ;; "alpha"
00 01                    ;; key token 1 → "count"
18                       ;; G_TYPE_INT (24)
01 2A                    ;; width 1, value 42
FF FD                    ;; TOKEN_END
```

No `TOKEN_REG_KEY` blocks appear again until a new property name is seen.

---

## 3. Root object layout

```text
50                              ;; GLib.Type.OBJECT (80), array flag clear
reg_id                          ;; 1 byte (0–127) or 2-byte escape (see §6)
properties…                     ;; zero or more property encodings
FF FD                           ;; TOKEN_END (uint16)
```

A root message is **never** an object array (`0xD0` = `GLib.Type.OBJECT | 0x80`).

---

## 4. Property layout

Each property:

```text
key_token    uint16     ;; cached id, or TOKEN_REG_KEY introduction (§5)
type_byte    uint8      ;; GLib.Type fundamental + optional array flag (§7)
reg_id       0–2 bytes  ;; only when base type is GLib.Type.OBJECT (0x50)
payload      …          ;; depends on type (§8–§14)
```

The object ends with `FF FD` (`TOKEN_END`).

---

## 5. Property key tokens (uint16)

| Value | Meaning |
| ----- | ------- |
| `0xFFFF` | `TOKEN_REG_KEY` — introduce a new property name |
| `0xFFFD` | `TOKEN_END` — end of property stream |

**Introduction** (first time `"label"` is sent):

```text
FF FF           TOKEN_REG_KEY
00 02           assigned id 2
05              name length
6C 61 62 65 6C  "label"
00 02           reference id 2
…               type_byte + payload follow
```

**Cached reference** (every later `"label"`):

```text
00 02           key token 2 only
…               type_byte + payload
```

Property names are limited to 255 bytes on introduction.

---

## 6. Object type registration and `reg_id`

### `Stream.register(alias, gtype)`

Call on each `OLLMrpc.Bin.Stream` after the channel opens and **before** decoding messages that use those types. Each end maintains `alias → GLib.Type`. **Registration order is not significant** — only the alias string and `GType` must match on both sides.

- Duplicate alias on the same stream → error.
- `register()` does **not** assign wire `reg_id`s.
- The receiver must have registered an alias before it can accept a `TOKEN_REG_TYPE` introduction for that alias.

### Wire `reg_id` (JIT, per connection)

When a type is **first encoded** on a connection, the sender emits `TOKEN_REG_TYPE` before the `GLib.Type.OBJECT` header:

```text
FF FE                    ;; TOKEN_REG_TYPE
reg_id                   ;; encoded as in table below (§6)
alias_len                ;; uint8
alias_bytes              ;; UTF-8 alias (must match a prior register() on the receiver)
50                       ;; G_TYPE_OBJECT — follows immediately after introduction
reg_id                   ;; same id as above
… properties …
FF FD
```

Later messages of the same type omit `TOKEN_REG_TYPE` and send only `50` + `reg_id`.

- `write_gtype()` assigns the next local `reg_id` on first send of each alias and emits the introduction.
- `read_reg_gtype()` (after seeing `0xFF 0xFE`) records `reg_id → alias` on the receiver.
- `parse_object()` reads `reg_id` → alias → `GLib.Type`, then `GLib.Object.new(gtype)` and `bin_read()`.
- Unknown `reg_id` without a prior introduction → error.

Example (from `tests/rpc/bin-test.vala` — reader may register in any order):

```vala
write_bin.register ("TestPair", typeof (TestPair));
write_bin.register ("TestParent", typeof (TestParent));

// Reader: same aliases, any order
read_bin.register ("TestParent", typeof (TestParent));
read_bin.register ("TestPair", typeof (TestPair));
```

### `reg_id` encoding

| id range | Bytes |
| -------- | ----- |
| 0–127 | one byte, bit 7 clear — e.g. `00`, `7F` |
| ≥ 128 (rare) | two bytes: `(0x80 \| (id >> 8))`, then `(id & 0xFF)` |

Example: reg_id `200` → `80 C8` (because `0x80 | 0` = `0x80`, low byte `0xC8`).

Alias strings are limited to 255 bytes on introduction.

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

There is no two-byte type encoding. The two-byte escape applies only to **`reg_id`**, not the type byte.

Numeric values follow the platform's GObject fundamentals (shown here for a typical GLib 2.x build). The implementation writes `(uint8) GLib.Type.*` directly.

---

## 8. `bool`

Vala: `enabled = true`

```text
14        ;; G_TYPE_BOOLEAN (20)
01        ;; true (false = 00)
```

With key token prefix, a cached property looks like:

```text
00 03     ;; key token for "enabled"
14 01     ;; G_TYPE_BOOLEAN, true
```

---

## 9. `string`

Vala: `name = "hi"`

```text
40           ;; G_TYPE_STRING (64)
00 02        ;; length 2 (uint16 BE)
68 69        ;; "hi"
```

Max length 65535. Longer payloads use `GLib.Type.BOXED` (`0x48`) with a uint32 length prefix (§13).

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

Large binary (`GLib.Type.BOXED`). Vala types use a custom `bin_write_prop` override; default scalar walk does not emit blobs automatically.

```text
48                       ;; G_TYPE_BOXED (72)
00 00 04 D2              ;; uint32 length 1234
… 1234 raw bytes …
```

---

## 14. Nested object

Default `bin_write_prop` / `bin_read_prop` encode nested `Bin.Serializable` objects. Null object properties are omitted on write. The nested value's type must be registered on the stream (`register()`).

Single object — registered as `"Child"`, reg_id `1`:

```text
50           ;; G_TYPE_OBJECT (80)
01           ;; reg_id 1
…            ;; Child property stream
FF FD        ;; TOKEN_END
```

Full property (cached key token `4` for `"child"`):

```text
00 04        ;; key token
50 01        ;; G_TYPE_OBJECT + reg_id 1
… child props …
FF FD
```

Nested encoding does **not** repeat the type byte before `reg_id` inside `write_gtype()` output — `write_gtype` emits `0x50` + `reg_id`, then `bin_write` emits the property stream.

---

## 15. Arrays

Set bit 7 on the type byte, then a **count**, then elements.

**Vala:** native arrays (`string[]`, `int[]`, …), `Gee.ArrayList<T>`, and `uint8[]` are **not** encoded by the default property walk. Override `bin_write_prop` / `bin_read_prop` on the owning type. Scalar element arrays use the layouts below; opaque byte buffers typically use §13 blob (`GLib.Type.BOXED` on the wire).

### Short list (count ≤ 255)

`uint8` element count, then each element.

**`string[]`** — `["a", "bb"]` (cached key token `5`):

```text
00 05        ;; key token
C0           ;; G_TYPE_STRING (64) | array (0x80)
02           ;; count 2
00 01 61     ;; len 1, "a"
00 02 62 62  ;; len 2, "bb"
```

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

**`Child[]`** — two `Child` instances, reg_id `1`:

```text
… key …
D0           ;; G_TYPE_OBJECT (80) | array (0x80)
01           ;; reg_id 1
02           ;; count 2
… child 1 property stream … FF FD
… child 2 property stream … FF FD
```

### Long list

Same layouts, but `uint32` BE count instead of `uint8` when more than 255 elements.

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

---

## 16. Omitted and default-valued properties

**Default `bin_write` walk** iterates all GObject properties (except `g-type-instance` and `ref-count`) and writes each supported scalar with its **current value**, including zero, empty string, and false. It does **not** skip properties at default values.

Properties omitted on write:

- **Null** nested `Serializable` object references — no key token appears.
- **Explicit skips** via `bin_write_prop` override (e.g. transient `extra` in `TestSkipDefault`).

On read, any property not present on the wire keeps its GObject default (typically set by `default = …` in Vala).

Writers omit transient fields by overriding `bin_write_prop`. Unsupported types throw `GLib.Error`. Readers throw on unknown keys or undecodable properties. Array-flagged type bytes (`0x80` on bit 7) require a `bin_read_prop` override on the receiving type.

---

## 17. Unsupported types

Not defined in version 3.0:

- `float`, `double`, `date`
- varint / LEB128 / zigzag integers
- raw `GType` numbers on the wire (aliases + `reg_id` only)

---

## Quick reference

```text
TOKEN_REG_KEY   = FFFF (uint16)   ;; introduce property name
TOKEN_REG_TYPE  = FFFE (uint16)   ;; introduce type alias: FF FE + reg_id + alias (§6)
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
