# 2.10.4.33 — Client AST lookup → file daemon

**Status:** **DONE** — lookup RPC, Summarize on daemon, client Tree dropped

> **Do not update** `docs/plans/FILES-1.0-summary.md` **for this sub-plan.**

**Parent:** [`FILES-2.10.4.0-summary.md`](FILES-2.10.4.0-summary.md)

**Split from:** [`done/2.10.4.6-DONE-file.md`](done/2.10.4.6-DONE-file.md) deferred AST-on-wire lookup. Unblocks [`RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) Phase 1.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

Named methods this plan adds: `File.ast_lookup` (client + daemon),
`File.ast_summarize` (daemon). Wire: `RPC-File.ast_lookup`,
`RPC-File.ast_summarize`. Same underscore names as the Vala methods
(not `ast.lookup` / `ast.summarize` from [`2.10.4.6`](done/2.10.4.6-DONE-file.md)).

---

## Purpose

- 🔷 Tree-sitter stays on `ollmfilesd`. Thin client must not link `tree-sitter`.
- 🔷 Land `File.ast_lookup`: `path` + `ast_path` → three ints in `response.msg`
  (`start end comment_start`). Empty `msg` = not found. RPC errors throw.
- 🔷 Callers stop constructing `OLLMfiles.Tree`. Line-range math and buffer
  slices stay on the client.
- 🔷 `ReadFile` summarize walks the AST on the daemon (`File.ast_summarize`).
  Then delete client `Tree.vala` / `TreeBase.vala`.
- ℹ️ `ollmfilesd/FileChange.resolve_ast_path` already uses `tree_factory`.
  Do not change it.

---

## Current behaviour

- ℹ️ Client `FileChange`, `ReadFile.Request.resolve_ast_path`, and
  `ResolveLink` call `new OLLMfiles.Tree` / `lookup_path` locally.
- ℹ️ Daemon `Tree.parse` + `lookup_path` and `tree_factory` already exist.
- ℹ️ `RPC-File` has no `ast_lookup`. Client `File` has no lookup method.
- ℹ️ `OLLMtools.ReadFile.Summarize` subclasses client `TreeBase`.

---

## Phase 1 — `File.ast_lookup` (`✔︎`)

- 🔷 `✔︎` Register `ast_lookup` / `"ss"`. Daemon parses via `tree_factory`.
- 🔷 `✔︎` Client `File.ast_lookup` mirrors `File.read` (`rpc.call`).
- 🔷 `✔︎` Switch FileChange, ReadFile lookup, ResolveLink, `oc-test-files --read`.

### 1. `ollmfilesd/File.vala` — `rpc_register`: add `ast_lookup`

**Why:** Wire name matches the Vala method (`RPC-File.ast_lookup`).

**Where:** `add_class` method list.

**Depends on:** §2.

#### Remove

```vala
				"rpc_write", "ssssu",
				"rpc_delete", "s"
```

#### Replace with

```vala
				"rpc_write", "ssssu",
				"rpc_delete", "s",
				"ast_lookup", "ss"
```

---

### 2. `ollmfilesd/File.vala` — `ast_lookup`: parse + `lookup_path`

**Why:** Same work as daemon `FileChange.resolve_ast_path`, over RPC.

**Where:** new method immediately after `read()`.

**Depends on:** none.

#### Add — after the closing `}` of `read()`

Daemon `Tree.parse` is async, so reply inside `parse.begin` (same idea as
`rpc_write` / `write.begin`). `msg` is three decimal ints separated by
spaces. Empty `msg` means the path was not found.

```vala
		/**
		 * ''File.ast_lookup'' — line range for one AST path.
		 *
		 * @param request inbound RPC
		 * @param path indexed file path
		 * @param ast_path tree-sitter path (e.g. Class.method)
		 */
		public void ast_lookup(
			OLLMrpc.Request request,
			string path,
			string ast_path
		)
		{
			var tree = this.manager.tree_factory(
				this.manager.get_file_from_active_project(path)
			);
			tree.parse.begin((obj, res) => {
				try {
					tree.parse.end(res);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
				var start = 0;
				var end = 0;
				var comment_start = 0;
				if (!tree.lookup_path(ast_path, out start, out end, out comment_start)) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = ""
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = start.to_string() + " " + end.to_string() + " "
						+ comment_start.to_string()
				});
			});
		}
