# CODER-4.2.5 Project and file selector

**Status:** proposed. Phase 1 desktop project selector is confirmed. Phase 2 is the desktop file selector. Phase 3 is the Android review. Phase 4 is file content search, and it is held off.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**.

**Related:**

- ℹ️ [`CODER-4.2.1-tree-navigation-filedropdown.md`](CODER-4.2.1-tree-navigation-filedropdown.md) — older tree note. The tree is Phase 2 of this plan.
- ℹ️ Today: `liboccoder/ProjectDropdown.vala`, `liboccoder/FileDropdown.vala`, `liboccoder/SearchableDropdown.vala`.
- ℹ️ Smoke app: `examples/oc-test-source-diff.vala`. Classes live in `examples/oc-test-source-diff/`.
- ℹ️ Phone history today: `ollmapp/android/OllmchatWindow.vala` and `libollmchatgtk/HistoryBrowser.vala`.
- ℹ️ Phone source-view trouble, partly worked: [`docs/bugs/2026-09-29-android-source-view-phone.md`](../bugs/2026-09-29-android-source-view-phone.md).

---

## Purpose

- 🔷 Phase 1 is the desktop project selector. Phase 2 is the desktop file selector. Phase 3 is an Android review. Phase 4 is file content search.
- ✅ Phase 1 is confirmed.
- 🔷 ✔️ marks code that is in the smoke app and not approved yet.
- 🔷 Never do status theatre. Do not mark an item done, rewrite Status, or report ticks in place of the behavior. A tick waits until that behavior is what the running app does.
- 🔷 Phase 2.1 is the file selector already in the smoke app.
- 🔷 Next is Phase 2.2. Empty folders, single-child folder chains, and the other controls that are not search.
- 🔷 Phase 2.3 is search. Phase 3 and Phase 4 wait.

---

## Phase 1 — Desktop project selector ✅

### Run

From the repo root. The window loads projects from filesd. No file-pair arguments.

```
ninja -C build examples/oc-test-source-diff
./build/examples/oc-test-source-diff --selectors
```

- ℹ️ `--selectors` is the desktop pop-down.

### Desktop

- ✅ Resting state is a flat button. A folder icon, then the project name.
- ✅ No project: the button says `Select project`. The file button is not shown.
- ✅ A click turns the button into a search entry, focuses it, and opens the pop-down.
- ✅ The pop-down is left aligned under the button. `place()` anchors it. Width stays 280.
- ✅ Height fills the space under the row and stays inside the window.
- ✅ The pop-down closes when the window stops being the active one.
- ✅ Each row is a title and a path, left aligned.
- ✅ Choosing a project moves to the file control and opens the file pop-down.
- ✅ Every project is loaded. They are not paged.
- ℹ️ `examples/oc-test-source-diff/ProjectSelector.vala`. The smoke row only hosts it.

### Recent and All

- ✅ A Recent / All bar on the desktop pop-down.
- ✅ Default is Recent.
- ✅ Recent shows projects that contain a viewed file, newest file view first.
- ✅ Projects with no viewed file under them are left out.
- ✅ If none have a viewed file, Recent says `No recent projects`.
- ✅ All lists every project by name, A to Z, ignoring case.
- ✅ Search still applies on top of whichever choice is showing.
- ✅ The bar does not take keyboard focus. The search entry keeps the keys.
- ℹ️ Project rows in `filebase` do not use `last_viewed`. Those values stay 0.
- ℹ️ `load_projects_from_db` sets the loaded folder from `MAX(last_viewed)` of files under that path. It does not write the project row.
- ✅ Opening the project list again always shows Recent.
- ✅ That open scrolls to the top.
- ✅ That open does not highlight a row.
- ✅ Choosing a project does not change this list. Recent stays the list the server already sent.

---

## Phase 2 — Desktop file selector

`FileSelector` is on the desktop smoke row. Phase 2.1 is what that app already does. Phase 2.2 is the rest that is not search. Phase 2.3 is search.

### 2.1 — Smoke app

A grey tick is behavior that app already does.

#### Pop-down

