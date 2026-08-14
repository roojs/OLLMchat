# Bin RPC: duplex wire-name token collision (`alias mismatch`)

**Status:** ⏳ OPEN — dual-table fix applied; await verify (rebuild matching client+daemon)

**Started:** 2026-08-14 · **Updated:** 2026-08-14

**Related:** [`2026-08-13-is-text-content-type-fallback.md`](2026-08-13-is-text-content-type-fallback.md) (restore `File.fetch` after activate hit this while testing Approvals / `is_text`)

**Wire docs:** [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md) §1 (per-connection `client_names` / `server_names`, even/odd)

---

## Problem

🔷 Client and daemon on the **same** bin socket can both introduce new wire names (`TOKEN_REG_KEY` / `TOKEN_REG_TYPE`) at the same time. Today both use `id = names.length` on **one** shared table → colliding token ids for different strings → protocol abort.

**Expected:** Duplex traffic (client request while daemon sends reply/notification) never corrupts the name table.

**Actual:** `wire name token N alias mismatch` → `GLib.error` → process abort (client and/or daemon).

---

## Evidence (2026-08-14 ~08:50)

✔️ Live after activate + session restore `File.fetch`:

```text
Client:  replied id=6 ProjectManager.activate_project
Client:  id=7 method=File.fetch
Client:  wire name token 48 alias mismatch   → Trace/breakpoint (core dumped)

Daemon:  reply id=6 activate_project
Daemon:  filesystem scan queued …
Daemon:  wire name token 48 alias mismatch
```

✔️ Daemon `activate_project` **replies first**, then emits `event.filesystem.scan_start`. Client restore sends `File.fetch` immediately after. Both sides mint new name tokens on the same connection.

✔️ Multi-client is **not** the issue: each connection already has its own `Stream`. The race is **two writers on one link**.

---

## Root cause

✔️ **`OLLMrpc.Bin.Stream` keeps a single dense `names[]` / `name_to_token`.**  
Writers assign `id = names.length`. Concurrent intros with the same next id for different strings → `alias mismatch`.

ℹ️ Property keys on arrays of objects **must** stay tokenized — 🚫 “only one side may introduce names”.

---

## Type aliases (clarification)

🔷 **`Bin.register("File", typeof(…))` is process-local** — each end maps the **alias string** to its own `GLib.Type`. That does **not** cross the wire as a GType.

✔️ On the wire today, `TOKEN_REG_TYPE` still puts that **alias string** into the **same** per-connection `names[]` and then uses a short `reg_id` (same index space as property keys). So type intros **can** race with key intros under the current single table.

🔷 Dual-table fix: treat type-alias strings like any other wire name — **allocate in the writer’s table**; `alias_to_gtype` lookup stays process-local after the string is known. No separate “type-only” protocol unless we choose one later.

---

## Rejected / deferred

🚫 Only one side introduces names.  
🚫 Client lease / request number blocks.  
💩 Alternating id batches — workable; dual tables clearer.

---

## Locked design (proposal)

🔷 **Even = client, odd = server** on the wire token.

🔷 **Yes — you need two string arrays** (`client_names` / `server_names`).  
A single shared `names.length` cannot be the allocator for both ends (that is today’s race). Each side uses **its own** `.length` as the next local index, then:

- client wire = `client_names.length * 2`
- server wire = `server_names.length * 2 + 1`

🔷 On read, parity selects the table; local index = `wire / 2`.

🔷 `name_to_token` still maps string → full wire uint16 (even or odd).

🔷 `is_server` on `Stream` construct: client false, daemon `Connection` true.

🔷 Type-alias **strings** live in the same two tables; `Bin.register` / `alias_to_gtype` stay process-local.

🚫 High-bit table flag. 🚫 One shared `names[]` + `.length` for both roles.

---

### 1. `libocrpc/Bin/Stream.vala` — split `names` + `is_server`

**Why:** Two lengths so each role can allocate without colliding.

**Where:** fields above `TOKEN_REG_KEY`.

**Depends on:** none.

#### Keep
```vala
		public Mode mode { get; set; default = Mode.EXPLICIT; }
```

#### Remove
```vala
		internal string[] names = {};
		internal Gee.HashMap<string, uint16> name_to_token =
			new Gee.HashMap<string, uint16>();
```

