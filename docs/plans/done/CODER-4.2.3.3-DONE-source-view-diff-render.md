# 4.2.3.3 — SourceView diff Phase 2: inline render

**Status:** **DONE** ✅ — `show_diff` / `clear_diff` + smoke in tree

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`../CODER-4.2.3-URGENT-source-view-diff.md`](../CODER-4.2.3-URGENT-source-view-diff.md)

**Depends on:** [`CODER-4.2.3.2-DONE-source-view-diff-db.md`](CODER-4.2.3.2-DONE-source-view-diff-db.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans; proposed Vala follows **`docs/coding-standards.md`**

**Next:** Phase 3 wire [`CODER-4.2.3.4-DONE-source-view-diff-view.md`](CODER-4.2.3.4-DONE-source-view-diff-view.md) ✅

---

## Purpose

- 🔷 **`SourceView.show_diff(Differ differ)`** — render from a caller-owned **`OLLMfiles.Diff.Differ`** (SourceView does **not** construct Differ).
- 🔷 Caller (Phase **3**) builds `new Differ(V_backup, V_disk)`, then passes it in.
- 🔷 Use **`differ.patches`** + public **`differ.lines1` / `differ.lines2`** — no second `split("\n")` in SourceView.
- 🔷 **`SourceView.clear_diff()`** — restore prior buffer; turn off diff chrome.
- 🔷 Whole chunk treated as pending (no `file_diff_part` overlay filtering).
- 🔷 No Approvals / pending-file wiring (Phase **3**).
- 🔷 No per-hunk approve controls (Phase **4**).
- 🔷 **Smoke window** — `examples/oc-test-source-diff.vala` (**`TestAppBase`**) takes **two files**; fixtures in **`tests/source-diff/`**.

### Phase 2 requirements (must all land)

- 🔷 **Inline unified buffer** — one `SourceView`; interleaved equal / removed / added rows (not a second pane).
- 🔷 **Green** on **added** lines — full-line background via **`Gtk.TextTag`** (`paragraph-background-rgba`).
- 🔷 **Red** on **removed** lines — same, plus **`editable=false`** on that tag (still selectable / **copyable**).
- 🔷 **Per-`SourceView` `diff_tag_table`** — create **`diff-add`** / **`diff-remove`** once per view; that view’s diff buffers reuse the table.
- 🔷 **Equal** lines — no tint; remain editable.
- 🔷 **Secondary gutter** — baseline (**V_backup**) 1-based line numbers (blank on added lines, `baseline == 0`).
- 🔷 **Hide default line numbers in diff mode** — `show_line_numbers = false` in `show_diff`; restore `true` in `clear_diff`.
- 🔷 **`show_line_marks`** already true on the view — keep it; colour comes from **tags**, not mark attributes.
- 🔷 Existing **`.source-view`** monospace CSS stays; green/red are **tags**, not new CSS colour rules.

### How colour + lock work

- 🔷 **One `Gtk.TextTagTable` per `SourceView`** (`diff_tag_table` instance field) — tags created **once** for that view, not on every `show_diff`.
- 🔷 Named tags on that table (generic types):
  - **`diff-add`** — `paragraph-background-rgba` = light green
  - **`diff-remove`** — `paragraph-background-rgba` = light red, **`editable=false`**
- 🔷 Each `show_diff` builds `new GtkSource.Buffer(this.diff_tag_table)` and **`lookup`**s the tags — never `create_tag` again.
- 🔷 For each display line: apply the matching tag from line start through end-of-line (include the newline when present so the tint fills the row).
- 🔷 **Do not** rely on `MarkAttributes.background` for the green/red fill (tags are the contract).
- 🔷 Copy/paste-out of removed text must work; typing into a removed span must not.
- ℹ️ **No CSS** for the tint — GTK does not style `Gtk.TextTag` `paragraph-background` from stylesheets; tag properties are set in code.
- ℹ️ **No GtkSource StyleScheme** `diff:added-line` / `diff:removed-line` — those are **foreground** styles for the `diff` language file, not full-row review fills.

---

## Named methods / fields (approved)

- 🔷 **`show_diff(OLLMfiles.Diff.Differ differ)`**
- 🔷 **`clear_diff()`**
- 🔷 Fields: **`diff_buffer`**, **`pre_diff_buffer`**, **`diff_baseline`**, **`baseline_gutter`**, **`diff_active`**, **`diff_tag_table`** (per view)
- 🔷 **`Differ.lines1`** / **`Differ.lines2`** — make existing private fields **public** (`get; private set;`)
- 🔷 Smoke binary **`oc-test-source-diff`** — **`TestAppBase`** + two positional files (`examples/oc-test-source-diff.vala` + `examples/meson.build`)
- 🔷 Fixtures under **`tests/source-diff/`** (hello walkthrough + insert-only + delete-only pairs)

---

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 0. `libocfiles/Diff/Differ.vala` — public `lines1` / `lines2`

**Where:** private fields at top of `Differ` (~lines 60–61).

#### Remove

```vala
		private string[] lines1;
		private string[] lines2;
```

#### Replace with

```vala
		public string[] lines1 { get; private set; }
		public string[] lines2 { get; private set; }
```

ℹ️ Constructor / `diff_update1` / `diff_update2` already assign `this.lines1` / `this.lines2` — keep those assigns.

---

### 1. `liboccoder/SourceView.vala` — fields

**Where:** after `private Approvals? approvals = null;` (~line 47).

#### Add

```vala
		private Gtk.TextTagTable? diff_tag_table = null;
		private GtkSource.Buffer? diff_buffer = null;
		private GtkSource.Buffer? pre_diff_buffer = null;
		private Gee.ArrayList<int> diff_baseline = new Gee.ArrayList<int>();
		private GtkSource.GutterRendererText? baseline_gutter = null;
		private bool diff_active = false;
```

---

### 2. `liboccoder/SourceView.vala` — baseline gutter in ctor

**Where:** after `this.source_view.add_css_class("source-view");` (~line 204). (`show_line_numbers = true` already set on the view above this.)

#### Add

```vala
			this.baseline_gutter = new GtkSource.GutterRendererText();
			this.baseline_gutter.xalign = 1.0f;
			this.baseline_gutter.xpad = 4;
			this.baseline_gutter.query_data.connect((lines, line) => {
				if (!this.diff_active || (int) line >= this.diff_baseline.size
					|| this.diff_baseline.get((int) line) <= 0) {
					this.baseline_gutter.set_text("", -1);
					return;
				}
				this.baseline_gutter.set_text(this.diff_baseline.get((int) line).to_string(), -1);
			});
			this.source_view.get_gutter(Gtk.TextWindowType.LEFT).insert(this.baseline_gutter, -40);
```

---

### 3. `liboccoder/SourceView.vala` — `show_diff` + `clear_diff`

**Where:** after `open_file` method (or end of class before closing brace).

#### Add — new methods on `SourceView`

```vala
		/**
		 * Show inline unified diff from a caller-owned {@link OLLMfiles.Diff.Differ}.
		 *
		 * Builds interleaved equal / removed / added rows. Green and red come from
		 * buffer tags; removed lines are non-editable but selectable/copyable.
		 * Secondary gutter shows baseline line numbers. Does not write disk.
		 * Caller restores with {@link clear_diff}.
		 *
		 * @param differ already constructed (text1 = V_backup, text2 = V_disk)
		 */
		public void show_diff(OLLMfiles.Diff.Differ differ)
		{
			if (this.diff_active) {
				this.clear_diff();
			}
			differ.diff();
			var display = new Gee.ArrayList<string>();
			var kinds = new Gee.ArrayList<int>();
			this.diff_baseline.clear();
			var old_i = 1, new_i = 1;
			foreach (var patch in differ.patches) {
				while (old_i < patch.old_line_start && new_i < patch.new_line_start
					&& old_i <= differ.lines1.length && new_i <= differ.lines2.length) {
					display.add(differ.lines2[new_i - 1]);
					this.diff_baseline.add(old_i);
					kinds.add(0);
					old_i++;
					new_i++;
				}
				if (patch.old_line_start > patch.old_line_end) {
					old_i = patch.old_line_start;
				} else {
					for (var ln = patch.old_line_start; ln <= patch.old_line_end; ln++) {
						display.add(differ.lines1[ln - 1]);
						this.diff_baseline.add(ln);
						kinds.add(2);
					}
					old_i = patch.old_line_end + 1;
				}
				if (patch.new_line_start > patch.new_line_end) {
					new_i = patch.new_line_start;
					continue;
				}
				for (var ln = patch.new_line_start; ln <= patch.new_line_end; ln++) {
					display.add(differ.lines2[ln - 1]);
					this.diff_baseline.add(0);
					kinds.add(1);
				}
				new_i = patch.new_line_end + 1;
			}
			while (old_i <= differ.lines1.length && new_i <= differ.lines2.length) {
				display.add(differ.lines2[new_i - 1]);
				this.diff_baseline.add(old_i);
				kinds.add(0);
				old_i++;
				new_i++;
			}
			var table = this.diff_tag_table;
			if (table == null) {
				table = new Gtk.TextTagTable();
				var add = new Gtk.TextTag("diff-add");
				add.paragraph_background_rgba = Gdk.RGBA() {
					red = 0.75f,
					green = 0.95f,
					blue = 0.75f,
					alpha = 1.0f
				};
				table.add(add);
				var remove = new Gtk.TextTag("diff-remove");
				remove.paragraph_background_rgba = Gdk.RGBA() {
					red = 0.95f,
					green = 0.75f,
					blue = 0.75f,
					alpha = 1.0f
				};
				remove.editable = false;
				table.add(remove);
				this.diff_tag_table = table;
			}
			this.diff_buffer = new GtkSource.Buffer(table);
			this.diff_buffer.set_text(string.joinv("\n", display.to_array()), -1);
			var add_tag = table.lookup("diff-add");
			var remove_tag = table.lookup("diff-remove");
			for (var i = 0; i < kinds.size; i++) {
				if (kinds.get(i) == 0) {
					continue;
				}
				Gtk.TextIter iter;
				this.diff_buffer.get_iter_at_line(out iter, i);
				Gtk.TextIter line_end = iter;
				if (!line_end.ends_line()) {
					line_end.forward_to_line_end();
				}
				if (!line_end.is_end()) {
					line_end.forward_char();
				}
				this.diff_buffer.apply_tag(kinds.get(i) == 1 ? add_tag : remove_tag, iter, line_end);
			}
			this.pre_diff_buffer = this.source_view.buffer as GtkSource.Buffer;
			this.source_view.set_buffer(this.diff_buffer);
			this.source_view.show_line_numbers = false;
			this.diff_active = true;
			this.scrolled_window.visible = true;
		}

		/**
		 * Leave diff mode and restore the previous buffer.
		 */
		public void clear_diff()
		{
			if (!this.diff_active) {
				return;
			}
			if (this.pre_diff_buffer != null) {
				this.source_view.set_buffer(this.pre_diff_buffer);
			}
			this.diff_buffer = null;
			this.pre_diff_buffer = null;
			this.diff_baseline.clear();
			this.source_view.show_line_numbers = true;
			this.diff_active = false;
		}
```

---

### 4. `examples/oc-test-source-diff.vala` — **Add** (smoke window)

**Why:** Phase 2 ends with a **`TestAppBase`** GTK app that diffs **two files** via real **`SourceView.show_diff`** — no Approvals / daemon / Phase 3. Same app flow as `oc-test-gtkmd` / other examples (not a one-off `Gtk.Application`).

#### Add — new file

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * Smoke: {@link TestAppBase} window showing {@link OLLMcoder.SourceView} inline diff.
 *
 * Usage: oc-test-source-diff <baseline_file> <current_file>
 * text1 = baseline (V_backup), text2 = current (V_disk).
 */
class TestSourceDiff : TestAppBase
{
	private Gtk.Window window;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <baseline_file> <current_file>

Opens a window with SourceView.show_diff of the two files.

Arguments:
  baseline_file              Old / backup text (Differ text1)
  current_file               New / disk text (Differ text2)

Examples:
  {ARG} old.vala new.vala
"""; }

	public TestSourceDiff()
	{
		base("com.roojs.ollmchat.test-source-diff");
	}

	protected override string get_app_name()
	{
		return "oc-test-source-diff";
	}

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var base_opts = new OptionEntry[3];
		base_opts[0] = base_options[0];
		base_opts[1] = base_options[1];
		base_opts[2] = { null };
		opt_context.add_main_entries(base_opts, null);
		return opt_context;
	}

	protected override string? validate_args(string[] args)
	{
		if (args.length < 3 || args[1] == "" || args[2] == "") {
			return "ERROR: Two files required.\nUsage: %s <baseline_file> <current_file>\n".printf(args[0]);
		}
		return null;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}
		var baseline_path = GLib.Path.is_absolute(args[1])
			? args[1]
			: GLib.Path.build_filename(GLib.Environment.get_current_dir(), args[1]);
		var current_path = GLib.Path.is_absolute(args[2])
			? args[2]
			: GLib.Path.build_filename(GLib.Environment.get_current_dir(), args[2]);
		var baseline = "";
		var current = "";
		GLib.FileUtils.get_contents(baseline_path, out baseline);
		GLib.FileUtils.get_contents(current_path, out current);
		this.window = new Gtk.Window() {
			title = "%s → %s".printf(
				GLib.Path.get_basename(baseline_path),
				GLib.Path.get_basename(current_path)),
			default_width = 720,
			default_height = 480
		};
		var source_view = new OLLMcoder.SourceView(new OLLMfiles.ProjectManager());
		source_view.show_diff(new OLLMfiles.Diff.Differ(baseline, current));
		this.window.set_child(source_view);
		var loop = new GLib.MainLoop();
		this.window.close_request.connect(() => {
			loop.quit();
			return false;
		});
		this.window.present();
		loop.run();
	}

	public static int main(string[] args)
	{
		return new TestSourceDiff().run(args);
	}
}
```

---

### 5. `examples/meson.build` — register `oc-test-source-diff`

**Where:** near other GTK / occoder **`TestAppBase`** examples (e.g. after `oc-test-gtkmd`).

#### Add

```meson
# Smoke: SourceView.show_diff of two files (Phase 2) — TestAppBase flow
test_source_diff = executable('oc-test-source-diff',
  dependencies: [test_window_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ollamaweb_vapi_dep],
  sources: ['TestAppBase.vala', 'oc-test-source-diff.vala'],
  link_with: [ollmchat_base_lib, occoder_base_lib],
  include_directories: [
    include_directories('../libocfiles'),
    include_directories('../libollmchat'),
    include_directories('../liboccoder'),
    ollmchat_consumer_include
  ],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=gmodule-2.0',
    '--pkg=tree-sitter',
    '--pkg=ocfiles',
    '--pkg=ollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'liboccoder',
    '--vapidir', meson.current_source_dir() / '../vapi',
  ] + ollmchat_consumer_vala_args,
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)
```

ℹ️ Match `oc-test-files` / `oc-test-gtkmd` deps if the first build complains — do not invent a third app style.

---

### 6. `tests/source-diff/` — smoke fixtures

**Why:** Stable two-file pairs for `oc-test-source-diff` (and eyeballing). Hello pair matches [`CODER-4.2.3.1`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md) Step 1.

ℹ️ Files are already in the tree (Add below is the contract if missing).

#### Add — `tests/source-diff/hello-baseline.txt`

```
Hello World One
Legacy Line Two
Hello World Three
Legacy Line Four
Hello World Five
Hello World Six
Hello World Seven
```

#### Add — `tests/source-diff/hello-current.txt`

```
Hello World One
Hello World Two
Hello World Three
Hello World Four
Hello World Five
Hello World Six
Hello World Seven
```

#### Add — `tests/source-diff/insert-only-baseline.txt`

```
alpha
gamma
```

#### Add — `tests/source-diff/insert-only-current.txt`

```
alpha
beta
gamma
```

#### Add — `tests/source-diff/delete-only-baseline.txt`

```
alpha
beta
gamma
```

#### Add — `tests/source-diff/delete-only-current.txt`

```
alpha
gamma
```

---

## Manual check (smoke)

- 🔷 ⏳ Green add / red remove fill the row; removed text cannot be typed over; Ctrl+C from a removed line works.
- 🔷 ⏳ Baseline gutter matches baseline file on equal/remove rows; blank on adds.
- 🔷 ⏳ Hello pair shows interleaved replace hunks on lines 2 and 4 (walkthrough Step 1 shape).

---

## Example commands

From repo root (after Phase 2 lands):

```bash
ninja -C build examples/oc-test-source-diff

./build/examples/oc-test-source-diff \
  tests/source-diff/hello-baseline.txt \
  tests/source-diff/hello-current.txt

./build/examples/oc-test-source-diff \
  tests/source-diff/insert-only-baseline.txt \
  tests/source-diff/insert-only-current.txt

./build/examples/oc-test-source-diff \
  tests/source-diff/delete-only-baseline.txt \
  tests/source-diff/delete-only-current.txt
```

---

## LLM notes

- 🚫 Wire to Approvals / `backup_path` (Phase **3**).
- 🚫 Per-hunk approve / reject UI (Phase **4**).
- 🚫 Filter overlays by `file_diff_part` (Phase **4**).
- 🚫 New helpers beyond **`show_diff`** / **`clear_diff`**.
- 🚫 Construct **`Differ`** inside SourceView — caller owns it (smoke builds Differ outside).
- 🚫 Add **`Diff.Line`** / **`LineKind`** — use public **`lines1`/`lines2`** + **`patches`**.
- 🚫 Re-`split("\n")` in SourceView — use **`differ.lines1`/`lines2`**.
- 🚫 Use **`MarkAttributes.background`** as the green/red mechanism — **tags** are the contract.
- 🚫 Create a new tag **per line** or **per `show_diff`** — one **`diff_tag_table`** per `SourceView`; **`lookup`** after first init.
- 🚫 Manual `for` copy of `ArrayList` → `string[]` — use **`display.to_array()`** with **`string.joinv`**.
- 🚫 One `var` per line for paired counters — use **`var old_i = 1, new_i = 1`**.
- 🚫 Put approval / `file_history` awareness in **`OLLMfiles.Diff`**.
- 🚫 Set whole **`source_view.editable = false`** — only removed lines via tag.
- 🚫 Disable selection on removed lines — copy / paste-out must work.
- 🚫 Trivial aliases — inline; use **`differ.patches`** after **`differ.diff()`**.
- 🚫 Hardcoded hello strings / one-off `Gtk.Application` smoke — use **`TestAppBase`** + two file args + **`tests/source-diff/`** fixtures.
- 🚫 Add CSS colour rules for green/red — tags set `paragraph-background-rgba` in code.
- 🚫 Use StyleScheme `diff:added-line` / `diff:removed-line` for the review fill — wrong mechanism (foreground for `.diff` language).
- 🚫 Shrink Purpose / requirements to a short summary — the checklist above is the contract.
