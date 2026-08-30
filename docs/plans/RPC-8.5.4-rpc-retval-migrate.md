# 8.5.4 — migrate `result` onto `retval`, then drop `result`

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

> Split from [`RPC-8.5.3-rpc-response-value.md`](RPC-8.5.3-rpc-response-value.md) Phase 3. Codec + `retval` property are that file. This cut moves every `result` writer and reader, then deletes `result`.

**Status:** **⏳** **proposed**

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`RPC-8.5.3-rpc-response-value.md`](RPC-8.5.3-rpc-response-value.md)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** `⏳` Every method that writes `Response.result` writes `retval` instead. Both ends change in the same cut. No dual-write.
- **🔷** `✔️` Pack with `OLLMrpc.val` — same D-Bus letters as `OLLMrpc.args`, **one** complete type, varargs after. Assign in the `Response` initializer: `retval = OLLMrpc.val("o", row)`.
- **🔷** `✔️` One letter switch: private `to_value(tag, l)`. `val(...)` and `args()` both call it.
- **🔷** `⏳` After the last caller, delete `result` (property, `bin_write_prop` / `bin_read_prop` cases, class examples, protocol).
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

## Phase 1 — `val()` then FFI / HTTP / tests ⏳

- **🔷** `✔️` `OLLMrpc.val` next to `args`. `tests/rpc/values-test.vala` smokes `val("i" / "o" / empty list)`.
- **🔷** `⏳` Then `Gi` / HTTP / tests use `val` on `retval`.

### 1. `libocrpc/namespace.vala` — `val()` next to `args()`

**Status:** **✔️** see `libocrpc/namespace.vala`. Private `to_value` holds the switch. `val(...)` and `args()` call it.

**Why:** `GLib.Value` cannot be built in a Vala object initializer.

**Where:** already in tree.

**Depends on:** none.

**ℹ️** Empty `Gee.ArrayList` → `INVALID` only on `val(string, ...)`. Namespace functions cannot both be named `val`.

---

### 2. `libocrpc/Gi.vala` — `dispatch_new`: one object on `retval`

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
			var response = new Response();
			response.retval = OLLMrpc.val("o", created);
			this.request.reply(response);
```

### 3. `libocrpc/Gi.vala` — method `INTERFACE` return: one object on `retval`

**Why:** Same packing as `dispatch_new`.

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

### 4. `libocrpc/Gi.vala` — `GList` / `GSList` / `GHASH`: always `ArrayList` on `retval`

**Why:** List-shaped GIR returns stay lists when there is one element. Empty → `val("o", list)` is `INVALID`.

**Where:** the three loops that `response.result.add(obj)`. Build a local list, then one `set_object`. Same packing in all three.

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

### 5. `libocrpc/Client.vala` — HTTP JSON: one object on `retval`

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

### 6. `tests/rpc/gi-test.vala` — read `retval`

**Why:** `Gio-Menu.new` / `new_for_path` / `actors` asserted `result.size` / `get(0)`.

**Where:** each `response.result` assert. Test `hello` that `result.add(actor)` becomes one-object `retval` (that handler is a one-object return).

**Depends on:** **### 2**, **### 4**.

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

**ℹ️** Same object check for `new_for_path`. `actors` is a GIR list: `retval.type().is_a(typeof(Gee.ArrayList))`, then `((Gee.ArrayList<GLib.Object>) response.retval.get_object()).get(0)`.

---

## Phase 2 — ollmfilesd + libocfiles ⏳

- **🔷** `⏳` Daemon writers and matching `libocfiles` / tool readers in one pass per method.

### 7. `ollmfilesd/Daemon.vala` — `hello()`: one object

**Why:** Template for every one-row `result.add` + `result = result` reply.

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

### 8. `ollmfilesd/File.vala` — `read()`: one object (keeps `msg`)

**Why:** One-row + `msg` / `msg_encode`. Same packing as **### 6** with extra fields.

**Where:** success `request.reply` after `result.add(row)`.

**Depends on:** **### 1**, **### 7**.

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

**ℹ️** Same one-object packing (drop the throwaway `ArrayList`) at:

- `ollmfilesd/File.vala` — `fetch`, `register`
- `ollmfilesd/Folder.vala` — `fetch`
- `ollmfilesd/FileHistory.vala` — revert / approve replies that `result.add(row)`
- `ollmfilesd/ProjectManager.vala` — `rpc_create_project`

### 9. `libocfiles/File.vala` — `read()`: one object from `retval`

**Why:** Reader for **### 7**. `INVALID` means no row (today `size == 0`).

**Where:** after `rpc.call` in `read()`.

**Depends on:** **### 8**.

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

**ℹ️** Same `INVALID` / `get_object()` shape at:

- `libocfiles/File.vala` — `register`
- `libocfiles/Folder.vala` — `fetch_file` (`RPC-File.fetch`)
- `libocfiles/ProjectManager.vala` — `fetch_folder`, `rpc_create_project`
- `libocfiles/FileHistory.vala` — `rpc_revert`

### 9. `ollmfilesd/Folder.vala` — `fetch_files_reply()`: list on `retval`

**Why:** Template for list methods. Empty page still sends `msg` (total). Omit `retval` when `list.size == 0`.

**Where:** both success `request.reply` calls in `fetch_files_reply()` (path-filter arm and paged arm).

**Depends on:** 8.5.3 `retval`.

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
			if (list.size == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = matched.size.to_string()
				});
				return;
			}
			var retval = GLib.Value(typeof(Gee.ArrayList));
			retval.set_object(list);
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = retval,
				msg = matched.size.to_string()
			});
```

