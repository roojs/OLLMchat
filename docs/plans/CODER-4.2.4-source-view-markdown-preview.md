# CODER-4.2.4 Source view markdown preview

**Status:** ⏳ proposed

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan** until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala code must follow `docs/coding-standards.md`.

**Related:**

- ℹ️ Smoke screen is [`CODER-4.2.5-project-file-selector.md`](CODER-4.2.5-project-file-selector.md). The header is `examples/oc-test-source-diff/CoderView.vala`.
- ℹ️ Product `SourceView` header comes after that smoke window.

---

## Purpose

- 🔷 Phase 1 links `libocmarkdowngtk` into the smoke app.
- 🔷 Phase 2 is the markdown preview on `CoderView`.
- 🔷 Phase 3 (optional) draws diff colours in that render.
- 🔷 Phase 4 (optional) replaces a changed chunk in the render. A long-press jumps to that source line.
- 🔷 Phase 5 (optional) is Ctrl+wheel and pinch zoom on the render.

---

## Phase 1 — Link `libocmarkdowngtk` into the smoke app

ℹ️ `examples/oc-test-source-diff` is where `CoderView` lives. `liboccoder` stays without this dependency. `build_rpath` in `examples/meson.build` already lists `libocmarkdowngtk`. Both the Android executable (the `host_machine.system() == 'android'` block) and the desktop `test_source_diff` executable need the same three edits.

- 🔷 ⏳ `oc-test-source-diff` can construct `MarkdownGtk.Render`.

### 1. `examples/meson.build` — dependencies

**Why:** the smoke app constructs `MarkdownGtk.Render`.

**Where:** the `dependencies:` array of both `oc-test-source-diff` executables. Android is the `if host_machine.system() == 'android'` block. Desktop is `test_source_diff`.

**Depends on:** none.

#### Remove

```meson
      ollmchat_vapi_dep,
      ollamaweb_vapi_dep
```

#### Replace with

```meson
      ollmchat_vapi_dep,
      ollamaweb_vapi_dep,
      ocmarkdowngtk_vapi_dep
```

The desktop list is one line. Same addition, before the closing `]`.

#### Remove

```meson
  dependencies: [test_window_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ollamaweb_vapi_dep],
```

#### Replace with

```meson
  dependencies: [test_window_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ollamaweb_vapi_dep, ocmarkdowngtk_vapi_dep],
```

### 2. `examples/meson.build` — C header include

**Why:** generated C includes `ocmarkdowngtk.h`.

**Where:** `include_directories:` in both executables, next to `include_directories('../liboccoder')`.

**Depends on:** §1.

#### Remove

```meson
      include_directories('../liboccoder'),
```

#### Replace with

```meson
      include_directories('../liboccoder'),
      include_directories('../libocmarkdowngtk'),
```

Apply to both executables. The Android list has `include_directories('../ollmapp/android')` after this line. Leave that line.

### 3. `examples/meson.build` — `vala_args`

**Why:** valac must see `ocmarkdown` and `ocmarkdowngtk`.

**Where:** `vala_args` in both executables, with the existing `--pkg=ollmchat` line.

**Depends on:** §1.

#### Remove

```meson
      '--pkg=ollmchat',
      '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
```

#### Replace with

```meson
      '--pkg=ollmchat',
      '--pkg=ocmarkdown',
      '--pkg=ocmarkdowngtk',
      '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
      '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
```

Apply to both executables. Android also has `'--pkg=ocfiles'` above `'--pkg=ollmchat'`. Leave that.

---

## Phase 2 — Markdown preview on `CoderView`

ℹ️ Widget hunks are not fenced yet. Earlier fences targeted `liboccoder/SourceView.vala`. Those are withdrawn.

- 🔷 ⏳ The `md` button is a `Gtk.ToggleButton` on `examples/oc-test-source-diff/CoderView.vala`. It replaces the History button.
  - Label is `md`. No icon.
  - Hidden unless `file.language` is `markdown`, and hidden when no file is open.
  - ℹ️ The daemon sets `language` from the extension map. `md` and `markdown` both become `markdown`, in `ollmfilesd/BufferProviderBase.vala`.
  - No `flat` class. Active draws recessed, same idea as `button.page-picker.picker-on` in `resources/style.css` (inset shadow).
  - The tooltip is the action of the next click.
  - Active, markdown showing: `Change to source view`.
  - Inactive, source showing: `Change to markdown`.
- 🔷 ⏳ Opening a markdown file turns the toggle on and shows the render. Nothing is stored per file.
- 🔷 ⏳ The rendered scroller sits in the editor column, in place of `SourceView` while markdown is showing. Project and file overlays stay above that column.
- 🔷 ⏳ The text rendered is `file.buffer`, the document.
  - ℹ️ `CoderView` search and `SourceView.current_buffer` read `source_view.buffer`. During a review that buffer is the diff (`diff_buffer` in `examples/oc-test-source-diff/SourceView.vala`). `file.buffer` stays the document.
- 🔷 ⏳ A pending diff does not force the source view. Markdown still shows the document.
  - Switching back to source shows the editor as it was, diff included.
- 🔷 ⏳ Rebuild the render only when the document text changed since the last render.
  - Toggle flips with the same text only swap which view is visible.
  - A disk reload, or an edit made in the source view, changes the text, so the next show rebuilds.
- 🔷 ⏳ On that rebuild, put the markdown scroller back to the scroll position it had.
- 🔷 ⏳ Opening a file, or opening a different file, starts the render at the top.
  - `MarkdownGtk.Render.scroll_to_end` stays false. The chat default scrolls to the bottom.
- 🔷 ⏳ The rendered view is read-only.
- 🔷 ⏳ A click on a link opens a popover that shows the link. The first click does not navigate.
  - A click on the popover follows the link.
  - The render's `link_clicked` is what opens that popover.
- 🔷 ⏳ The desktop search bar stays visible in rendered mode.
  - `perform_search`, `forward_search`, and `backward_search` use the document text while markdown is showing.
  - A match moves the view that is on screen.
  - Search does not use `diff_buffer`.

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

- 🚫 Phase 2 is `examples/oc-test-source-diff/CoderView.vala`. Do not add the toggle to `liboccoder/SourceView.vala`.
- 🚫 Do not implement Phase 3, Phase 4, or Phase 5 while doing Phase 2.