#### Replace with
```vala
		internal string[] client_names = {};
		internal string[] server_names = {};
		internal Gee.HashMap<string, uint16> name_to_token =
			new Gee.HashMap<string, uint16>();
		public bool is_server { get; construct; default = false; }
```

---

### 2. `libocrpc/Bin/Stream.vala` — `write_tag`: allocate even/odd

**Why:** Writer uses own table `.length` → wire parity.

**Where:** `write_tag`, the block that assigns a new id (after the `name_to_token.has_key` hit-return).

**Depends on:** §1.

#### Keep
```vala
			if (this.name_to_token.has_key(prop_name)) {
				this.out_stream.put_uint16(this.name_to_token.get(prop_name));
				return;
			}
```

#### Remove
```vala
			var id = (uint16) this.names.length;
			this.out_stream.put_uint16(TOKEN_REG_KEY);
			this.out_stream.put_uint16(id);

			var len = (uint8) uint.min(prop_name.length, 255);
			this.out_stream.put_byte(len);
			size_t written;
			this.out_stream.write_all(((uint8[]) prop_name)[0:len], out written);

			this.names += prop_name;
			this.name_to_token.set(prop_name, id);
			this.out_stream.put_uint16(id);
```

#### Replace with
```vala
			var mine = this.is_server ? this.server_names : this.client_names;
			var local = (uint16) mine.length;
			var wire = this.is_server ? (uint16) (local * 2 + 1) : (uint16) (local * 2);
			this.out_stream.put_uint16(TOKEN_REG_KEY);
			this.out_stream.put_uint16(wire);

			var len = (uint8) uint.min(prop_name.length, 255);
			this.out_stream.put_byte(len);
			size_t written;
			this.out_stream.write_all(((uint8[]) prop_name)[0:len], out written);

			if (this.is_server) {
				this.server_names += prop_name;
			} else {
				this.client_names += prop_name;
			}
			this.name_to_token.set(prop_name, wire);
			this.out_stream.put_uint16(wire);
```

---

### 3. `libocrpc/Bin/Stream.vala` — `read_tag`: short token lookup

**Why:** Resolve even/odd into the right table.

**Where:** `read_tag`, the `if (t != TOKEN_REG_KEY)` branch body.

**Depends on:** §1.

#### Keep
```vala
			if (t != TOKEN_REG_KEY) {
```

#### Remove
```vala
				if (t >= this.names.length) {
					throw new StreamError.PROTOCOL(
						"unknown wire name token %u",
						t
					);
				}
				prop_name = this.names[t];
				return t;
```

#### Replace with
```vala
				var server = (t & 1) != 0;
				var local = (uint16) (t / 2);
				var table = server ? this.server_names : this.client_names;
				if (local >= table.length) {
					throw new StreamError.PROTOCOL(
						"unknown wire name token %u",
						t
					);
				}
				prop_name = table[local];
				return t;
```

---

### 4. `libocrpc/Bin/Stream.vala` — `read_tag`: `TOKEN_REG_KEY` intro

**Why:** Peer REG stores into the table selected by wire parity (not `this.names`).

**Where:** `read_tag`, from `assigned_id` through `name_to_token.set` (before the recursive `return this.read_tag`).

**Depends on:** §1.

#### Keep
```vala
			var assigned_id = this.in_stream.read_uint16();
			var len = this.in_stream.read_byte();

			var buffer = new uint8[len + 1];
			size_t read_bytes;
			this.in_stream.read_all(buffer[0:len], out read_bytes);
			buffer[len] = 0;
			prop_name = (string) buffer;
```

#### Remove
```vala
			if (assigned_id > this.names.length) {
				throw new StreamError.PROTOCOL(
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (assigned_id < this.names.length && this.names[assigned_id] != prop_name) {
				throw new StreamError.PROTOCOL(
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			if (assigned_id == this.names.length) {
				this.names += prop_name;
			}
			this.name_to_token.set(prop_name, assigned_id);
```

