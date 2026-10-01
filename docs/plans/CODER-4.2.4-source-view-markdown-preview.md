# CODER-4.2.4 Source view markdown preview

**Status:** ⏳ proposed

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan** until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala code must follow `docs/coding-standards.md`.

**Related:** [`CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md`](CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md) — removes the header `Approvals` hover list (the "history" button) that sits where the new toggle goes.

---

## Purpose

- 🔷 On all platforms (desktop and Android), `SourceView` shows markdown files rendered as markdown.
- 🔷 Markdown files open in the rendered view by default.
  - 🔷 Main reason: Android will mostly be used to read and edit markdown files, and a rendered view reads better.
- 🔷 A toggle switches back to the plain source view (and back again).
- 🔷 The toggle lives in the `SourceView` header (file open / navigation bar), at the right end.
  - 🔷 Same place on desktop and Android. The phone bottom button row is **not** used.
  - 🔷 It takes the slot of the `Approvals` "history" hover button, which is being removed soon.
- 🔷 When the file changes on disk, the rendered view refreshes.
  - 🔷 Refresh is a full re-render. Renders are expected to be fast enough.
- ⏳ All work below is backlog.

---

## Behaviour

- 🔷 ⏳ Open a markdown file → toggle visible and active → rendered view shown, source view hidden.
- 🔷 ⏳ Click the toggle → switch between rendered and source.
- 🔷 ⏳ File changes on disk (existing `event.project.invalidate_cache` reload in the `SourceView` ctor) → buffer reloads → re-render.
- 🔷 ⏳ Non-markdown file → toggle hidden → source view as today.
- 💩 ⏳ Markdown detection uses `file.language == "markdown"`.
  - ℹ️ The daemon sets `language` from the extension map (`md`, `markdown` → `markdown`) in `ollmfilesd/BufferProviderBase.vala`.
- 💩 ⏳ Toggle resets to rendered each time a markdown file is opened. No per-file memory.
- 💩 ⏳ The render reads the **buffer** text, so unsaved source edits show when toggling to rendered.
- 💩 ⏳ A pending diff (review bar) always wins: the source/diff view shows while `diff_active`, even if the toggle is on.
- 💩 ⏳ On re-render after a disk change, keep the markdown scroll position. On opening a different file, start at the top.
- 💩 ⏳ Rendered view is read-only. Editing (including the Android long-press) stays in the source view.

---

## Phase 1 — Build: link `libocmarkdowngtk` into `liboccoder`

ℹ️ `liboccoder` links `libocmarkdown` but not `libocmarkdowngtk`. Both subdirs already build before `liboccoder` in root `meson.build` (desktop and Android branches). `lib_build_rpath` already lists `libocmarkdowngtk`.

### 1. `liboccoder/meson.build` — `occoder_lib_deps`: add the GTK markdown VAPI dependency

**Why:** `SourceView` uses `MarkdownGtk.Render` / `MarkdownGtk.RenderBox`.

**Where:** `occoder_lib_deps = [...]` line.

**Depends on:** none.

#### Remove

```meson
occoder_lib_deps = [occoder_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ocmarkdown_vapi_dep, ocrpc_vapi_dep]
```

#### Replace with

```meson
occoder_lib_deps = [occoder_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ocmarkdown_vapi_dep, ocmarkdowngtk_vapi_dep, ocrpc_vapi_dep]
```

### 2. `liboccoder/meson.build` — `occoder_vala_args`: package and VAPI dir

**Why:** valac must find `ocmarkdowngtk.vapi` when compiling the library.

**Where:** inside `occoder_vala_args = [...]`. Part 1 is the `--pkg` list. Part 2 is the `--vapidir` list (the block containing `liboctools`).

**Depends on:** §1.

##### Part 1 — `--pkg`

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

##### Part 2 — `--vapidir`

#### Remove

```meson
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
```

#### Replace with

```meson
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
```

### 3. `liboccoder/meson.build` — both `library(occoder_lib, ...)` calls: C header include dir

**Why:** generated C includes `ocmarkdowngtk.h` (same as `ollmapp/meson.build` does with `include_directories('../libocmarkdowngtk')`).

**Where:** `include_directories: [...]` in the Android (`if is_android_cross`) **and** desktop (`else`) `library()` calls. The block is identical in both — apply to both.

**Depends on:** §1.

#### Remove

```meson
      include_directories('..' / 'libocfiles')     # For C headers (build directory)
    ],
```

#### Replace with

```meson
      include_directories('..' / 'libocfiles'),     # For C headers (build directory)
      include_directories('..' / 'libocmarkdowngtk')
    ],
```

### 4. `liboccoder/meson.build` — `occoder.vapi` custom target: package, VAPI dir, depends

**Why:** the hand-built `occoder.vapi` runs its own valac and needs the same package.

**Where:** three spots — `occoder_vapi_gen_pkgs`, `occoder_vapi_vapidirs`, `occoder_vapi_depends`.

