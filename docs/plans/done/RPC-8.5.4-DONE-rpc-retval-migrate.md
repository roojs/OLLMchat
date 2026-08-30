# 8.5.4 — migrate `result` onto `retval`, then drop `result`

> Landed. Index: [`RPC-1.0-summary.md`](../RPC-1.0-summary.md).

> Split from [`RPC-8.5.3-DONE-rpc-response-value.md`](RPC-8.5.3-DONE-rpc-response-value.md) Phase 3. Codec + `retval` property are that file. This cut moves every `result` writer and reader, then deletes `result`.

**Status:** **✅** **done**

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`RPC-8.5.3-DONE-rpc-response-value.md`](RPC-8.5.3-DONE-rpc-response-value.md)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** `✅` Every method that writes `Response.result` writes `retval` instead. Both ends change in the same cut. No dual-write.
- **🔷** `✅` Apply order: writer, then that method’s reader, then the next method. Do not convert all daemon replies and only later fix `libocfiles`.
- **🔷** `✅` Pack with `OLLMrpc.val` — same D-Bus letters as `OLLMrpc.args`, **one** complete type, varargs after. Assign in the `Response` initializer: `retval = OLLMrpc.val("o", row)`.
- **🔷** `✅` Writers that construct a Response set `retval` in that initializer. Do not `new Response()` then assign. Gi method dispatch already has a Response for OUT args — assign `retval` there.
- **🔷** `✅` One letter switch: private `to_value(tag, l)`. `val(...)` and `args()` both call it.
- **🔷** `✅` After the last caller, delete `result` (property, `bin_write_prop` / `bin_read_prop` cases, class examples, protocol).
- **🔷** Packing is by **method shape**, not by runtime count:
  - one GObject → `OLLMrpc.val("o", obj)` (Value GType is `obj.get_type()`, not `typeof(GLib.Object)`)
  - list → `OLLMrpc.val("o", list)` even when `size == 1` (`get_type()` is `Gee.ArrayList`)
  - empty list → `val("o", list)` returns unset (`INVALID`). Writer always assigns; omit on the wire is free
- **ℹ️** `args` / `msg` / `msg_encode` stay. Scalar `msg` methods are not this plan.
- **ℹ️** Same letters as `args()` (`s`, `i`, `o`, …). `val("is", …)` is fatal — that is `args`, not `val`.

---

## Today

- **ℹ️** Writers: one-element `Gee.ArrayList`, then `result = list`. Readers: `(Gee.ArrayList<T>) response.result` then `get(0)` for a single row.
- **ℹ️** `Gi` / HTTP client: `response.result.add(obj)`.
- **ℹ️** HF / examples: `resp.result[0]` for a one-element wrapper object.

---

## Phase 1 — `val()` then Gi / HTTP, each with its reader ✅

- **🔷** `✅` `OLLMrpc.val` next to `args`. `tests/rpc/values-test.vala` smokes `val("i" / "o" / empty list)`.
- **🔷** `✅` Gi writer then `gi-test`. HTTP writer then HF readers.

### 1. `libocrpc/namespace.vala` — `val()` next to `args()`

**Status:** **✅** see `libocrpc/namespace.vala`. Private `to_value` holds the switch. `val(...)` and `args()` call it.

**Why:** `GLib.Value` cannot be built in a Vala object initializer.

**Where:** already in tree.

**Depends on:** none.

**ℹ️** Empty `Gee.ArrayList` → `INVALID` only on `val(string, ...)`. Namespace functions cannot both be named `val`.

---

### 2. `libocrpc/Gi.vala` — `dispatch_new`: one object on `retval`

**Status:** **✅** see `libocrpc/Gi.vala`.

**Why:** `Gio-Menu.new` and friends return one GObject.

**Where:** after `export(created)`, before `this.request.reply(response)`.

**Depends on:** 8.5.3 `retval`.

#### Remove

```vala
			var created = (GLib.Object) ret.v_pointer;
			this.request.connection.export(created);
			var response = new Response();
			response.result.add(created);
			this.request.reply(response);
```

#### Replace with

