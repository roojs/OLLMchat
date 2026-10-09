# CODER-4.2.5 Project and file selector

**Status:** ⏳ proposed. ✔️ Phase 1 selector row is in the diff smoke app only. Product chrome is still backlog.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**.

**Related:**

- ℹ️ [`CODER-4.2.1-tree-navigation-filedropdown.md`](CODER-4.2.1-tree-navigation-filedropdown.md) — tree tab inside the file picker. The popup chrome in that plan is replaced by this one.
- ℹ️ Phone source-view selection trouble, partly worked: [`docs/bugs/2026-09-29-android-source-view-phone.md`](../bugs/2026-09-29-android-source-view-phone.md).
- ℹ️ Today: `liboccoder/ProjectDropdown.vala`, `liboccoder/FileDropdown.vala`, `liboccoder/SearchableDropdown.vala`, header in `liboccoder/SourceView.vala`.
- ℹ️ Phone history today: `ollmapp/android/OllmchatWindow.vala` swaps `view_stack` to `HistoryBrowser` and keeps the window header. Search is at the top and takes focus (`libollmchatgtk/HistoryBrowser.vala`).
- ℹ️ Diff smoke app: `examples/oc-test-source-diff.vala` (`TestAppBase`). Desktop executable only. It already constructs `OLLMfiles.ProjectManager` and fills the view from local file pairs.
- ℹ️ Header history button is `Approvals` in `liboccoder/SourceView.vala`. The view toggle that replaces it is [`CODER-4.2.4-source-view-markdown-preview.md`](CODER-4.2.4-source-view-markdown-preview.md).

---

## Purpose

- 🔷 Replace the project selector and the file selector.
- 🔷 They stop being a text entry plus a pull-down.
- 🔷 Resting state on every layout is a flattened button: the current name as text, search icon on the left.
- 🔷 Desktop stays a pop-down. Phone and tablet share a pull-over. Tablet follows the phone, not the desktop.
- 🔷 Phone and tablet also move chat history onto that same pull-over.
- 🔷 Phase 1 proves that row on the existing diff smoke app, on desktop and on Android, with data from filesd.
- ⏳ All work below is backlog.

---

## Shared button

- 🔷 ⏳ Project control and file control are buttons, not entries, until activated.
- 🔷 ⏳ Flattened button. Search icon sits to the left of the label.
- ℹ️ Desktop and touch use the same resting button. What a click does is what splits.

### File button label

- 🔷 ⏳ Phone shows the file name only.
- 🔷 ⏳ Tablet and desktop show the path relative to the project.
- 🔷 ⏳ That relative path ellipsizes at the start, so the end of the path stays visible.
- 🔷 ⏳ Mouse over on tablet and desktop shows the full path.
- 🔷 ⏳ That full-path hover is on the project button and the file button.

### Row

- 🔷 ⏳ No project: the project button says `Select project`.
- 🔷 ⏳ No project: the file button is not shown.
- ℹ️ `SourceView` already hides `file_dropdown` until a project is selected.
- 🔷 ⏳ After a project is selected, the file button is shown.
- 🔷 ⏳ On the phone, the project button has a maximum width.
- 🔷 ⏳ That cap is wide enough for a typical project name.
- 🔷 ⏳ A shorter project name makes the project button narrower than the cap.
- 🔷 ⏳ The file button takes the remaining width of the row.
- 🔷 ⏳ The header history button stays for this pass.
- 🔷 ⏳ That history button is replaced later by the view toggle.
- 🚫 Do not remove the history button in this plan.

## Desktop

- 🔷 ⏳ Click the button and it becomes a text entry and takes focus.
- 🔷 ⏳ That entry is a search, not the old fake pull-down.
- 🔷 ⏳ Search opens a pop-down under the control.
- 🔷 ⏳ Project pop-down is a list of projects.
- 🔷 ⏳ File pop-down is wide.
- 🔷 ⏳ File pop-down tabs:
  - Tree
  - History
  - Search results, when the entry has typed text