**Depends on:** §1.

##### Part 1 — `occoder_vapi_gen_pkgs`

#### Remove

```meson
  '--pkg', 'ocmarkdown',
```

#### Replace with

```meson
  '--pkg', 'ocmarkdown',
  '--pkg', 'ocmarkdowngtk',
```

##### Part 2 — `occoder_vapi_vapidirs`

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

##### Part 3 — `occoder_vapi_depends`

#### Remove

```meson
occoder_vapi_depends = [occoder_base_lib, ocfiles_vapi, ollmchat_base_lib, ollamaweb_vapi, ocmarkdown_vapi, ocrpc_vapi]
```

#### Replace with

```meson
occoder_vapi_depends = [occoder_base_lib, ocfiles_vapi, ollmchat_base_lib, ollamaweb_vapi, ocmarkdown_vapi, ocmarkdowngtk_vapi, ocrpc_vapi]
```

- ℹ️ The new fields are private, so `OLLMcoder-1.0.gir` should not need `--girdir libocmarkdowngtk`. Verify with `ninja -C build`.

---

## Phase 2 — `SourceView`: toggle, rendered view, refresh

ℹ️ All edits in `liboccoder/SourceView.vala`. The re-render teardown copies `ChatView.clear()` in `libollmchatgtk/ChatView.vala` (`renderer.clear()`, new `RenderBox`, `disconnect_box()`, reconnect the three link signals).

### 1. `liboccoder/SourceView.vala` — fields

**Why:** hold the toggle, the rendered view's scroller, and the renderer.

**Where:** class fields, directly after `private Gtk.ScrolledWindow scrolled_window;`.

**Depends on:** Phase 1.

#### Add — after `private Gtk.ScrolledWindow scrolled_window;`: markdown view fields.

```vala
		private Gtk.ScrolledWindow markdown_scrolled;
		private Gtk.ToggleButton markdown_toggle;
		private MarkdownGtk.Render markdown_render;
```

### 2. `liboccoder/SourceView.vala` — ctor: toggle at the right of the header

**Why:** 🔷 toggle in the file navigation bar, rightmost (where the `Approvals` hover button is today).

**Where:** constructor, immediately after `header_bar.append(this.approvals);`.

**Depends on:** §1, §8.

- 💩 Icon `view-reveal-symbolic` is a placeholder. Check it is bundled in the Android APK icon set.
- 💩 Uses `clicked`, not `toggled`. `Gtk.Button::clicked` is run-first, so `active` is already flipped when the handler runs. Programmatic `active = true` in `open_file` does **not** fire it, so `open_file` controls when the render happens.

#### Add — after `header_bar.append(this.approvals);`: markdown toggle button.

```vala
			this.markdown_toggle = new Gtk.ToggleButton() {
				icon_name = "view-reveal-symbolic",
				tooltip_text = "Show rendered markdown",
				active = true,
				visible = false
			};
			this.markdown_toggle.clicked.connect(() => {
				this.show_markdown();
			});
			header_bar.append(this.markdown_toggle);
```

### 3. `liboccoder/SourceView.vala` — ctor: invalidate_cache reload re-renders

**Why:** 🔷 refresh the rendered view when the file changes on disk.

**Where:** constructor, `this.manager.notification.connect(...)` → `file.check_changed.begin` callback → `file.read.begin` callback. Between the pending-diff early return and `this.restore_cursor_position(file);`.

**Depends on:** §8.

#### Remove

```vala
							this.show_pending_diff.begin(file);
							return;
						}
						this.restore_cursor_position(file);
```

#### Replace with

```vala
							this.show_pending_diff.begin(file);
							return;
						}
						this.show_markdown();
						this.restore_cursor_position(file);
```

### 4. `liboccoder/SourceView.vala` — ctor: build the rendered view

**Why:** a second scroller for the rendered markdown, hidden until a markdown file opens.

**Where:** constructor, immediately after `this.scrolled_window.visible = false;` (the line after `this.scrolled_window.set_child(this.source_view);`).

**Depends on:** §1.

- 💩 `scroll_to_end = false` — the renderer default scrolls to the bottom (chat behaviour).
- 💩 Link clicks are not wired in this plan (no `link_clicked` handler).

#### Add — after `this.scrolled_window.visible = false;`: rendered markdown scroller and renderer.

```vala
			this.markdown_scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				visible = false
			};
			this.markdown_render = new MarkdownGtk.Render(new MarkdownGtk.RenderBox()) {
				scroll_to_end = false
			};
```

### 5. `liboccoder/SourceView.vala` — ctor: overlay child holds both views

**Why:** the review overlay and (on Android) the toast overlay wrap the editor. Both views must sit inside, so visibility toggles swap them in place.

**Where:** constructor, `editor_overlay.set_child(this.scrolled_window);` (after `var editor_overlay = new Gtk.Overlay() { ... };`).

