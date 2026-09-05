# 4.2.3.3 — SourceView diff Phase 2: inline render

**Status:** **⏳** proposed (implement after Phase 1 / review)

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md)

**Depends on:** Phase 1 optional · Phase 3 wires callers · [`CODER-4.2.3.2`](CODER-4.2.3.2-source-view-diff-db.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans; proposed Vala follows **`docs/coding-standards.md`**

---

## Purpose

- 🔷 Inline unified diff in `SourceView`: green add / red remove (non-editable, copyable) / secondary baseline gutter.
- 🔷 **`show_diff(Differ)`** / **`clear_diff()`** — caller owns Differ (Phase **3**).
- 🔷 ⏳ No Approvals wire / per-hunk UI (Phases **3** / **4**).

## Named (approved)

- 🔷 **`show_diff`**, **`clear_diff`**
- 🔷 Fields **`diff_buffer`**, **`pre_diff_buffer`**, **`diff_baseline`**, **`baseline_gutter`**, **`diff_active`**
- 🔷 **`Differ.lines1`** / **`Differ.lines2`** public get

---

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 0. `libocfiles/Diff/Differ.vala` — public line arrays

**Where:** fields at top of `Differ` (~lines 60–61).

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

---

### 1. `liboccoder/SourceView.vala` — fields

**Where:** after `private Approvals? approvals = null;` (~line 47).

#### Add — diff-mode state

```vala
		private GtkSource.Buffer? diff_buffer = null;
		private GtkSource.Buffer? pre_diff_buffer = null;
		private Gee.ArrayList<int> diff_baseline = new Gee.ArrayList<int>();
		private GtkSource.GutterRendererText? baseline_gutter = null;
		private bool diff_active = false;
```

---

### 2. `liboccoder/SourceView.vala` — baseline gutter in ctor

**Where:** after `this.source_view.add_css_class("source-view");` (~line 204). (`show_line_numbers = true` already set on the view above this.)

#### Add — secondary gutter (baseline line numbers; blank when `diff_baseline` entry is `0`)

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

#### Add — unified buffer; green/red `paragraph-background-rgba` tags; remove tag also `editable=false`; tag range includes trailing newline when present

```vala
		/**
		 * Show inline unified diff from a caller-owned {@link OLLMfiles.Diff.Differ}.
		 *
		 * @param differ text1 = V_backup, text2 = V_disk
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
			var old_i = 1;
			var new_i = 1;
			foreach (var patch in differ.patches) {
				while (old_i < patch.old_line_start && new_i < patch.new_line_start
					&& old_i <= differ.lines1.length && new_i <= differ.lines2.length) {
					display.add(differ.lines2[new_i - 1]);
					this.diff_baseline.add(old_i);
					kinds.add(0);
					old_i++;
					new_i++;
				}
				if (patch.old_line_start <= patch.old_line_end) {
					for (var ln = patch.old_line_start; ln <= patch.old_line_end; ln++) {
						display.add(differ.lines1[ln - 1]);
						this.diff_baseline.add(ln);
						kinds.add(2);
					}
					old_i = patch.old_line_end + 1;
				} else {
					old_i = patch.old_line_start;
				}
				if (patch.new_line_start <= patch.new_line_end) {
					for (var ln = patch.new_line_start; ln <= patch.new_line_end; ln++) {
						display.add(differ.lines2[ln - 1]);
						this.diff_baseline.add(0);
						kinds.add(1);
					}
					new_i = patch.new_line_end + 1;
				} else {
					new_i = patch.new_line_start;
				}
			}
			while (old_i <= differ.lines1.length && new_i <= differ.lines2.length) {
				display.add(differ.lines2[new_i - 1]);
				this.diff_baseline.add(old_i);
				kinds.add(0);
				old_i++;
				new_i++;
			}
			var joined = new string[display.size];
			for (var i = 0; i < display.size; i++) {
				joined[i] = display.get(i);
			}
			this.diff_buffer = new GtkSource.Buffer(null);
			this.diff_buffer.set_text(string.joinv("\n", joined), -1);
			var add_tag = this.diff_buffer.create_tag("diff-add",
				"paragraph-background-rgba",
				Gdk.RGBA() { red = 0.75f, green = 0.95f, blue = 0.75f, alpha = 1.0f });
			var remove_tag = this.diff_buffer.create_tag("diff-remove",
				"paragraph-background-rgba",
				Gdk.RGBA() { red = 0.95f, green = 0.75f, blue = 0.75f, alpha = 1.0f },
				"editable", false);
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
			this.diff_active = false;
		}
```

---

## LLM notes

- 🚫 Implement anything only described in Purpose bullets — apply the fences above only.
- 🚫 Wire Approvals / `backup_path` / per-hunk UI (Phases **3** / **4**).
- 🚫 Construct **`Differ`** inside SourceView.
- 🚫 **`MarkAttributes`** for green/red — tags in the fence are the colour path.
- 🚫 New helpers / **`Diff.Line`** / re-`split` / whole-view `editable = false` / trivial aliases.