**ℹ️** Path-filter arm: same `list.size == 0` skip, `msg = list.size.to_string()`. Same list packing at:

- `ollmfilesd/Folder.vala` — `fetch_pending_approvals` (`result` + `msg` marker)
- `ollmfilesd/ProjectManager.vala` — `rpc_load_projects_from_db`
- `ollmfilesd/Codebase.vala` — `file_info` (`result = list`)

### 10. `libocfiles/ProjectFiles.vala` — list from `retval`

**Why:** Reader for `fetch_files`. `INVALID` → empty foreach (no items).

**Where:** `refresh` / `load_more` after `response.msg` total.

**Depends on:** **### 9**.

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

**ℹ️** `load_more` already returns when `files.size == 0`. `INVALID` is that case. Same list unpack at:

- `libocfiles/Folder.vala` — `fetch_files`
- `libocfiles/ProjectManager.vala` — `rpc_load_projects_from_db` (`foreach` on the list; skip if `INVALID`)
- `libocfiles/ReviewFiles.vala` — `fetch_pending`: `INVALID` → `return new Gee.ArrayList<FileWithHistory>();` else cast `get_object()`
- `liboctools/ReadFile/Summarize.vala` — `RPC-Codebase.file_info`
- `examples/oc-vector-index.vala` — folder list
- `examples/oc-vector-search.vala` — metadata list

---

## Phase 3 — HF / examples (one wrapper object) ⏳

- **🔷** `⏳` `result[0]` becomes `retval.get_object()`. HTTP writer is **### 4**.

### 11. `liboctools/HuggingFace/Request.vala` — `result[0]` → `get_object()`

**Why:** Search/detail return one `Model` / `ModelArray`.

**Where:** each `detail_resp.result[0]` / `search_resp.result[0]` / `.size == 0`.

**Depends on:** **### 4**.

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

**ℹ️** Same `INVALID` / `get_object()` at the other `result[0]` sites in this file, `libochf/Model.vala`, `libochf/namespace.vala` examples, `examples/oc-hf.vala`.

---

## Phase 4 — delete `result` ⏳

- **🔷** `⏳` When grep for `response.result` / `.result.add` / `result = result` on `OLLMrpc.Response` is empty, remove the property.

### 12. `libocrpc/Response.vala` — drop `result`

**Why:** `retval` is the only object/list return.

**Where:** property; class doc **Object result** sample; `bin_write_prop` / `bin_read_prop` `case "result":`.

**Depends on:** Phases 1–3.

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
- **🚫** `[Deprecated]` soak on `result` — delete after the last caller.
- **🚫** Fold `msg` / `args` into `retval` here.
- **🚫** Apply 8.5.3 Phase 4 (spec that keeps `result`). This plan’s **### 13** is the spec.