**Depends on:** §4.

#### Remove

```vala
			editor_overlay.set_child(this.scrolled_window);
```

#### Replace with

```vala
			var editor_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				vexpand = true,
				hexpand = true
			};
			editor_box.append(this.scrolled_window);
			editor_box.append(this.markdown_scrolled);
			editor_overlay.set_child(editor_box);
```

### 6. `liboccoder/SourceView.vala` — `on_file_selected()`: hide rendered view when no file

**Why:** no file → nothing shown, same as the source view.

**Where:** `on_file_selected()`, `if (file == null)` branch, after `this.scrolled_window.visible = false;`.

**Depends on:** §2, §4.

#### Remove

```vala
				this.scrolled_window.visible = false;
				this.search_bar.visible = false;
```

#### Replace with

```vala
				this.scrolled_window.visible = false;
				this.markdown_scrolled.visible = false;
				this.markdown_toggle.visible = false;
				this.search_bar.visible = false;
```

### 7. `liboccoder/SourceView.vala` — `open_file()`: default to rendered for markdown

**Why:** 🔷 markdown files open rendered by default. Runs after the pending-diff check so `diff_active` is known.

**Where:** `open_file()`, after the closing `}` of the `if (file.delete_id > 0) { ... } else { ... }` block, before `// Reset search context when switching files`.

**Depends on:** §2, §4, §8.

#### Remove

```vala
				yield this.show_pending_diff(file);
			}
			
			// Reset search context when switching files
```

#### Replace with

```vala
				yield this.show_pending_diff(file);
			}
			
			this.markdown_toggle.visible = file.language == "markdown";
			this.markdown_toggle.active = true;
			this.markdown_scrolled.vadjustment.value = 0;
			this.show_markdown();
			
			// Reset search context when switching files
```

### 8. `liboccoder/SourceView.vala` — new method `show_markdown()`

**Why:** one place that picks rendered vs source and rebuilds the render. Called from the toggle (§2), disk reload (§3), and `open_file` (§7).

**Where:** new private method, directly after `clear_diff()`.

**Depends on:** §1, §4.

- 💩 New method — the user did not name it. Approve the name, or say to inline the body at §2, §3, and §7 instead (three copies).
- 💩 Scroll restore runs on idle because the new widgets have no height until laid out.

#### Add — after `clear_diff()`: choose view and re-render markdown from the buffer.

```vala
		/**
		 * Show the current buffer as rendered markdown, or the source view.
		 *
		 * Rendered shows when the toggle is visible and active and no diff
		 * is open. Each call rebuilds the render from the buffer text and
		 * keeps the scroll position.
		 */
		private void show_markdown()
		{
			var show = this.markdown_toggle.visible && this.markdown_toggle.active && !this.diff_active;
			this.scrolled_window.visible = !show;
			this.markdown_scrolled.visible = show;
			if (!show) {
				return;
			}
			var top = this.markdown_scrolled.vadjustment.value;
			this.markdown_render.clear();
			this.markdown_render.disconnect_box();
			this.markdown_render.box = new MarkdownGtk.RenderBox() {
				margin_start = 8,
				margin_end = 8,
				margin_top = 8,
				margin_bottom = 8
			};
			this.markdown_render.box.on_link_click_released.connect(this.markdown_render.on_link_click_released);
			this.markdown_render.box.on_link_motion.connect(this.markdown_render.on_link_motion);
			this.markdown_render.box.on_link_leave.connect(this.markdown_render.on_link_leave);
			this.markdown_scrolled.set_child(this.markdown_render.box);
			this.markdown_render.start();
			this.markdown_render.add(this.current_buffer.text);
			this.markdown_render.flush();
			GLib.Idle.add(() => {
				this.markdown_scrolled.vadjustment.value = top;
				return false;
			});
		}
```

### 9. `liboccoder/SourceView.vala` — `show_diff()`: diff hides the rendered view

**Why:** 💩 a pending diff always shows in the source view, even for markdown files.

**Where:** `show_diff()`, last line `this.scrolled_window.visible = true;`.

**Depends on:** §4.

#### Remove

```vala
			this.diff_active = true;
			this.scrolled_window.visible = true;
		}
```

#### Replace with

```vala
			this.diff_active = true;
			this.scrolled_window.visible = true;
			this.markdown_scrolled.visible = false;
		}
```

---

## Open questions

- 💩 ⏳ Desktop search bar searches the source buffer. In rendered mode, hide it, or switch to source on search?
- 💩 ⏳ Ctrl+wheel / pinch font zoom only targets `.source-view`. Apply to the rendered view too?
- 💩 ⏳ Links in rendered markdown: open `http(s)` externally? Open relative `.md` links in `SourceView`?
- 💩 ⏳ Persist rendered vs source per file (DB), instead of always defaulting to rendered?
- ℹ️ `refresh_file()` (public, no callers) reloads the buffer without re-rendering. Left as is.