```

---

### 3. `libocfiles/File.vala` — `ast_lookup`: RPC client

**Why:** One call site for every leftover `new Tree`.

**Where:** new method immediately after `read()`.

**Depends on:** §1, §2.

#### Add — after the closing `}` of `read()`

```vala
		/**
		 * Line range for an AST path (''RPC-File.ast_lookup'').
		 *
		 * ''response.msg'' is ''start end comment_start'' (1-based lines).
		 * Empty msg means the path was not found.
		 *
		 * @param ast_path tree-sitter path
		 * @param start_line element start line
		 * @param end_line element end line
		 * @param comment_start preceding comment start, or start_line
		 * @return false when path/ast_path is empty or the AST path is missing
		 * @throws GLib.Error if the RPC fails
		 */
		public async bool ast_lookup(
			string ast_path,
			out int start_line,
			out int end_line,
			out int comment_start
		) throws GLib.Error
		{
			start_line = 0;
			end_line = 0;
			comment_start = 0;
			if (this.path.length == 0 || ast_path == "") {
				return false;
			}
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-File.ast_lookup",
				args = OLLMrpc.args("ss", this.path, ast_path)
			});
			var parts = response.msg.split(" ");
			if (parts.length != 3) {
				return false;
			}
			int.try_parse(parts[0], out start_line);
			int.try_parse(parts[1], out end_line);
			int.try_parse(parts[2], out comment_start);
			return true;
		}
```

---

### 4. `libocfiles/FileChange.vala` — `resolve_ast_path()`: RPC instead of `Tree`

**Why:** Keep BEFORE/AFTER/DELETE/REPLACE math on the client.

**Where:** `resolve_ast_path()`, the `new Tree` / `parse` / `lookup_path` try.

**Depends on:** §3.

#### Remove

```vala
			var tree = new Tree(this.file);
			
			int start, end, comment_start;
			try {
				yield tree.parse();
				if (!tree.lookup_path(this.ast_path, out start, out end, out comment_start)) {
					this.result = "AST path not found: " + this.ast_path;
					this.completed = true;
					this.has_error = true;
					return;
				}
			} catch (GLib.Error e) {
				GLib.warning("Error resolving AST path '%s': %s", this.ast_path, e.message);
				this.result = "Error resolving AST path: " + e.message;
				this.completed = true;
				this.has_error = true;
				return;
			}
```

#### Replace with

```vala
			int start, end, comment_start;
			try {
				if (!yield this.file.ast_lookup(
					this.ast_path, out start, out end, out comment_start
				)) {
					this.result = "AST path not found: " + this.ast_path;
					this.completed = true;
					this.has_error = true;
					return;
				}
			} catch (GLib.Error e) {
				GLib.warning("Error resolving AST path '%s': %s", this.ast_path, e.message);
				this.result = "Error resolving AST path: " + e.message;
				this.completed = true;
				this.has_error = true;
				return;
			}
```

---

### 5. `liboctools/ReadFile/Request.vala` — `resolve_ast_path()`: RPC

**Why:** Same line-range lookup as FileChange.

**Where:** body of `resolve_ast_path()`.

**Depends on:** §3.

#### Remove

```vala
			// Parse via V2 Tree (RPC-fed content in load_file_content)
			var tree = new OLLMfiles.Tree(this.file);
			yield tree.parse();
			
			// Lookup AST path
			int start, end, comment_start;
			if (tree.lookup_path(this.ast_path, out start, out end, out comment_start)) {
				this.start_line = comment_start;
				this.end_line = end;
				return true;
			}
			
			return false;
```

#### Replace with

```vala
			int start, end, comment_start;
			if (!yield this.file.ast_lookup(
				this.ast_path, out start, out end, out comment_start
			)) {
				return false;
			}
			this.start_line = comment_start;
			this.end_line = end;
			return true;