```vala
			var created = (GLib.Object) ret.v_pointer;
			this.request.connection.export(created);
			this.request.reply(new Response() {
				retval = OLLMrpc.val("o", created)
			});
```

### 3. `tests/rpc/gi-test.vala` — `Gio-Menu.new` / `new_for_path` read `retval`

**Status:** **✅** see `tests/rpc/gi-test.vala`.

**Why:** Consumer for **### 2**. Do not leave Gi sending `retval` while the test still reads `result`.

**Where:** `Gio-Menu.new` asserts (same object check for `new_for_path`).

**Depends on:** **### 2**.

#### Remove (`Gio-Menu.new` asserts)

```vala
			this.check(command_line, response.result.size == 1, "new returned no object");
			this.check(command_line, rpc.proxies.size == 1, "proxy not bound");
			var lease_id = (uint64) 0;
			foreach (var id in rpc.proxies.keys) {
				this.check(command_line, id != 0, "handle is 0");
				this.check(
					command_line,
					rpc.proxies.get(id) == response.result.get(0),
					"proxy is not result"
				);
				lease_id = (uint64) id;
			}
```

#### Replace with

```vala
			this.check(command_line, response.retval.type() != GLib.Type.INVALID, "new returned no object");
			this.check(command_line, rpc.proxies.size == 1, "proxy not bound");
			var lease_id = (uint64) 0;
			foreach (var id in rpc.proxies.keys) {
				this.check(command_line, id != 0, "handle is 0");
				this.check(
					command_line,
					rpc.proxies.get(id) == response.retval.get_object(),
					"proxy is not retval"
				);
				lease_id = (uint64) id;
			}
```

**ℹ️** Same object check for `new_for_path`.

### 4. `libocrpc/Gi.vala` — method `INTERFACE` return: one object on `retval`

**Status:** **✅** see `libocrpc/Gi.vala`.

**Why:** Same packing as `dispatch_new`. Response already exists (OUT args after the switch). Assign `retval` on it.

**Where:** `GI.TypeTag.INTERFACE` arm that `export`s `created`.

**Depends on:** **### 1**.

#### Remove

```vala
					this.request.connection.export(created);
					response.result.add(created);
					break;
```

#### Replace with

```vala
					this.request.connection.export(created);
					response.retval = OLLMrpc.val("o", created);
					break;
```

### 5. `libocrpc/Gi.vala` — `GList` / `GSList` / `GHASH`: always `ArrayList` on `retval`

**Status:** **✅** see `libocrpc/Gi.vala`.

**Why:** List-shaped GIR returns stay lists when there is one element. Empty → `val("o", list)` is `INVALID`.

**Where:** the three loops that `response.result.add(obj)`. Build a local list, then `response.retval = OLLMrpc.val("o", list)`. Response already exists (OUT args). Same packing in all three.

**Depends on:** **### 1**.

#### Remove (`GList` loop body + return — `GSList` / `GHASH` match this shape)

```vala
			if (type.get_tag() == GI.TypeTag.GLIST) {
				for (unowned GLib.List<GLib.Object>? node = (GLib.List<GLib.Object>) arg.v_pointer;
					node != null; node = node.next) {
					var obj = node.data;
					if (Bin.gtype_to_alias != null && Bin.gtype_to_alias.has_key(obj.get_type())) {
						this.request.connection.export(obj);
						response.result.add(obj);
						continue;
					}
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				return true;
			}
```

#### Replace with

```vala
			if (type.get_tag() == GI.TypeTag.GLIST) {
				var list = new Gee.ArrayList<GLib.Object>();
				for (unowned GLib.List<GLib.Object>? node = (GLib.List<GLib.Object>) arg.v_pointer;
					node != null; node = node.next) {
					var obj = node.data;
					if (Bin.gtype_to_alias != null && Bin.gtype_to_alias.has_key(obj.get_type())) {
						this.request.connection.export(obj);
						list.add(obj);
						continue;
					}
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				response.retval = OLLMrpc.val("o", list);
				return true;
			}
```

**ℹ️** Repeat for the `GSList` loop and the `GHASH` `foreach` (local `list`, then `response.retval = OLLMrpc.val("o", list)`).

### 6. `tests/rpc/gi-test.vala` — `actors` read list `retval`

