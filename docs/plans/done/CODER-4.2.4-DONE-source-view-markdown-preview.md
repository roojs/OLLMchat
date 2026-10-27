# CODER-4.2.4 Source view markdown preview

**Status:** done — core markdown preview merged to mainline; optional ideas are archived

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan** until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala code must follow `docs/coding-standards.md`.

**Related:**

- ℹ️ `CoderView` is `liboccoder/CoderView.vala` after [`CODER-4.2.6-DONE-file-nav-mainline.md`](CODER-4.2.6-DONE-file-nav-mainline.md).
- ℹ️ Unapproved changes stay on `liboccoder/Diff/ReviewBar.vala`. Chat history stays the left sidebar.

---

## Purpose

- ✔️ Phase 1 links `libocmarkdowngtk` into `liboccoder`.
- ✔️ Phase 2 is a `DocView` that `CoderView` shows in place of `SourceView`.
- ✔️ `DocView` is the interface in `liboccoder/DocView.vala`. The active viewer is a `DocView`.
- ✔️ `MarkdownView` implements `DocView` for a markdown file.
- ✔️ `MarkdownView` is in the library. `CoderView` shows it for a markdown file.
- ℹ️ A later `DocView` can render SVG, an image, or an HTML page. Not this phase.
- 🔷 Phase 3 (optional) draws diff colours in that render.
- 🔷 Phase 4 (optional) replaces a changed chunk in the render. A long-press jumps to that source line.
- 🔷 Phase 5 (optional) is Ctrl+wheel and pinch zoom on the render.

---

## Phase 1 — Link `libocmarkdowngtk` into `liboccoder`

ℹ️ `CoderView` lives in `liboccoder`. The preview class is constructed there. `build_rpath` in `liboccoder/meson.build` already lists `libocmarkdowngtk`. Android and desktop share `occoder_lib_deps` and `occoder_vala_args`. Each `library()` call has its own `include_directories`.

- ✔️ `liboccoder` can construct `MarkdownGtk.Render`.

### 1. `liboccoder/meson.build` — sources and link

**Why:** the preview class is part of `liboccoder` and constructs `MarkdownGtk.Render`.

**Where:** `occoder_src`, before `'CoderView.vala'`. `occoder_lib_deps`, after `ocmarkdown_vapi_dep`.

**Depends on:** none.

#### Add — `occoder_src`, immediately before `'CoderView.vala'`. The preview class must be listed before the screen that owns it.

```meson
  'MarkdownView.vala',
```

#### Remove

```meson
occoder_lib_deps = [occoder_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ocmarkdown_vapi_dep, ocrpc_vapi_dep]
```

#### Replace with

```meson
occoder_lib_deps = [occoder_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ocmarkdown_vapi_dep, ocmarkdowngtk_vapi_dep, ocrpc_vapi_dep]
```

### 2. `liboccoder/meson.build` — `occoder_vala_args`

**Why:** valac must see `ocmarkdowngtk` while compiling the library.

**Where:** `occoder_vala_args`. Package flag after `'--pkg=ocmarkdown'`. Vapi dir and gir dir after the `libocmarkdown` lines.

**Depends on:** §1.

#### Remove

```meson
  '--pkg=ocmarkdown',
  '--pkg=ocrpc',
```

#### Replace with

```meson
  '--pkg=ocmarkdown',
  '--pkg=ocmarkdowngtk',
  '--pkg=ocrpc',
```

#### Remove

```meson
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
```

#### Replace with

```meson
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
```

#### Remove

```meson
  '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
```

#### Replace with

```meson
  '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--girdir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
```

### 3. `liboccoder/meson.build` — C header include

**Why:** generated C includes `ocmarkdowngtk.h`.

**Where:** `include_directories:` inside both `library()` calls. The android block and the desktop block use the same three lines.

**Depends on:** §1.

#### Remove

```meson
      include_directories('..' / 'libocfiles')     # For C headers (build directory)
```

#### Replace with

```meson
      include_directories('..' / 'libocfiles'),     # For C headers (build directory)
      include_directories('..' / 'libocmarkdowngtk')
```

### 4. `liboccoder/meson.build` — hand-written vapi

**Why:** the `occoder.vapi` custom target compiles the same sources.

**Where:** `occoder_vapi_gen_pkgs` after `'--pkg', 'ocmarkdown'`. `occoder_vapi_vapidirs` after the `libocmarkdown` line. `occoder_vapi_depends` after `ocmarkdown_vapi`.

**Depends on:** §2.

#### Remove

```meson
  '--pkg', 'ocmarkdown',
  '--pkg', 'gtk4',
```