```

---

### 6. `liboccoder/Task/ResolveLink.vala` — preload stores range; `file_ast` reads it

**Why:** `file_ast` is sync. Lookup must happen in `preload_links`.

**Where:** field on `ResolveLink`; `range()` get/set; AST branch of `preload_links`; body of `file_ast`.

**Depends on:** §3.

#### Add — field after `project_manager`

Map key is `path + "\0" + hash`. Value is `{ start, end, comment_start }`.

```vala
	Gee.HashMap<string, Gee.ArrayList<int>> ast_range {
		get; private set;
		default = new Gee.HashMap<string, Gee.ArrayList<int>>();
	}
```

#### Add — `range()` (user-approved helper)

One method: pass three ints to store, empty list to read. Empty return means no preload hit.

```vala
	Gee.ArrayList<int> range(string path, string hash, Gee.ArrayList<int> store)
	{
		var key = path + "\0" + hash;
		if (store.size >= 3) {
			this.ast_range.set(key, store);
			return store;
		}
		if (!this.ast_range.has_key(key)) {
			return new Gee.ArrayList<int>();
		}
		return this.ast_range.get(key);
	}
```

#### Remove — `preload_links` Tree parse

```vala
			var tree = new OLLMfiles.Tree (found);
			try {
				yield tree.parse ();
			} catch (GLib.Error e) {
				GLib.debug ("tree.parse %s: %s", found.path, e.message);
			}
```

#### Replace with

```vala
			int start, end, comment_start;
			try {
				if (!yield found.ast_lookup (
					link.hash, out start, out end, out comment_start
				)) {
					continue;
				}
			} catch (GLib.Error e) {
				GLib.debug ("ast_lookup %s: %s", found.path, e.message);
				continue;
			}
			var store = new Gee.ArrayList<int>();
			store.add(start);
			store.add(end);
			store.add(comment_start);
			this.range(found.path, link.hash, store);
```

#### Remove — `file_ast` local Tree

```vala
		var tree = new OLLMfiles.Tree (found);
		int start_line, end_line, comment_start;
		tree.lookup_path (link.hash, out start_line, out end_line, out comment_start);
		string content = found.buffer.get_text (comment_start - 1, end_line - 2);
```

#### Replace with

```vala
		var range = this.range(found.path, link.hash, new Gee.ArrayList<int>());
		if (range.size < 3) {
			return "";
		}
		var content = found.buffer.get_text(range.get(2) - 1, range.get(1) - 2);
```

---

### 7. `examples/oc-test-files.vala` — `--read` AST path

**Why:** This CLI still calls `manager.tree_factory` (not on V2 client PM).

**Where:** `run_read()`, the `opt_ast_path != ""` block.

**Depends on:** §3.

#### Remove

```vala
			var tree = manager.tree_factory(file);
			yield tree.parse();
			
			int start, end, comment_start;
			if (!tree.lookup_path(opt_ast_path, out start, out end, out comment_start)) {
				stderr.printf("AST path not found: %s\n", opt_ast_path);
				return;
			}
```

#### Replace with

```vala
			int start, end, comment_start;
			if (!yield file.ast_lookup(opt_ast_path, out start, out end, out comment_start)) {
				stderr.printf("AST path not found: %s\n", opt_ast_path);
				return;
			}
```

---

## Phase 2 — Summarize on the daemon (`✔︎`)

- 🔷 `✔︎` Move `liboctools/ReadFile/Summarize.vala` → `ollmfilesd/Summarize.vala`.
  Namespace `OLLMfilesd`, base daemon `TreeBase`.
- 🔷 Wire `RPC-File.ast_summarize` / method `ast_summarize` (`"sb"` path +
  `show_lines`).
- 🔷 `✔︎` Client summarize branch and `oc-test-files --summarize` call that RPC.
  Markdown comes back in `response.msg`.

### 8. Copy Summarize onto the daemon

**Why:** The markdown walk needs `TreeBase` / `TreeSitter`. That stays daemon-side.

**Where:** new file `ollmfilesd/Summarize.vala` (copy then the hunks below).
List it in `ollmfilesd/meson.build` next to `'Tree.vala'`.

**Depends on:** none.

#### Add — `ollmfilesd/meson.build` source list, after `'Tree.vala',`

```meson
  'Summarize.vala',