**Status:** **✅** see `tests/rpc/gi-test.vala`. Dummy `hello` uses one-object `val("o", actor)`.

**Why:** Consumer for **### 5**.

**Where:** `actors` asserts.

**Depends on:** **### 5**.

**ℹ️** `retval.type().is_a(typeof(Gee.ArrayList))`, then `((Gee.ArrayList<GLib.Object>) response.retval.get_object()).get(0)`. Test `hello` that `result.add(actor)` becomes one-object `retval`.

### 7. `libocrpc/Client.vala` — HTTP JSON: one object on `retval`

**Status:** **✅** see `libocrpc/Client.vala`.

**Why:** HF hub replies are one wrapper object today (`result.add(obj)`).

**Where:** after `var obj = read_ctx.parse();`.

**Depends on:** 8.5.3 `retval`.

#### Remove

```vala
			var obj = read_ctx.parse();
			var response = new Response() {
				id = head.request.id,
			};
			response.result.add(obj);
			this.complete_pending(head.request.id, response, null);
```

#### Replace with

```vala
			var obj = read_ctx.parse();
			var response = new Response() {
				id = head.request.id,
				retval = OLLMrpc.val("o", obj)
			};
			this.complete_pending(head.request.id, response, null);
```

### 8. `liboctools/HuggingFace/Request.vala` — `result[0]` → `get_object()`

**Status:** **✅** also `libochf/Model.vala`, `libochf/namespace.vala`, `examples/oc-hf.vala`.

**Why:** Consumer for **### 7**. Search/detail return one `Model` / `ModelArray`.

**Where:** each `detail_resp.result[0]` / `search_resp.result[0]` / `.size == 0`.

**Depends on:** **### 7**.

#### Remove

```vala
				if (detail_resp.result.size == 0) {
```

#### Replace with

```vala
				if (detail_resp.retval.type() == GLib.Type.INVALID) {
```

#### Remove

```vala
				this.download_model = (OLLMhf.Model) detail_resp.result[0];
```

#### Replace with

```vala
				this.download_model = (OLLMhf.Model) detail_resp.retval.get_object();
```

**ℹ️** Same `INVALID` / `get_object()` at the other `result[0]` sites in this file, `libochf/Model.vala`, `libochf/namespace.vala` examples, `examples/oc-hf.vala`. Apply those in this same cut, before Phase 2.

---

## Phase 2 — ollmfilesd + libocfiles, one method both ends ✅

- **🔷** `✅` For each RPC: daemon writer, then its `libocfiles` / tool reader, then the next RPC.

### 9. `ollmfilesd/Daemon.vala` — `hello()`: one object

**Status:** **✅** see `ollmfilesd/Daemon.vala`.

**Why:** Template for a one-row reply. Connect does not read `result` / `retval`.

**Where:** `hello()`, the list + `request.reply`.

**Depends on:** 8.5.3 `retval`.

#### Remove

```vala
			var result = new Gee.ArrayList<GLib.Object>();
			result.add(this);
			request.reply(new OLLMrpc.Response() {
				result = result
			});
```

#### Replace with

```vala
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", this)
			});
```

### 10. `RPC-File.read` — daemon writer, then `libocfiles` reader

**Status:** **✅** plus the one-object pass listed below.

**Why:** One-row + `msg` / `msg_encode`. Writer and reader in this section so the client never sees `result` after the daemon sends `retval`.

**Depends on:** **### 1**.

##### Part 1 — `ollmfilesd/File.vala` `read()` writer

**Where:** success `request.reply` after `result.add(row)`.

#### Remove

```vala
			var result = new Gee.ArrayList<GLib.Object>();
			result.add(row);
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				result = result,
				msg = row.is_text ? (string) data : GLib.Base64.encode(
					data[0:data.length > 0 ? data.length - 1 : 0]
				),
				msg_encode = row.is_text ? 0 : 1
			});
```

#### Replace with

```vala
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("o", row),
				msg = row.is_text ? (string) data : GLib.Base64.encode(
					data[0:data.length > 0 ? data.length - 1 : 0]
				),
				msg_encode = row.is_text ? 0 : 1
			});
```