#### Replace with

```meson
  '--pkg', 'ocmarkdown',
  '--pkg', 'ocmarkdowngtk',
  '--pkg', 'gtk4',
```

#### Remove

```meson
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir(),
```

#### Replace with

```meson
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  '--vapidir', meson.current_build_dir(),
```

#### Remove

```meson
occoder_vapi_depends = [occoder_base_lib, ocfiles_vapi, ollmchat_base_lib, ollamaweb_vapi, ocmarkdown_vapi, ocrpc_vapi]
```

#### Replace with

```meson
occoder_vapi_depends = [occoder_base_lib, ocfiles_vapi, ollmchat_base_lib, ollamaweb_vapi, ocmarkdown_vapi, ocmarkdowngtk_vapi, ocrpc_vapi]
```

### 5. `liboccoder/meson.build` — typelib include

**Why:** the gir compiler must see `OCMarkdownGtk` when the preview class is public.

**Where:** the `occoder-typelib` `--includedir` list, after `libocmarkdown`.

**Depends on:** §1.

#### Remove

```meson
      '--includedir', meson.current_build_dir() / '..' / 'libocmarkdown',
```

#### Replace with

```meson
      '--includedir', meson.current_build_dir() / '..' / 'libocmarkdown',
      '--includedir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
```

### 6. `docs/meson.build` — valadoc source list

**Why:** valadoc compiles `liboccoder` sources directly. `libocmarkdowngtk` sources are already in that input.

**Where:** the `liboccoder` source list, immediately before `'../liboccoder/CoderView.vala'`.

**Depends on:** §1.

#### Add — immediately before `'../liboccoder/CoderView.vala'`.

```meson
    '../liboccoder/MarkdownView.vala',
```

---

## Phase 2 — Preview class owned by `CoderView`

ℹ️ Phase 2 is in the tree. The fences below match that code. Earlier fences targeted `liboccoder/SourceView.vala`. Those are withdrawn. The task-due header stub is already gone. The `file_changed` flag is `is_markdown` because the constructor already has a local named `markdown`. The header control is a flat `Gtk.Button`. The icon is the only change. It is hidden unless a markdown file is open.

- ✔️ `liboccoder/MarkdownView.vala` renders the document, restores scroll after a rebuild, opens the link popover, and moves to a search match. `scroll_to_end` stays false.
- ✔️ `CoderView` shows the active `DocView` or `SourceView`.
  - The active viewer for a markdown file is `MarkdownView`.
  - Project and file overlays stay above that column.
  - The button is a flat `Gtk.Button` on the `CoderView` header. `CoderView` uses it to show or hide the preview.
  - It shows the view the next click will open. No text label. It does not draw pressed or raised.
  - Source showing: `document-print-symbolic`.
  - Markdown showing: `format-justify-left-symbolic`.
  - Hidden unless the file is markdown, and hidden when no file is open. Markdown is `language` `markdown`, or a name ending in `.md` or `.markdown`.
  - ℹ️ The daemon sets `language` from the extension map. `md` and `markdown` both become `markdown`, in `ollmfilesd/BufferProviderBase.vala`.
  - The tooltip is the action of the next click.
  - Markdown showing: `Change to source view`.
  - Source showing: `Change to markdown`.
- ✔️ `MarkdownView` handles the render events.
  - Opening a markdown file turns the toggle on and shows the render. Nothing is stored per file.
  - The text rendered is `file.buffer`, the document.
  - ℹ️ `CoderView` search and `SourceView.current_buffer` read `source_view.buffer`. During a review that buffer is the diff (`diff_buffer` on `SourceView`). `file.buffer` stays the document.
  - A pending diff does not force the source view. The preview still shows the document.
  - Switching back to source shows the editor as it was, diff included.
  - Rebuild the render only when the document text changed since the last render.
  - Toggle flips with the same text only swap which view is visible.
  - A disk reload, or an edit made in the source view, changes the text, so the next show rebuilds.
  - On that rebuild, put the markdown scroller back to the scroll position it had.
  - Opening a file, or opening a different file, starts the render at the top.
  - `MarkdownGtk.Render.scroll_to_end` stays false. The chat default scrolls to the bottom.
  - The rendered view is read-only.
  - A click on a link opens a popover that shows the link. The first click does not navigate.
  - A click on the popover follows the link.
  - The render's `link_clicked` is what opens that popover.
- ✔️ The desktop search bar stays on `CoderView` and stays visible in rendered mode.
  - `perform_search`, `forward_search`, and `backward_search` use the document text while markdown is showing.
  - `CoderView` asks the active `DocView` to move to that match.
  - Search does not use `diff_buffer`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 7. `liboccoder/DocView.vala` — the active viewer