```

#### Remove — class namespace / base / ctor types in the copied file

```vala
namespace OLLMtools.ReadFile
{
	/**
	 * Tree-sitter based file structure summarizer.
	 * 
	 * Parses source code files using tree-sitter to extract code elements
	 * and output a markdown summary with indentation following file structure.
	 */
	public class Summarize : OLLMfiles.TreeBase
```

```vala
		public Summarize(OLLMfiles.File file, bool show_lines = false)
```

#### Replace with

```vala
namespace OLLMfilesd
{
	/**
	 * Tree-sitter based file structure summarizer.
	 *
	 * Parses source code files using tree-sitter to extract code elements
	 * and output a markdown summary with indentation following file structure.
	 */
	public class Summarize : TreeBase
```

```vala
		public Summarize(File file, bool show_lines = false)
```

#### Remove — `load_vector_metadata` RPC

```vala
			Gee.ArrayList<OLLMfiles.SQT.VectorMetadata> rows;
			try {
				var response = yield this.file.manager.rpc.call (
					new OLLMrpc.Request () {
						method = "RPC-Codebase.file_info",
						args = OLLMrpc.args ("s", this.file.path)
					});
				if (response.retval.type() == GLib.Type.INVALID) {
					return;
				}
				rows = (Gee.ArrayList<OLLMfiles.SQT.VectorMetadata>) response.retval.get_object();
			} catch (GLib.Error e) {
				GLib.critical ("Summarize vector metadata: %s: %s",
					this.file.path, e.message);
				return;
			}
			foreach (var row in rows) {
				var ast_path = row.ast_path.strip();
				if (ast_path == "") {
					continue;
				}
				this.vectors.set(ast_path, row);
			}
```

#### Replace with — SQL `file_id` + non-empty `ast_path`

Also change the field type of `vectors` to
`Gee.HashMap<string, SQT.VectorMetadata>`. Empty paths stay out of the
map because the `WHERE` already dropped them. No Vala `strip` / `continue`.

```vala
			var rows = new Gee.ArrayList<SQT.VectorMetadata>();
			SQT.VectorMetadata.query(this.file.manager.db).select(
				"WHERE file_id = " + this.file.id.to_string()
					+ " AND ast_path != ''",
				rows
			);
			foreach (var row in rows) {
				this.vectors.set(row.ast_path, row);
			}
```

---

### 9. `ollmfilesd/File.vala` — `ast_summarize`

**Why:** Client must not construct `Summarize`.

**Where:** `rpc_register` list (add `"ast_summarize", "sb"` next to
`ast_lookup`); new method after `ast_lookup`.

**Depends on:** §8.

#### Add — `rpc_register` pair after `"ast_lookup", "ss"`

```vala
				"ast_summarize", "sb"
```

#### Add — after `ast_lookup`

`summarize.end` is the throw. Catch that, then `reply` outside the try
(same shape as `ast_lookup` / `parse.end`).

```vala
		/**
		 * ''File.ast_summarize'' — markdown AST outline.
		 *
		 * @param request inbound RPC
		 * @param path indexed file path
		 * @param show_lines true → line numbers instead of AST paths
		 */
		public void ast_summarize(
			OLLMrpc.Request request,
			string path,
			bool show_lines
		)
		{
			var summarizer = new Summarize(
				this.manager.get_file_from_active_project(path),
				show_lines
			);
			summarizer.summarize.begin((obj, res) => {
				var markdown = "";
				try {
					markdown = summarizer.summarize.end(res);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = markdown
				});
			});
		}
```

---

### 10. `liboctools/ReadFile/Request.vala` — summarize via RPC

**Why:** Drop the last `TreeBase` subclass in tools.

**Where:** `if (this.summarize)` branch.

**Depends on:** §9.

#### Remove

```vala
			if (this.summarize) {
				// Create Summarize instance (pass show_lines to control output format)
				var summarizer = new Summarize(this.file, this.show_lines);

				// Generate summary
				var summary = yield summarizer.summarize();

				// Send summary to UI
				var preview_summary = this.get_first_lines(summary, 20);
				this.agent.add_message(new OLLMchat.Message("ui", 
					OLLMchat.Message.fenced("text.oc-frame-success File Summary", preview_summary)));

				// Return full summary to LLM
				return summary;
			}
```

#### Replace with

```vala
			if (this.summarize) {
				var response = yield this.file.manager.rpc.call(new OLLMrpc.Request() {
					method = "RPC-File.ast_summarize",
					args = OLLMrpc.args("sb", this.file.path, this.show_lines)
				});
				var preview_summary = this.get_first_lines(response.msg, 20);
				this.agent.add_message(new OLLMchat.Message("ui",
					OLLMchat.Message.fenced("text.oc-frame-success File Summary", preview_summary)));
				return response.msg;
			}
```

---

### 11. `examples/oc-test-files.vala` — `run_summarize`

**Where:** replace `new OLLMtools.ReadFile.Summarize` with `File.ast_summarize`.

**Depends on:** §9.

#### Remove

```vala
		var summarizer = new OLLMtools.ReadFile.Summarize(file, opt_show_lines);
		