##### Part 2 — `libocfiles/File.vala` `read()` reader

**Where:** after `rpc.call` in `read()`. `INVALID` means no row (today `size == 0`).

#### Remove

```vala
			var files = (Gee.ArrayList<File>) response.result;
			if (files.size > 0) {
				this.copy_from((File) files.get(0), {
					"manager",
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
			}
```

#### Replace with

```vala
			if (response.retval.type() != GLib.Type.INVALID) {
				this.copy_from((File) response.retval.get_object(), {
					"manager",
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
			}
```

**ℹ️** Same one-object pass (daemon writer, then its reader, before the next RPC):

- `RPC-File.fetch` — `ollmfilesd/File.vala` `fetch`, then `libocfiles/Folder.vala` `fetch_file`
- `RPC-File.register` — `ollmfilesd/File.vala` `register`, then `libocfiles/File.vala` `register`
- `RPC-Folder.fetch` — `ollmfilesd/Folder.vala` `fetch`, then `libocfiles/ProjectManager.vala` `fetch_folder`
- FileHistory revert / approve — `ollmfilesd/FileHistory.vala`, then `libocfiles/FileHistory.vala` `rpc_revert`
- `RPC-ProjectManager.rpc_create_project` — `ollmfilesd/ProjectManager.vala`, then `libocfiles/ProjectManager.vala` `rpc_create_project`

### 11. `RPC-Folder.fetch_files` — daemon writer, then `libocfiles` reader

**Status:** **✅** plus the list pass listed below.

**Why:** List template. Empty page still sends `msg` (total). `val("o", list)` is `INVALID` when empty.

**Depends on:** **### 1**.

##### Part 1 — `ollmfilesd/Folder.vala` `fetch_files_reply()` writer

**Where:** both success `request.reply` calls (path-filter arm and paged arm).

#### Remove (paged arm; path-filter arm is the same with `msg = list.size.to_string()`)

```vala
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				result = list,
				msg = matched.size.to_string()
			});
```

#### Replace with

```vala
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("o", list),
				msg = matched.size.to_string()
			});
```

##### Part 2 — `libocfiles/ProjectFiles.vala` `refresh` / `load_more` reader

**Where:** after `response.msg` total. `INVALID` → empty foreach (no items).

#### Remove

```vala
			var files = (Gee.ArrayList<File>) response.result;
			foreach (var file in files) {
```

#### Replace with

```vala
			if (response.retval.type() == GLib.Type.INVALID) {
				return;
			}
			var files = (Gee.ArrayList<File>) response.retval.get_object();
			foreach (var file in files) {
```

**ℹ️** `load_more` already returns when `files.size == 0`. `INVALID` is that case. Same list pass (writer, then reader):

- `libocfiles/Folder.vala` — `fetch_files`
- `RPC-Folder.fetch_pending_approvals` — `ollmfilesd/Folder.vala`, then `libocfiles/ReviewFiles.vala` `fetch_pending` (`INVALID` → `return new Gee.ArrayList<FileWithHistory>();`)
- `RPC-ProjectManager.rpc_load_projects_from_db` — `ollmfilesd/ProjectManager.vala`, then `libocfiles/ProjectManager.vala` (skip `foreach` if `INVALID`)
- `RPC-Codebase.file_info` — `ollmfilesd/Codebase.vala`, then `liboctools/ReadFile/Summarize.vala`
- `examples/oc-vector-index.vala` — folder list
- `examples/oc-vector-search.vala` — metadata list

---

## Phase 3 — delete `result` ✅

- **🔷** `✅` When grep for `response.result` / `.result.add` / `result = result` on `OLLMrpc.Response` is empty, remove the property.

### 12. `libocrpc/Response.vala` — drop `result`

**Status:** **✅** see `libocrpc/Response.vala`.

**Why:** `retval` is the only object/list return.

**Where:** property; class doc **Object result** sample; `bin_write_prop` / `bin_read_prop` `case "result":`.

**Depends on:** Phases 1–2.

#### Remove — property (keep `retval` that follows)

```vala
		public Gee.ArrayList<GLib.Object> result { 
			get; set; default = new Gee.ArrayList<GLib.Object>(); }
```

