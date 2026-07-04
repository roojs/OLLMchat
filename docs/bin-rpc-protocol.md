# Binary RPC wire format

**Version 3.0**

This document defines the on-the-wire byte layout for `OLLMrpc.Bin` object bodies. A message is one root object: a type header, a sequence of properties, and an end marker. Multi-byte integers are **big-endian** unless noted otherwise.

---

## 1. Overview

A **connection** maintains two tables:

1. **Property names** — learned on the wire via `TOKEN_REG_KEY` (`"name"`, `"count"`, … → uint16 key tokens).
2. **Object types** — assigned at `register()` before any messages. Both ends call `register("TestPair", typeof(TestPair))` in the **same order**; that assigns `reg_id` 0, 1, 2… No type names are sent on the wire.

Every **property value**: key token → one-byte **type** → payload. Unknown key or unknown `reg_id` → protocol error.

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

**First** message (keys `"name"` and `"count"` not yet seen on this connection):

```text
;; --- root object header (TestPair is reg_id 0 from register()) ---
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

A root message is **never** an object array (`0x86`).

---

## 4. Property layout

Each property:

```text
key_token    uint16     ;; cached id, or TOKEN_REG_KEY introduction (§5)
type_byte    uint8      ;; base type + optional array flag (§7)
reg_id       0–2 bytes  ;; only when base type is WIRE_OBJECT (6)
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

---

## 6. Object type `reg_id`

Both ends call `register(alias, gtype)` at connect time, in the **same order**. The first call gets `reg_id` 0, the second gets 1, and so on. The wire carries only the numeric `reg_id`, never the alias string.

### `reg_id` encoding

| id range | Bytes |
| -------- | ----- |
| 0–127 | one byte, bit 7 clear — e.g. `00`, `7F` |
| ≥ 128 (rare) | two bytes: `(0x80 \| (id >> 8))`, then `(id & 0xFF)` |

Example: reg_id `200` → `80 C8` (because `0x80 | 0` = `0x80`, low byte `0xC8`).

---

## 7. Type byte (uint8)

Always **exactly one byte** per property value. The low seven bits (when bit 7 is clear) are the **`GLib.Type` fundamental** value. Bit 7 (`0x80`) is the **array flag** only.

| `type_byte` | `GLib.Type` | Meaning |
| ----------- | ----------- | ------- |
| `0x00` | `INVALID` | heterogeneous array only (`0x80`) |
| `0x14` | `BOOLEAN` (20) | `bool` |
| `0x40` | `STRING` (64) | `string` |
| `0x0C` | `CHAR` (12) | `char` / `int8` |
| `0x10` | `UCHAR` (16) | `uchar` |
| `0x18` | `INT` (24) | `int` |
| `0x1C` | `UINT` (28) | `uint` |
| `0x28` | `INT64` (40) | `int64` |
| `0x2C` | `UINT64` (44) | `uint64` |
| `0x30` | `ENUM` (48) | any `enum` |
| `0x34` | `FLAGS` (52) | any `flags` |
| `0x50` | `GObject` (80) | registered object — `reg_id` follows |
| `0x48` | `BOXED` (72) | large binary blob |

Array examples (set bit 7):

| `type_byte` | Meaning |
| ----------- | ------- |
| `0xC0` | `string[]` (`STRING` \| `0x80`) |
| `0xD0` | `object[]` (`GObject` \| `0x80`) |
| `0x80` | `ANY[]` (`INVALID` \| `0x80`) — each element has its own type byte |

There is no two-byte type encoding. The two-byte escape applies only to **`reg_id`**, not the type byte.

Numeric values follow the platform’s GObject fundamentals (shown here for a typical GLib 2.x build).

---

## 8. `bool`

Vala: `enabled = true`

```text
01        ;; WIRE_BOOL
01        ;; true (false = 00)
```

With key token prefix, a cached property looks like:

```text
00 03     ;; key token for "enabled"
01 01     ;; bool true
```

---

## 9. `string`

Vala: `name = "hi"`

```text
02           ;; WIRE_STRING
00 02        ;; length 2 (uint16 BE)
68 69        ;; "hi"
```

Max length 65535. Longer payloads use `WIRE_BLOB` (`0x07`) with a uint32 length prefix.

---

## 10. Narrow integer

Vala: `code = (int8) -3` (or `char` / `uchar` — one raw byte)