**Why:** `CoderView` toggles from `SourceView` to whichever rendered viewer the file uses. `MarkdownView` is the first one. A later viewer for SVG, an image, or an HTML page implements the same interface.

**Where:** new file.

**Depends on:** none.

#### Add — new file `liboccoder/DocView.vala`. The interface is the active viewer `CoderView` shows.

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

namespace OLLMcoder
{
	/**
	 * Rendered view of one open file.
	 *
	 * {@link CoderView} shows one {@link DocView} in place of
	 * {@link SourceView}. {@link MarkdownView} is the markdown
	 * implementor. Another implementor can render a different kind
	 * of file behind the same toggle.
	 *
	 * == Example ==
	 *
	 * {{{
	 * DocView doc = new MarkdownView();
	 * doc.show_file(file, true);
	 * doc.show_match("Hello", true, false, false);
	 * }}}
	 */
	public interface DocView : Gtk.Widget
	{
		/**
		 * Show this file.
		 *
		 * A new file starts at the top. The same file with the same
		 * contents does not rebuild.
		 *
		 * @param file Open file. The viewer reads what it needs.
		 * @param new_document True when the open file changed
		 */
		public abstract void show_file(OLLMfiles.File file, bool new_document);

		/**
		 * Move the view to the next match.
		 *
		 * A viewer that cannot search returns false.
		 *
		 * @param query Search text. A regex when ''use_regex'' is true
		 * @param forward True for the next match, false for the previous
		 * @param case_sensitive True when case matters
		 * @param use_regex True when ''query'' is a regular expression
		 * @return True when a match was shown
		 */
		public abstract bool show_match(string query, bool forward, bool case_sensitive, bool use_regex);
	}
}
```

### 8. Build lists — `DocView` before `MarkdownView`

**Why:** `MarkdownView` implements `DocView`, so the interface is compiled first.

**Where:** `liboccoder/meson.build` `occoder_src`, `docs/meson.build` valadoc list, and the namespace overview.

**Depends on:** §7.

#### Add — `liboccoder/meson.build` `occoder_src`, immediately before `'MarkdownView.vala'`.

```meson
  'DocView.vala',
```

#### Add — `docs/meson.build`, immediately before `'../liboccoder/MarkdownView.vala'`.

```meson
    '../liboccoder/DocView.vala',
```

#### Add — `liboccoder/namespace.vala`, immediately before the `MarkdownView` bullet.

```vala
 *  * DocView: Rendered view of one open file
```

### 9. `liboccoder/MarkdownView.vala` — implement `DocView`

**Why:** the markdown viewer is the `DocView` a markdown file activates. It reads `file.buffer` itself.

**Where:** the class declaration, the example, and `show_text`.

**Depends on:** §7.

#### Remove

```vala
	 * var preview = new MarkdownView();
	 * preview.show_text("# Hello\n", true);
	 * preview.show_match("Hello", true, false, false);
	 * }}}
	 */
	public class MarkdownView : Gtk.Box
```

#### Replace with

```vala
	 * var preview = new MarkdownView();
	 * preview.show_file(file, true);
	 * preview.show_match("Hello", true, false, false);
	 * }}}
	 */
	public class MarkdownView : Gtk.Box, DocView