- 🔷 ⏳ Choosing a project still moves focus to the file control, as it does now.
  - ℹ️ `SourceView` calls `file_dropdown.grab_focus()` after a project is chosen.
  - 🔷 On desktop that focus is the file control in its entry state, so the file pop-down opens.
- ℹ️ Tree-tab contents stay specified in `CODER-4.2.1`. This plan only places that tab in the wide file pop-down.

---

## Phone and tablet

- 🔷 ⏳ Tablet uses this pull-over. It does not use the desktop pop-down.
- 🔷 ⏳ A click does not open a search field and does not raise the keyboard.
- 🔷 ⏳ A click opens a pull-over.
- 🔷 ⏳ Same pull-over for chat history, projects, and files.
- 🔷 ⏳ Top bar: back arrow, then a title.
  - Chat history
  - Projects
  - Files
- 🔷 ⏳ Current selection is text at the top of the page, under that bar.
- 🔷 ⏳ The list sits under the current selection.
- 🔷 ⏳ Search entry is at the bottom.
- 🔷 ⏳ The keyboard stays down until that bottom entry is focused.
- 🔷 ⏳ When the keyboard is up, the list collapses upward to the space left above it.
- 🔷 ⏳ Back arrow closes the pull-over.
- 🔷 ⏳ Choosing a row closes the pull-over.
- 🔷 ⏳ Which edge the pull-over comes from is not decided, and the tablet case is the open one.
- 🚫 Do not treat “left” or “right” as chosen.

### History moves onto this pull-over

- 🔷 ⏳ Phone history today keeps the window header, slides the list in, and puts search at the top.
- 🔷 ⏳ That layout changes to this pull-over.
- 🔷 ⏳ Search moves from the top to the bottom.
- 🔷 ⏳ Opening history must not focus the search entry and must not raise the keyboard.
- ℹ️ Today `history_toggle_button` grabs `history_browser.search_entry` as soon as history is shown.

---

## Phase 1 — extend `oc-test-source-diff`

- 🔷 ✔️ Same idea as the diff work: an out-of-band window, not the product app.
- 🔷 ✔️ Extend `examples/oc-test-source-diff.vala`. Do not start a second app.
- 🚫 A temporary selection tool that copies the selectors out of the diff smoke app.
- ℹ️ Row widget: `examples/oc-test-source-diff-selectors.vala` (`TestSelectorRow`). No library files change.

### Top row

- 🔷 ✔️ Put the project and file selector row on that window.
- 🔷 ✔️ Desktop run uses the desktop pop-down.
- 🔷 ✔️ `--phone` and `--tablet` use the pull-over in this same binary.
- ℹ️ `--phone` or `--tablet` turns the selector subtest on. File pairs stay optional.
- ℹ️ Tree, history, and search-results tabs are not in this subtest. The file list is one search page from filesd.

### filesd

- 🔷 ✔️ The selectors load projects and files from a running filesd.
- ℹ️ `OLLMfiles.rpc_register`, then `ProjectManager.rpc.connect` and `rpc_load_projects_from_db`.

### Android

- 🔷 ⏳ The same extended window is the Android test.
- 💩 ⏳ How that window is packaged on Android is not specified. `oc-test-source-diff` is not in the Android APK build today.
- ℹ️ Until that packaging exists, `--phone` and `--tablet` are how the pull-over is opened.

---

## Later

- 🔷 ⏳ Product `SourceView` header and the phone history pull-over come after the smoke window shows the row on desktop and on Android.

---

## Out of scope

- 🚫 Desktop chat history. This pass only moves the phone and tablet history list onto the pull-over.
- 🚫 Implementing the tree model. That stays in `CODER-4.2.1`.
- 🚫 A phone or tablet copy of the desktop tabbed file pop-down. Tabs were specified for the desktop file pop-down only.
- 🚫 Auto-opening the file pull-over after a project pick on phone or tablet. The focus flip was specified for desktop only.
- 🚫 A new standalone selection executable. Phase 1 stays on `oc-test-source-diff`.