		// Generate summary
		var summary = yield summarizer.summarize();
		
		// Output full summary
		print(summary);
```

#### Replace with

```vala
		var response = yield file.manager.rpc.call(new OLLMrpc.Request() {
			method = "RPC-File.ast_summarize",
			args = OLLMrpc.args("sb", file.path, opt_show_lines)
		});
		print(response.msg);
```

---

### 12. Delete client Summarize + meson refs

**Where:** delete `liboctools/ReadFile/Summarize.vala`. Drop it from
`liboctools/meson.build` `octools_src` and from `docs/meson.build`
(`../liboctools/ReadFile/Summarize.vala` — point valadoc at
`../ollmfilesd/Summarize.vala` if that file is in the valadoc list).

#### Remove — `liboctools/meson.build` sources

```meson
  'ReadFile/Summarize.vala',
```

---

## Phase 3 — Drop client tree-sitter (`✔︎`)

- 🔷 `✔︎` After no client type extends `TreeBase`, delete
  `libocfiles/Tree.vala` and `libocfiles/TreeBase.vala`.

### 13. `libocfiles/meson.build` — stop linking tree-sitter

**Depends on:** Phase 1 + Phase 2.

#### Remove

```meson
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),
  dependency('sqlite3'),
  dependency('libsoup-3.0'),  # ocrpc.h includes Soup types (HttpReply)
  valac.find_library('posix'),
  tree_sitter_dep,
```

#### Replace with

```meson
  dependency('json-glib-1.0'),
  dependency('sqlite3'),
  dependency('libsoup-3.0'),  # ocrpc.h includes Soup types (HttpReply)
  valac.find_library('posix'),
```

#### Remove — vapi pkgs (`ocfiles_vapi_pkgs` and the matching
`ocfiles_vapi_gen_pkgs` `--pkg` lines)

```meson
  '--pkg=gmodule-2.0',  # GModule for dynamic library loading (required for TreeBase)
  '--pkg=tree-sitter',  # Tree-sitter via vapi (required for TreeBase)
```

#### Remove — sources

```meson
  'TreeBase.vala',
  'Tree.vala',
```

ℹ️ Same leftover `--pkg=tree-sitter` / `--pkg=gmodule-2.0` comments exist in
`liboctools/meson.build`, `liboccoder/meson.build`, `examples/meson.build`.
Delete those lines after this cut; they only existed for client `TreeBase`.

---

## Suggested order

1. ✔︎ Phase 1 — `ast_lookup` daemon + client + switch three callers
2. ✔︎ Phase 2 — move Summarize, `ast_summarize`, switch tool + CLI
3. ✔︎ Phase 3 — delete client `Tree` / `TreeBase` / meson deps
4. Then [`RPC-8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) Phase 1

---

## LLM notes

- ℹ️ Vector `Indexer` already uses `new Tree(file)` inside `ollmfilesd`. Leave it.
- ℹ️ Client `SQT.VectorMetadata.lookup_path` is SQL, not tree-sitter.
- ℹ️ `ollmfilesd/FileChange` stays on `tree_factory`.
- 🚫 Pixiewood tree-sitter wrap or language `.so` in the APK.
- 🚫 `#if ANDROID` stub `OLLMfiles.Tree`.
- 🚫 Re-adding `tree_factory` on the V2 client `ProjectManager`.
- 🚫 Folding lookup into `File.read` (optional in 2.10.4.6) — dedicated
  `ast_lookup` unless you want that fold.