#### Replace with
```vala
			var server = (assigned_id & 1) != 0;
			var local = (uint16) (assigned_id / 2);
			var table = server ? this.server_names : this.client_names;
			if (local > table.length) {
				throw new StreamError.PROTOCOL(
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (local < table.length && table[local] != prop_name) {
				throw new StreamError.PROTOCOL(
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			if (local == table.length) {
				if (server) {
					this.server_names += prop_name;
				} else {
					this.client_names += prop_name;
				}
			}
			this.name_to_token.set(prop_name, assigned_id);
```

ℹ️ Writer’s `TOKEN_REG_KEY` payload is the **full even/odd wire** id (§2), not a dense local-only index.

---

### 5. `libocrpc/Bin/Stream.vala` — `write_reg_gtype`: same allocator as keys

**Why:** Type alias strings use the writer’s table + even/odd wire id.

**Where:** `write_reg_gtype`, from `new_reg_id = names.length` through `name_to_token.set`.

**Depends on:** §1.

#### Keep
```vala
			if (this.name_to_token.has_key(gtype_to_alias.get(object_type))) {
				return;
			}
```

#### Remove
```vala
			var new_reg_id = (uint) this.names.length;

			this.out_stream.put_byte(0xFF);
			this.out_stream.put_byte(0xFE);
			if (new_reg_id < 128) {
				this.out_stream.put_byte((uint8) new_reg_id);
			} else {
				this.out_stream.put_byte((uint8) (0x80 | ((new_reg_id >> 8) & 0x7F)));
				this.out_stream.put_byte((uint8) (new_reg_id & 0xFF));
			}
```

#### Replace with
```vala
			var alias = gtype_to_alias.get(object_type);
			var mine = this.is_server ? this.server_names : this.client_names;
			var local = (uint) mine.length;
			var wire = this.is_server
				? (uint16) (local * 2 + 1)
				: (uint16) (local * 2);

			this.out_stream.put_byte(0xFF);
			this.out_stream.put_byte(0xFE);
			if (wire < 128) {
				this.out_stream.put_byte((uint8) wire);
			} else {
				this.out_stream.put_byte((uint8) (0x80 | ((wire >> 8) & 0x7F)));
				this.out_stream.put_byte((uint8) (wire & 0xFF));
			}
```

#### Keep
```vala
			this.out_stream.put_byte(
				(uint8) uint.min(
					gtype_to_alias.get(object_type).length,
					255
				)
			);
			size_t written;
			this.out_stream.write_all(
				((uint8[]) gtype_to_alias.get(object_type))[
					0:uint.min(
						gtype_to_alias.get(object_type).length,
						255
					)
				],
				out written
			);
```

#### Remove
```vala
			this.names += gtype_to_alias.get(object_type);
			this.name_to_token.set(
				gtype_to_alias.get(object_type),
				(uint16) new_reg_id
			);
```

#### Replace with
```vala
			if (this.is_server) {
				this.server_names += alias;
			} else {
				this.client_names += alias;
			}
			this.name_to_token.set(alias, wire);
```

ℹ️ Early `has_key(gtype_to_alias.get(…))` Keep above still uses the getter twice; after apply, the new `alias` local is only for the allocate path. Optionally change the early return to `has_key(alias)` in the same edit if you introduce `alias` before it — not required for correctness.

---

### 6. `libocrpc/Bin/Stream.vala` — `read_gtype`: parity lookup

**Why:** Type short id is even/odd wire token into the dual tables.

**Where:** `read_gtype`, after `reg_id` is fully read.

**Depends on:** §1, §5.

#### Keep
```vala
			if ((reg_b & 0x80) != 0) {
				reg_id = ((uint) (reg_b & 0x7F) << 8) | this.in_stream.read_byte();
			}
```

#### Remove
```vala
			if (reg_id >= this.names.length) {
				throw new StreamError.PROTOCOL(
					"unknown wire name token %u",
					reg_id
				);
			}
			if (!alias_to_gtype.has_key(this.names[reg_id])) {
				throw new StreamError.REGISTRATION(
					"Unrecognized type alias: %s",
					this.names[reg_id]
				);
			}

			return alias_to_gtype.get(this.names[reg_id]);
```