```text
03     ;; WIRE_NARROW
FD     ;; raw byte (two's complement for signed types)
```

No width prefix.

---

## 11. Signed wide integer

Used for `int`, `int64`, and `enum`.

**Short** (fits in −128…127) — Vala: `count = 42`

```text
04     ;; WIRE_SIGNED
01     ;; width 1
2A     ;; 42
```

**Long** — Vala: `count = 1000`

```text
04     ;; WIRE_SIGNED
08     ;; width 8
00 00 00 00 00 00 03 E8   ;; int64 1000, big-endian
```

Only width bytes `01` and `08` are valid.

---

## 12. Unsigned wide integer

Used for `uint`, `uint64`, and `flags`.

**Short** (0…255) — Vala: `flags = 7`

```text
05     ;; WIRE_UNSIGNED
01     ;; width 1
07
```

**Long** — Vala: `id = 1000`

```text
05     ;; WIRE_UNSIGNED
08     ;; width 8
00 00 00 00 00 00 03 E8
```

---

## 13. Blob

Large binary (`WIRE_BLOB`). Vala types use a custom `bin_write_prop` override; default scalar walk does not emit blobs automatically.

```text
07                       ;; WIRE_BLOB
00 00 04 D2              ;; uint32 length 1234
… 1234 raw bytes …
```

---

## 14. Nested object

Default `bin_write_prop` / `bin_read_prop` encode nested `Bin.Serializable` objects. Null object properties are omitted on write. The nested value must be registered on the stream (`register()`).

Single object — registered as `"Child"`, reg_id `1`:

```text
06           ;; WIRE_OBJECT
01           ;; reg_id 1
…            ;; Child property stream
FF FD        ;; TOKEN_END
```

Full property (cached key token `4` for `"child"`):

```text
00 04        ;; key token
50 01        ;; GLib.Type.OBJECT + reg_id 1
… child props …
FF FD
```

---

## 15. Arrays

Set bit 7 on the type byte, then a **count**, then elements.

**Vala:** native arrays (`string[]`, `int[]`, …), `Gee.ArrayList<T>`, and `uint8[]` are **not** encoded by the default property walk. Override `bin_write_prop` / `bin_read_prop` on the owning type. Scalar element arrays use the layouts below; opaque byte buffers typically use §13 blob (`GLib.Type.BOXED` on the wire).

### Short list (count ≤ 255)

`uint8` element count, then each element.

**`string[]`** — `["a", "bb"]` (cached key token `5`):

```text
00 05        ;; key token
82           ;; WIRE_STRING | array
02           ;; count 2
00 01 61     ;; len 1, "a"
00 02 62 62  ;; len 2, "bb"
```

**`int[]`** — `[1, 2]`:

```text
… key …
84           ;; WIRE_SIGNED | array
02           ;; count
01 01        ;; width 1, value 1
01 02        ;; width 1, value 2
```

### Object array

**`Child[]`** — two `Child` instances, reg_id `1`:

```text
… key …
86           ;; WIRE_OBJECT | array
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
02           ;; elem 0: WIRE_STRING
00 01 78     ;; "x"
04           ;; elem 1: WIRE_SIGNED
01 0A        ;; 10
```

Each element carries its own `type_byte` and payload.

---

## 16. Omitted properties

If a property is not written, nothing appears on the wire for it — no key token, no type byte, no payload. On read, the GObject field keeps its default.

Writers omit transient fields by overriding `bin_write_prop`. Unsupported types throw `GLib.Error`. Readers throw on unknown keys or undecodable properties. Array-flagged type bytes (`0x80` on bit 7) require a `bin_read_prop` override on the receiving type.

---

## 17. Unsupported types

Not defined in version 3.0:

- `float`, `double`, `date`
- varint / LEB128 / zigzag integers
- raw `GType` numbers (aliases + `reg_id` only)

---

## Quick reference

```text
TOKEN_REG_KEY   = FFFF (uint16)
TOKEN_REG_TYPE  = FFFE (uint16)
TOKEN_END       = FFFD (uint16)

array flag (bit 7, `0x80`)

WIRE_ANY        = 0
WIRE_BOOL       = 1
WIRE_STRING     = 2
WIRE_NARROW     = 3
WIRE_SIGNED     = 4
WIRE_UNSIGNED   = 5
WIRE_OBJECT     = 6
WIRE_BLOB       = 7
```