- ✔️ The file control is a flat button until activated, same resting shape as the project button.
- ✔️ After a file is chosen, desktop shows the path relative to the project. The label ellipsizes at the start.
- ✔️ Mouse over shows the full path.
- ✔️ A click turns the button into a search entry and opens a wide pop-down.
- ✔️ The resting file button shows a file icon. The project button shows a folder icon.
- ✔️ The tabs are Tree and Recent. Tree is the primary tab. Opening the pop-down shows Tree.
- ✔️ Three pixels sit under those titles, before the list.
- ✔️ The second tab is titled Recent.
- ✔️ Opening the pop-down shows Tree, and that show starts `FolderTreeStore.load`.
- ✔️ The Search tab is off this pop-down.
- ✔️ The Tree tab is two panes. Detail is under Tree. The lists start empty.
- ✔️ Recent loads files that have a last-view time. Empty copy is `No recent files`.
- ✔️ The pop-down is inset from the left and right of the window, and tall enough to cover the source view.
  - ℹ️ Popover padding and shadow sit outside the content width, so that extra comes off the width.
- ✔️ With no project, a spacer keeps the header history button on the right. The file control takes that gap once a project is chosen.
- ✔️ Choosing a file closes the pop-down and moves focus to the source view.
- ✔️ The pop-down closes when the window stops being the active one.
- ℹ️ `examples/oc-test-source-diff/FileSelector.vala`.

#### Recent

- ✔️ An empty search shows the recent files, up to 50.

#### First step

Widgets first, then the lists behind them. `FolderTreeStore.load` asks the file server for child folders and appends them. It does not clear the store.

- ✔️ Replace the Tree note with two panes: a folder tree on the left and a file list on the right. `examples/oc-test-source-diff/FileTree.vala`.
- ✔️ The left holder is `FolderTreeStore`. It lists folders only. The shape follows RooTerm `TreeNodes`, with path as the key instead of uuid. `examples/oc-test-source-diff/FolderTreeStore.vala`.
- ✔️ While a folder request is waiting on the file server, the folder pane shows a spinner. It stays up for the folders asked for under that same load.
- ✔️ The top `FolderTreeStore` owns a path-to-folder hash map and a flat list of every folder. There is no uuid map.
- ✔️ Each folder's children are a `FolderTreeStore` for that segment. The same folder object sits in the segment, the path map, and the flat list. Add and remove go through the top store and signal `items-changed` for that one position.
- ✔️ A `Gtk.TreeListModel` binds the top list and, for each folder, that folder's child store. One search filter is used on the top list and on every child list. The filter currently keeps every row.
- ℹ️ `ProjectFiles.refresh` clears its page and loads another. This store does not follow that.
- ✔️ The right holder is a `GLib.ListStore` of `File` for the folder that is selected. It starts empty.
- ℹ️ On the client today there is no folder tree. `ProjectList.path_map` is project roots only. `ProjectManager.file_cache` is path to `FileBase` for rows fetched one at a time, files and folders mixed. `Folder.children` stays empty. `ProjectFiles` is one dropdown page from `Folder.fetch_files`, not a kept tree. `Folder.fetch_children` is named on `FolderFiles` and does not exist.

#### Existing stores

Reference only. Each one is a `GLib.ListModel` with an array behind it, except the settings page, which uses `GLib.ListStore` directly. Client and daemon each have their own copy of the named classes.

| Store | Holds | Used for |
| --- | --- | --- |
| `FolderFiles` | `FileBase`. Files and subfolders of one folder. | Daemon folder tree, as `Folder.children`. The client copy stays empty. |
| `ProjectList` | `Folder`. Project roots only. | The project selector. Subfolders are not kept here. |
| `ProjectFiles` | `ProjectFile`. One flat list. | File dropdown and file search. Not a tree. |
| `ReviewFiles` | `FileWithHistory`. | Files waiting for approval. |
| `GLib.ListStore` of `Folder` | `Folder`. | Settings projects page only. Not a named store class. |

#### Tree

Folders on the left, files on the right. The file server is queried for each side after the first step. File content search is Phase 4.

- ✔️ The left side is a folder tree. It does not list files.
- ✔️ That tree is expanded.
- ✔️ Clicking a folder asks the file server (''Folder.fetch_dir'') for that folder's files and shows them on the right.
- ✔️ A selected folder's files are a three-column grid: name with a type icon, size, and modified time. Names are alphabetical, ignoring case.

#### Other controls

- ✔️ This selector reads and shows files. It does not create them.
- ✔️ Folder names are alphabetical, ignoring case, through the name sorter on each filter. That order does not copy the old file-dropdown sorts.