#### Remove — `bin_write_prop` `case "result":` through its `return;` (do not touch `case "retval":`)

#### Remove — `bin_read_prop` `case "result":` through its `return;`

#### Remove — class docblock **Object result** `{{{ }}}` sample

Update the overview sentence that names `{@link result}` so it names `{@link retval}` only.

### 13. `docs/bin-rpc-protocol.md` — §15: `retval` replaces `result` arrays

**Status:** **✅** see `docs/bin-rpc-protocol.md`.

**Why:** Spec still describes `result` as the object list. 8.5.3 Phase 4 is **not** applied; write the final text here.

**Where:** `### Root result arrays (`Response.result`)` through the See line. Also the sentence under **Positional returns** that says a returned GObject uses **`result`**.

**Depends on:** **### 12**.

#### Remove

```markdown
### Root result arrays (`Response.result`)

List **results** (`fetch_files`, …) encode as an object array on the **`result`** property of **`OLLMrpc.Response`** — not as a separate root message.

**Property type:** **`Gee.ArrayList<GLib.Object>`** — **`default = new Gee.ArrayList<GLib.Object>()`**; never null. Handlers populate **`result`** (length 0, 1, or N). Single-row RPCs use a one-element list — **🚫** no bare object on **`result`**.

**Encode:** omit **`result`** when **`result.size == 0`**. When **`size > 0`**, **`Response.bin_write_prop`** writes reg-id-first object arrays (`0xD0` + element `reg_id` + count + bodies); element **`GType`** from **`result.get(0)`**. **🚫** no **`is_array`** / **`result_type`** on handlers.

**Decode:** property present → **`Stream.parse_object_array()`**; property absent → default empty list. Clients: guard **`response.error`** only — **🚫** no **`response.result == null`**; one **`(Gee.ArrayList<T>) response.result`** cast — **🚫** no **`(Gee.ArrayList<GLib.Object>)`** hop. Single-row methods use **`list.get(0)`** when **`list.size > 0`**.

See `libocrpc/Response.vala`.
```

#### Replace with

```markdown
### Root retval (`Response.retval`)

Optional typed return on **`OLLMrpc.Response.retval`** (`GLib.Value`), encoded with **`Bin.StreamValue`**.

**Omit** when unset (`GLib.Type.INVALID`) or an empty **`Gee.ArrayList`**.

**One GObject** (method returns a single row): bare `OBJECT`. **N GObjects** (method returns a list): `typeof(Gee.ArrayList)` → object array `0xD0`, including when `size == 1`. Live-handle bodies follow `StreamValue` / `parse_object`.

**Decode:** property absent → `INVALID`. List methods treat `INVALID` as empty. One-object methods treat `INVALID` as no row.

See `libocrpc/Response.vala`, `libocrpc/Bin/StreamValue.vala`.
```

#### Remove (under **Positional returns**)

```markdown
**Omit** when **`args.size == 0`**. A returned GObject uses **`result`**, not this list.
```

#### Replace with

```markdown
**Omit** when **`args.size == 0`**. A returned GObject uses **`retval`**, not this list.
```

---

## LLM notes

- **🚫** Dual-write `result` and `retval` on one reply.
- **🚫** Wrap a one-object method in `ArrayList` “for compatibility”.
- **🚫** Pack a GIR `GList` as bare `OBJECT` when `length == 1`.
- **🚫** New pack/unpack helpers besides `val` / `args` (private `to_value` is the letter switch).
- **🚫** `GLib.Value` + `set_object` on writers — `val()` is for the object initializer.
- **🚫** `new Response()` then `response.retval = …` when the reply can be `new Response() { retval = OLLMrpc.val(…) }`.
- **🚫** `if (list.size == 0)` skip `retval` — `val("o", list)` is `INVALID`.
- **🚫** Convert all daemon writers, then all `libocfiles` readers. Writer then that method’s reader before the next RPC.
- **🚫** `[Deprecated]` soak on `result` — delete after the last caller.
- **🚫** Fold `msg` / `args` into `retval` here.
- **🚫** Apply 8.5.3 Phase 4 (spec that keeps `result`). This plan’s **### 13** is the spec.