```

#### Remove

```vala
		/**
		 * Render this document text.
		 *
		 * The same text leaves the current render in place. Changed
		 * text rebuilds and restores the scroll position. A new
		 * document starts at the top.
		 *
		 * @param text Document text from the file buffer
		 * @param new_document True when the open file changed
		 */
		public void show_text(string text, bool new_document)
		{
			if (this.has_shown && text == this.shown) {
```

#### Replace with

```vala
		/**
		 * Show this markdown file.
		 *
		 * Reads the document from ''file.buffer''. The same text
		 * leaves the current render in place. Changed text rebuilds
		 * and restores the scroll position. A new document starts
		 * at the top.
		 *
		 * @param file Open file
		 * @param new_document True when the open file changed
		 */
		public void show_file(OLLMfiles.File file, bool new_document)
		{
			var text = ((GtkSource.Buffer) file.buffer).text;
			if (this.has_shown && text == this.shown) {
```

### 10. `liboccoder/CoderView.vala` — class overview

**Why:** the screen owns both the editor and the active `DocView`.

**Where:** the class docblock, the header sentence and the editor sentence.

**Depends on:** none.

#### Remove

```vala
	 * The header is {@link ProjectSelector}, {@link File.Nav}, and
	 * the editor save button.
	 * The editor is {@link SourceView}. The project list is an
	 * overlay on that editor. Project selection and search stay
	 * here. A chosen file is opened on the editor.
```

#### Replace with

```vala
	 * The header is {@link ProjectSelector}, {@link File.Nav},
	 * the editor save button, and the document toggle.
	 * The editor is {@link SourceView}. A rendered file shows
	 * the active {@link DocView} in that column instead. The project
	 * list is an overlay on that column. Project selection and
	 * search stay here. A chosen file is opened on the editor.
```

### 11. `liboccoder/CoderView.vala` — `doc` field

**Why:** search methods run outside the constructor, so the active viewer cannot be a local.

**Where:** field list, immediately after `editor`.

**Depends on:** none.

#### Remove

```vala
		public SourceView editor { get; private set; }
		private Gtk.SearchEntry search_entry;
```

#### Replace with

```vala
		public SourceView editor { get; private set; }
		private DocView doc;
		private Gtk.SearchEntry search_entry;
```

### 12. `liboccoder/CoderView.vala` — `md` toggle

**Why:** `CoderView` shows or hides the active `DocView`. The control is a flat button. A click swaps the icon. Opening a file sets the icon without a click.

**Where:** constructor, immediately after `header.append(this.editor.save_button)`.

**Depends on:** §9, §11. The column in §13 assigns `this.doc` before any file can open.

#### Add — immediately after `header.append(this.editor.save_button)`. The button stays hidden until a markdown file is open. `showing_doc` is which view is up.

```vala
			var showing_doc = false;
			var md_button = new Gtk.Button() {
				icon_name = "document-print-symbolic",
				tooltip_text = "Change to markdown",
				hexpand = false,
				valign = Gtk.Align.CENTER,
				visible = false,
			};
			md_button.add_css_class("flat");
			md_button.clicked.connect(() => {
				if (showing_doc) {
					showing_doc = false;
					md_button.icon_name = "document-print-symbolic";
					md_button.tooltip_text = "Change to markdown";
					this.doc.visible = false;
					this.editor.visible = true;
					return;
				}
				var file = this.editor.current_file;
				if (file == null) {
					md_button.visible = false;
					return;
				}
				showing_doc = true;
				md_button.icon_name = "format-justify-left-symbolic";
				md_button.tooltip_text = "Change to source view";
				this.doc.show_file(file, false);
				this.editor.visible = false;
				this.doc.visible = true;
			});
			header.append(md_button);
```

### 13. `liboccoder/CoderView.vala` — editor column

**Why:** the active `DocView` sits in the editor column. The search bar stays under whichever view is visible. Hiding `SourceView` hides the review bar with it.

**Where:** constructor, the `editor_column.append` calls.

**Depends on:** §11.

#### Remove

```vala
			editor_column.append(this.editor);
			editor_column.append(search_bar);
```

#### Replace with

```vala
			var markdown = new MarkdownView() {
				visible = false,
			};
			this.doc = markdown;
			editor_column.append(markdown);
			editor_column.append(this.editor);
			editor_column.append(search_bar);
```

### 14. `liboccoder/CoderView.vala` — `file_changed`

**Why:** opening a markdown file turns that `DocView` on and starts at the top. Any other file shows the editor. A pending diff does not get its own listener. `MarkdownView` reads `file.buffer`.

**Where:** the `file_changed` lambda, from `search_bar.visible = true` through the closing of that lambda.

**Depends on:** §9, §12, §13.

#### Remove

```vala
				search_bar.visible = true;
			});
```

#### Replace with

```vala
				search_bar.visible = true;
				var is_markdown = file.language.down() == "markdown" ||
					file.path_basename.down().has_suffix(".md") ||
					file.path_basename.down().has_suffix(".markdown");
				md_button.visible = is_markdown;
				if (!is_markdown) {
					showing_doc = false;
					md_button.icon_name = "document-print-symbolic";
					md_button.tooltip_text = "Change to markdown";
					this.doc.visible = false;
					this.editor.visible = true;
					return;
				}
				showing_doc = true;
				md_button.icon_name = "format-justify-left-symbolic";
				md_button.tooltip_text = "Change to source view";
				this.doc.show_file(file, true);
				this.editor.visible = false;
				this.doc.visible = true;
			});
```

### 15. `liboccoder/CoderView.vala` — `perform_search`

**Why:** while a `DocView` is showing, the match count uses the document buffer. `current_buffer` is the diff during a review.

**Where:** `perform_search`, the null check and the `SearchContext` line.

**Depends on:** §11.

#### Remove

```vala
			if (this.editor.current_buffer == null) {
				this.search_context = null;
				this.update_search_results();
				return;
			}
			var search_settings = new GtkSource.SearchSettings();
			search_settings.case_sensitive = this.case_sensitive_checkbox.active;
			search_settings.regex_enabled = this.regex_checkbox.active;
			search_settings.wrap_around = false;
			this.search_context = new GtkSource.SearchContext(this.editor.current_buffer, search_settings);