### 2.2 — Empty folders and other controls

Outstanding Phase 2 work that is not search.

- ✔️ The tree shows the selected project. Choosing another project removes the previous project's folders, then loads the new one.
- 🔷 ⏳ An empty folder uses a greyed folder icon, not the normal one, and a light grey colour.
- ✔️ A folder that contains only one child, and that child is a folder, is not its own row.
  - 🔷 That chain is one row.
  - 🔷 The label joins the folder names with `/`.
  - 🔷 `A/B` when `A` holds only `B`.
  - 🔷 `A/B/C` when the chain is one folder deeper.
  - 🔷 `scalable/apps` when `scalable` holds only `apps`.
  - 🔷 The row stops at the first folder that contains anything other than a single child folder.
  - 🔷 Children of that last folder stay under the combined row.
  - ✔️ Clicking the row selects that last folder and shows its files on the right.
  - 💩 The combined row uses the empty-folder grey icon when the chain has no files.
- 🔷 ⏳ The pop-down header is three slots.
  - 🔷 The left slot is two icon buttons.
  - 🔷 Collapse all.
  - 🔷 A tree filter beside it.
  - 🔷 That filter hides empty folders and gitignored folders.
  - 🔷 Build directories are empty and gitignored, so the filter hides them.
  - 🔷 The tree filter has its own icon.
  - 🔷 Middle is Tree and Recent.
  - 🔷 Right is the type filter.
  - 🔷 On Recent, the two left buttons are hidden.
  - 🔷 The left slot keeps its width, so Tree and Recent do not move or shrink.
- 🔷 ⏳ Collapse all collapses the folder tree.
- 🔷 ⏳ A type filter, document versus code. It sits in the right slot.
  - ℹ️ Daemon `File.is_documentation()` is markdown or plain text. Other languages are code.
- 🔷 ⏳ With no search text, the folder that contains the current file is the one selected, and that file sits about halfway down the right list. A load currently selects nothing and scrolls to the top.
- 🔷 ⏳ A click on the left tree selects that folder.
- 🔷 ⏳ A second click on that same folder deselects it and clears the file list.
- 🔷 ⏳ Refresh is a progressive update. A notification adds or removes the one path that changed. It does not clear the map, the flat list, or the segments, and it does not walk the tree again.
  - ℹ️ Today `scan_end` drops the project path from `loaded` and calls `load` on that project. `append` skips a path already stored, so the rows are not deleted and replaced. Deeper folders already in `loaded` are not fetched again. A folder that disappeared stays in the tree. The first open still walks every folder.
  - ℹ️ When `loading` goes false, `FileTree` calls `name_sorter.changed(DIFFERENT)`. That re-sorts every segment, and the list is hidden for the whole load. That full re-render is not the design. Leave it until the progressive update above.
- 🔷 ⏳ Refresh is a last line of defence.
  - ℹ️ The server is meant to stay current.
  - ℹ️ File watch on the active project is not implemented.
  - ℹ️ Refresh covers that watch missing a change.

### 2.3 — Search

- 🔷 ⏳ Typing in the desktop search entry does not filter Recent yet. That search stays on Recent and orders matches by how recent they are. It does not jump to Tree.
- 🔷 ⏳ Search on the Tree tab is a global file search. The file server returns those files in a separate query. That result marks folders on the existing `FolderTreeStore`. It does not build a second tree and it does not refill the hash map.
  - ℹ️ RooTerm `TreeNodes` is the reference. The root owns `by_uuid` and `flat`. Each row's `children` is another `TreeNodes`. Search walks `by_uuid`, then `filter.changed` on those same lists. This store uses the path map where RooTerm uses `by_uuid`. Non-matches are hidden there. Here they stay and go grey.
- 🔷 ⏳ Folders with no matching file under them stay in the left tree. A folder is not empty when a match is inside it, including inside a subfolder.
- 🔷 ⏳ Clicking a folder while searching shows that folder's matching files on the right, on that same grid.
- 🔷 ⏳ With no folder selected during a search, the right list is every matching file. Each row has the path relative to the project underneath the name.

---

## Phase 3 — Android review

Review the pull-over on a device after Phase 2. `--phone` and `--tablet` on the desktop binary are only a stand-in.

```
./build/examples/oc-test-source-diff --phone
./build/examples/oc-test-source-diff --tablet
```

