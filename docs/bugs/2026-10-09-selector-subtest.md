# Selector subtest — pop-down, file list, phone styling

**Status:** ⏳ open. Next step of phase 1. Not being applied in this pass.

**Related:**

- ℹ️ Plan: [`CODER-4.2.5-project-file-selector.md`](../plans/CODER-4.2.5-project-file-selector.md)
- ℹ️ Subtest: `examples/oc-test-source-diff.vala` `--selectors` / `--phone` / `--tablet`
- ℹ️ Row: `examples/oc-test-source-diff-selectors.vala` (`TestSelectorRow`)
- ℹ️ History list to match: `libollmchatgtk/HistoryBrowser.vala`, `resources/style.css` (`.list-chat-title` and the caption classes)

## Desktop — project pop-down

Seen on `--selectors`.

- 🔷 The first click does nothing. It does not open search.
- 🔷 The first click must flip the button into the search entry, focus it, and open the list.
- 🔷 The pop-down sits in the middle of the screen.
- 🔷 The pop-down is left aligned under the button.
- 🔷 Each row is left aligned.
- 🔷 Height uses the parent window and goes as tall as that window allows.
- 🔷 Width follows the longest row. The current width is acceptable until that measurement exists.
- 🔷 Load every project. There are not many. Do not page them.

## Desktop — file pop-down

Seen after a project is chosen.

- 🔷 The control flips into a search entry.
- 🔷 The pop-down is about five pixels wide and has no rows.
- 🔷 Build the full file selector in this subtest, not a one-page stub.
- 🔷 That is where the filesystem layout gets designed: wide pop-down, tree, history, and search results when text is typed.
- ℹ️ The empty list may be the test fetch. The full selector is still required either way.
- ℹ️ Tree contents stay in [`CODER-4.2.1`](../plans/CODER-4.2.1-tree-navigation-filedropdown.md). This bug places that tab in the subtest pop-down.

## Phone and tablet

Seen on `--phone` and `--tablet` in the desktop binary.

- 🔷 The pull-over does not look like a list. It looks like an overlay.
- 🔷 It should look like the history session list.
- 🔷 The history styling has to be in this test. It is not showing up now.
- 🔷 Tablet has the same problem as the phone.
- 🔷 The next test round for the phone is a build on Android, not `--phone` on the desktop.
- 🚫 Do not package the Android build in this pass. Record it as the following test round.