#### Replace with
```vala
			var server = (reg_id & 1) != 0;
			var local = (uint16) (reg_id / 2);
			var table = server ? this.server_names : this.client_names;
			if (local >= table.length) {
				throw new StreamError.PROTOCOL(
					"unknown wire name token %u",
					reg_id
				);
			}
			if (!alias_to_gtype.has_key(table[local])) {
				throw new StreamError.REGISTRATION(
					"Unrecognized type alias: %s",
					table[local]
				);
			}

			return alias_to_gtype.get(table[local]);
```

---

### 7. `libocrpc/Bin/Stream.vala` — `read_reg_gtype`: store by parity

**Why:** Same as property REG — wire id is even/odd.

**Where:** `read_reg_gtype`, the `assigned_id` vs `names` checks at the end.

**Depends on:** §1, §5.

#### Keep
```vala
			if (!alias_to_gtype.has_key(alias)) {
				throw new StreamError.REGISTRATION(
					"Unrecognized type alias: %s",
					alias
				);
			}
```

#### Remove
```vala
			if (assigned_id > this.names.length) {
				throw new StreamError.PROTOCOL(
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (assigned_id < this.names.length && this.names[assigned_id] != alias) {
				throw new StreamError.PROTOCOL(
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			if (assigned_id == this.names.length) {
				this.names += alias;
			}
			this.name_to_token.set(alias, (uint16) assigned_id);
```

#### Replace with
```vala
			var server = (assigned_id & 1) != 0;
			var local = (uint16) (assigned_id / 2);
			var table = server ? this.server_names : this.client_names;
			if (local > table.length) {
				throw new StreamError.PROTOCOL(
					"wire name token %u out of sequence",
					assigned_id
				);
			}
			if (local < table.length && table[local] != alias) {
				throw new StreamError.PROTOCOL(
					"wire name token %u alias mismatch",
					assigned_id
				);
			}
			if (local == table.length) {
				if (server) {
					this.server_names += alias;
				} else {
					this.client_names += alias;
				}
			}
			this.name_to_token.set(alias, (uint16) assigned_id);
```

---

### 8. `libocrpc/Client.vala` — client role

**Why:** This end allocates even tokens.

**Where:** `connect`, `bin = new Bin.Stream(...)`.

**Depends on:** §1.

#### Keep
```vala
			this.input = new GLib.DataInputStream(this.socket.get_input_stream());
			this.output = new GLib.DataOutputStream(this.socket.get_output_stream());
```

#### Remove
```vala
			this.bin = new Bin.Stream(this.input, this.output);
```

#### Replace with
```vala
			this.bin = new Bin.Stream(this.input, this.output) {
				is_server = false
			};
```

---

### 9. `libocrpc/Transport/Connection.vala` — server role

**Why:** Daemon end allocates odd tokens.

**Where:** connection setup, `bin = new Bin.Stream(...)`.

**Depends on:** §1.

#### Keep
```vala
				var out_stream = new GLib.DataOutputStream(
					this.stream.get_output_stream()
				);
```

#### Remove
```vala
				this.bin = new Bin.Stream(in_stream, out_stream);
```

#### Replace with
```vala
				this.bin = new Bin.Stream(in_stream, out_stream) {
					is_server = true
				};
```

---

### 10. `docs/bin-rpc-protocol.md` — even/odd + two tables

**Why:** Document the wire contract.

**Where:** §1 after the wire-names bullet.

**Depends on:** §1–§9.

#### Add — after the sentence that says tokens are learned via `TOKEN_REG_KEY`

Per connection: `client_names` / `server_names`; wire token **even = client**, **odd = server** (`local * 2` / `local * 2 + 1`). Type alias strings use the same tables; `Bin.register` stays process-local string→GType.

---

## Next

✔️ Applied §1–§10 (two arrays + even/odd; `Client` / `Transport.Connection` / `StdioConnection` `is_server`; protocol doc).

ℹ️ `is_server` is a construct property; Vala brace init was read-only — pass via `Stream(..., is_server)` ctor arg instead. `StdioConnection` also set (daemon stdio path; same role as `Transport.Connection`).

✔️ `tests/test-rpc-bin` exits 0.

⏳ Rebuild matching client + `ollmfilesd`; re-test activate + overlapping client write vs `scan_start`.

⏳ User ✅ when duplex no longer aborts on wire name intro race.