- ℹ️ Do not pass `--phone` and `--tablet` together.
- 🔷 ⏳ The same window on an Android build, not only `--phone` on the desktop.

### Project pull-over

- ✔️ A click opens the pull-over. It does not open a search field.
- ✔️ Top bar: back arrow, then the title `Projects`.
- ✔️ Recent / All is on that page.
- ✔️ Current selection is text under the bar. The list sits under it. Search is at the bottom.
- ✔️ Back, or choosing a row, closes the pull-over.
- ✔️ Choosing a project does not open the file pull-over.
- 🔷 Tablet uses this pull-over. It does not use the desktop pop-down.
- 🔷 ⏳ Which edge the pull-over comes from. The tablet case is the open one.

### File pull-over

- ✔️ The file page is one list. It does not copy the desktop tabs.
- ✔️ Phone shows the file name only. Tablet shows the path relative to the project, ellipsized at the start.
- ✔️ Tablet mouse-over shows the full path. Phone does not.
- ✔️ The project button has a maximum width. A shorter name stays narrower than that cap. The file button takes the rest of the row.

### Phone file navigation

The phone does not use the desktop tree. It browses one folder at a time.

- 🔷 ⏳ The list is the files and folders in the current folder. The first folder is the project root.
- 🔷 ⏳ Clicking a folder drills into that folder.
- 🔷 ⏳ The next folder slides in from the side.
- 🔷 ⏳ Swipe sideways to move back and forward through the folders already opened.

### Tablet file navigation

The tablet follows the desktop tree. It does not use the phone drill-down.

- 🔷 ⏳ Folders on the left, files on the right.
- 🔷 ⏳ Normal use is a swipe down the tree to find the file and view that folder.
- 🔷 ⏳ Searching puts the keyboard over about half the screen. The tree and the file list share the height that is left.

### Chat history

- 🔷 ⏳ Phone and tablet chat history moves onto this same pull-over.
  - The title stays Chat history. That list is sessions, not files.
  - Search moves from the top to the bottom.
  - Opening history must not focus search and must not raise the keyboard.
  - ℹ️ Today `history_toggle_button` grabs `history_browser.search_entry` as soon as history is shown.
- ℹ️ Product `SourceView` header comes after the smoke window.

---

## Phase 4 — File content search

Held off. Not the next step, and not a tab on the file pop-down.

- 🔷 Search that looks inside file contents waits until after the desktop file list and the Android review.
- 🔷 ⏳ That search is its own piece of work. It does not replace the tree name filter.

---

## LLM notes

- 🚫 Do not remove the header history button in this plan. The view toggle that replaces it is [`CODER-4.2.4-source-view-markdown-preview.md`](CODER-4.2.4-source-view-markdown-preview.md).
- 🚫 Desktop chat history stays where it is.
- 🚫 Do not leave the folder tree for `CODER-4.2.1`. Phase 2 shows folders on the left and files on the right.
- 🚫 Do not put files on the left tree. Do not bind that tree to `Folder.children`, and do not name the holder `FolderStore`. The holder is `FolderTreeStore`.
- 🚫 Do not clear `FolderTreeStore` and reload it on a notification. Update the path that changed.
- 🚫 Do not filter a client-held copy of the whole tree. Ask the file server for the folders and for the file results separately.
- 🚫 Do not give the phone the desktop tabbed pop-down or the two-pane tree. Phone file navigation is one folder at a time.
- 🚫 Do not give the tablet the phone drill-down. Tablet file browsing follows the desktop tree.
- 🚫 Do not auto-open the file pull-over after a project pick on phone or tablet.
- 🚫 No second smoke app. This stays on `oc-test-source-diff`.
- 🚫 Do not bring back `examples/oc-test-source-diff-selectors.vala`.
- 🚫 Do not start the Android review before the desktop file work.
- 🚫 Do not put a Search tab on the file pop-down. Tree name matches stay on Tree. Recent name matches stay on Recent. Content search is Phase 4.
- 🚫 No wildcard matching (`*` or `?`) in this pass.
- 🚫 Do not copy `ProjectFiles.cached_search` sort orders, and do not use `ProjectFiles.get_recent_list`.
- 🚫 No status theatre. Do not add ✔️ or ✅, rewrite the Status line, or answer with what was ticked, unless the running app already does that thing.