```

#### Replace with

```vala
			var search_buffer = this.editor.current_buffer;
			if (this.doc.visible && this.editor.current_file != null) {
				search_buffer = this.editor.current_file.buffer as GtkSource.Buffer;
			}
			if (search_buffer == null) {
				this.search_context = null;
				this.update_search_results();
				return;
			}
			var search_settings = new GtkSource.SearchSettings();
			search_settings.case_sensitive = this.case_sensitive_checkbox.active;
			search_settings.regex_enabled = this.regex_checkbox.active;
			search_settings.wrap_around = false;
			this.search_context = new GtkSource.SearchContext(search_buffer, search_settings);
```

### 16. `liboccoder/CoderView.vala` — `forward_search`

**Why:** the next match moves the view that is on screen.

**Where:** `forward_search`, immediately after the opening brace.

**Depends on:** §13.

#### Add — immediately after the opening brace of `forward_search`. A preview match does not scroll `SourceView`.

```vala
			if (this.doc.visible) {
				var txt = this.search_entry.text;
				if (this.multiline_checkbox.active) {
					txt = txt.replace("\\n", "\n");
				}
				this.doc.show_match(txt, true,
					this.case_sensitive_checkbox.active, this.regex_checkbox.active);
				return;
			}
```

### 17. `liboccoder/CoderView.vala` — `backward_search`

**Why:** the previous match moves the view that is on screen.

**Where:** `backward_search`, immediately after the opening brace.

**Depends on:** §13.

#### Add — immediately after the opening brace of `backward_search`. A preview match does not scroll `SourceView`.

```vala
			if (this.doc.visible) {
				var txt = this.search_entry.text;
				if (this.multiline_checkbox.active) {
					txt = txt.replace("\\n", "\n");
				}
				this.doc.show_match(txt, false,
					this.case_sensitive_checkbox.active, this.regex_checkbox.active);
				return;
			}
```

### 18. `resources/style.css` — no pressed `md` button

**Why:** the header control is a flat button. The icon is the only change. It does not use a recessed checked style.

**Where:** there is no `md` rule. `button.page-picker.picker-on` stays as it was.

**Depends on:** §12.

---

## Phase 3 (optional) — Diff colour in the render

- 🔷 ⏳ Unapproved hunks match the source diff. Added lines get a green background. Removed lines get a red background.
- 🔷 ⏳ Render the document with those diff lines included.
  - The renderer can draw the backgrounds.
  - The risk is that the extra lines make the markdown invalid, so the render comes out wrong.
  - When that render is wrong, render the plain document instead.
- 🔷 ⏳ Approving a deletion removes that text. The red comes off.
- 🔷 ⏳ Approving a change takes the colour off. Those lines look like normal markdown.
- 🔷 ⏳ Rejecting a change reverts the text. That change is gone from the render.
- 🔷 ⏳ The review bar jumps to that line and the band is grey. The bar is on the source editor, so it is off screen while markdown is showing.
  - Toggle to source to see the grey line.
  - Toggle back to markdown to return to the rendered document.

---

## Phase 4 (optional) — Progressive render

- 🔷 ⏳ The markdown library records the source line range for each rendered piece.
- 🔷 ⏳ When a chunk of the document text changes, find that range in the render, delete it, and replace it with the render of the new chunk.
- 🔷 ⏳ A long-press on a rendered spot uses that same line range. It switches to the source view and starts editing at that line.

---

## Phase 5 (optional) — Zoom on the render

- 🔷 ⏳ Ctrl+wheel and pinch zoom apply to the rendered view.
  - ℹ️ Today zoom only targets `.source-view`.

---

## LLM notes

- 🚫 Do not put render, scroll, link, or match-move handling inline in `CoderView`. That stays on the `DocView`.
- 🚫 Do not add the toggle or the render to `liboccoder/SourceView.vala`.
- 🚫 Do not link `ocmarkdowngtk` only on `oc-test-source-diff`. The viewer is in `liboccoder`.
- 🚫 Do not fold `Diff.ReviewBar` or the chat history sidebar into `DocView`.
- 🚫 Do not add an SVG, image, or HTML viewer in this phase.
- 🚫 Phase 2 is in the tree. Do not implement Phase 3, Phase 4, or Phase 5 until they are approved.
