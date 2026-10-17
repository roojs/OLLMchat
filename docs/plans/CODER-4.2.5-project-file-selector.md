# CODER-4.2.5 Project and file selector

**Status:** proposed. Phase 1 is confirmed. Phase 2.3 search is done. Phase 2.4 is signed off. Phase 3 is the Android review of the smoke window. Phase 3.5 is the semantic file search, taken out of Phase 4. Phase 4 is the rest of the open later work.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**.

**Related:**

- ℹ️ [`CODER-4.2.1-tree-navigation-filedropdown.md`](CODER-4.2.1-tree-navigation-filedropdown.md) — older tree note. The tree is Phase 2 of this plan.
- ℹ️ [`docs/bugs/done/2026-10-13-FIXED-folder-tree-filter-slow.md`](../bugs/done/2026-10-13-FIXED-folder-tree-filter-slow.md) — folder tree load. Closed. The current open is 74ms.
- ℹ️ Today: `liboccoder/ProjectDropdown.vala`, `liboccoder/FileDropdown.vala`, `liboccoder/SearchableDropdown.vala`.
- ℹ️ Smoke app: `examples/oc-test-source-diff.vala`. Classes live in `examples/oc-test-source-diff/`.
- ℹ️ Phone history today: `ollmapp/android/OllmchatWindow.vala` and `libollmchatgtk/HistoryBrowser.vala`.
- ℹ️ Phone source-view trouble, partly worked: [`docs/bugs/2026-09-29-android-source-view-phone.md`](../bugs/2026-09-29-android-source-view-phone.md).

---

## Purpose

- 🔷 Phase 1 is the desktop project selector. Phase 2 is the desktop file selector. Phase 3 is an Android review. Phase 3.5 is the semantic file search. Phase 4 is open later work.
- ✅ Phase 1 is confirmed.
- 🔷 ✔️ marks code that is in the smoke app and not approved yet.
- 🔷 Never do status theatre. Do not mark an item done, rewrite Status, or report ticks in place of the behavior. A tick waits until that behavior is what the running app does.
- 🔷 Phase 2.1 is the file selector already in the smoke app.
- 🔷 Phase 2.2 is in the smoke app.
- ✅ Phase 2.3 search is done. The no-folder search and restoring the current file on clear are Phase 4.
- ✅ Phase 2.4 is signed off. The folder list and the file list are overlays on the editor. The folder bar's left arrow is still to do, and it stays hidden on desktop.
- 🔷 Phase 3 is the Android review. Phase 3.5 follows that. Phase 4 waits.

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

`FileSelector` is on the desktop smoke row. Phase 2.1 is what that app already does. Phase 2.2 is the rest that is not search. Phase 2.3 is search. Phase 2.4 replaces the popovers.

### 2.1 — Smoke app

A grey tick is behavior that app already does.

#### Pop-down

- ✔️ The file control is a flat button until activated, same resting shape as the project button.
- ✔️ After a file is chosen, desktop shows the path relative to the project. The label ellipsizes at the start.
- ✔️ Mouse over shows the full path.
- ✔️ A click turns the button into a search entry and opens a wide pop-down.
- ✔️ The resting file button shows a file icon. The project button shows a folder icon.
- ✔️ The tabs are Tree and Recent. Tree is the primary tab. Opening the pop-down shows Tree.
- ✔️ Six pixels sit under those titles, before the list, matching the space above them.
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

- ✔️ Replace the Tree note with two panes: a folder tree on the left and a file list on the right. `examples/oc-test-source-diff/FolderTree.vala`, `examples/oc-test-source-diff/FileList.vala`, `examples/oc-test-source-diff/FileListStore.vala`.
- ✔️ The left holder is `FolderTreeStore`. It lists folders only. The shape follows RooTerm `TreeNodes`, with path as the key instead of uuid. `examples/oc-test-source-diff/FolderTreeStore.vala`.
- ✔️ While a folder request is waiting on the file server, the folder pane shows a spinner. It stays up for the folders asked for under that same load.
- ✔️ The top `FolderTreeStore` owns a path-to-folder hash map and a flat list of every folder. There is no uuid map.
- ✔️ Each folder's children are a `FolderTreeStore` for that segment. The same folder object sits in the segment, the path map, and the flat list. Add and remove go through the top store and signal `items-changed` for that one position.
- ✔️ A `Gtk.TreeListModel` binds the top list and, for each folder, that folder's child store. One search filter is used on the top list and on every child list. The filter currently keeps every row.
- ℹ️ `ProjectFiles.refresh` clears its page and loads another. This store does not follow that.
- ✔️ The right holder is `FileListStore`, a `GLib.ListModel` of `File` for the folder that is selected. The rows from the file server are that model. They are not copied into a `GLib.ListStore`. It starts empty.
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

Folders on the left, files on the right. The file server is queried for each side after the first step. Semantic file search is Phase 3.5.

- ✔️ The left side is a folder tree. It does not list files.
- ✔️ That tree is expanded.
- ✔️ A folder with no child folder has no expander.
- ✔️ Clicking a folder asks the file server (''Folder.fetch_dir'') for that folder's files and shows them on the right.
- ✔️ That file list opens at the top.
- ✔️ A selected folder's files are a three-column grid: name with a type icon, size, and modified time. Names are alphabetical, ignoring case.
- ✔️ A symlink whose stored target is a folder is not listed. A symlink to a file is.
- ℹ️ ''fetch_dir'' copies stored rows. It does not read the filesystem. Modified time is the stored ''last_modified''.

#### File size

The Size column shows the stored byte size. The directory scan records ''STANDARD_SIZE'' on the file row. ''fetch_dir'' copies that stored value. It does not read the filesystem. An existing project picks the size up on the next scan.

#### Other controls

- ✔️ This selector reads and shows files. It does not create them.
- ✔️ Folder names are alphabetical, ignoring case, through the name sorter on each filter. That order does not copy the old file-dropdown sorts.

### 2.2 — Empty folders and other controls ✔️

In the smoke app. Search is Phase 2.3.

- ✔️ The tree shows the selected project. Choosing another project removes the previous project's folders, then loads the new one.
- ✔️ Choosing a project opens the file tree. Choosing the project already shown opens that tree again and does not load it.
- ✔️ An empty folder has no folder icon. Its name binds the folder's `css-classes`, which is `dim-label` when the folder has no files, so the text is light grey. Child folders do not change that. The tooltip binds the folder's `tooltip`, the full path.
- ✔️ A folder that contains only one child, and that child is a folder, is not its own row.
  - 🔷 That chain is one row.
  - 🔷 The label joins the folder names with `/`.
  - 🔷 `A/B` when `A` holds only `B`.
  - 🔷 `A/B/C` when the chain is one folder deeper.
  - 🔷 `scalable/apps` when `scalable` holds only `apps`.
  - 🔷 The row stops at the first folder that contains anything other than a single child folder.
  - 🔷 A file in that folder stops the chain. `libochf` has files beside `Param`, so the row stays `libochf`.
  - ℹ️ The folder load query counts files and folders sitting directly inside each row. Gitignored children are not counted, so a folder that only holds them is empty. The tree reads those counts on the folder. It does not read the directory and does not send another call.
  - 🔷 Children of that last folder stay under the combined row.
  - ✔️ Clicking the row selects that last folder and shows its files on the right.
  - ✔️ A combined row has no folder icon. Its name and tooltip bind those same properties on the last folder, so the name is that light grey when the last folder has no files.
- ✔️ The top-level folder is displayed. Critical. Selecting it shows the files in that folder. The project is that row, and it is expanded.
- ✔️ The pop-down header is three slots.
  - ✔️ The left slot is two icon buttons. Each has 3 pixels on its right.
  - ✔️ Collapse all. It is a normal button and does not stay down. The icon is ''document-send-symbolic''. It folds every open row under the project. The project row stays open and has no expander.
  - ✔️ A ghost button beside it. It starts hiding. The icon is a crossed eye while hiding and an eye while showing. It does not stay pressed.
  - ✔️ While hiding, the ghost hides a gitignored folder, and a folder with no files and no child folders. A folder that only holds gitignored children is empty.
  - ✔️ Build directories are empty and gitignored, so hiding them drops them.
  - ✔️ The eye shows those folders again.
  - ✔️ A gitignored folder that is shown has a conceal icon beside its name.
  - ✔️ Middle is Tree and Recent.
  - ✔️ Right is the type filter. The slot holds document and code buttons. The one that is down hides folders and files of the other type. A second click on it shows every type again.
  - ✔️ On Recent, the two left buttons are hidden.
  - ✔️ The left slot keeps its width, so Tree and Recent do not move or shrink.
- ✔️ Collapse all collapses the folder tree under the project. The project row stays open.
- ✔️ A type filter, document versus code. It sits in the right slot.
  - ℹ️ Daemon `File.is_documentation()` is markdown or plain text. Other languages are code.
- ✔️ A click on the left tree selects that folder.
- ✔️ A second click on that same folder deselects it and clears the file list.
- ✔️ With no folder selected, the right pane says ''Select a folder''. A selected folder with no files says ''No files''.
- ℹ️ A scan that adds a file does not update an open tree. The file list is loaded when a folder is selected, and it is not kept on screen. Closing the pop-down and opening it again is the refresh. A progressive update, one path at a time, is later. Performance of the full load is fine.

### 2.3 — Search ✅

The desktop search entry drives whichever tab is showing. Tree is the first filter. Recent is after that. An empty search is the normal tree again.

- ✔️ Typing in the desktop search entry applies that text to the tab that is showing.
  - ✔️ Tree applies it to the folder tree.
  - ✔️ Recent applies it to the recent list. `Folder.fetch_files` with `recent` set returns viewed files whose name contains the text, newest `last_viewed` first, at most 50. There is no separate recent call, and there is no offset.
  - ✔️ It does not switch tabs.
- ✔️ Flipping Tree / Recent applies the same text to the tab that is now showing.
- ✔️ Tree search matches file names and folder names. The test ignores case. No `*` or `?`.
  - ✔️ A folder stays when its own name contains the text.
  - ✔️ A folder stays when a file under it contains the text, at any depth.
  - ✔️ A folder stays when a folder under it contains the text. That is the parent walk, so the path to a match stays on screen.
  - ✔️ Every other folder is hidden.
  - ✔️ An empty search is the normal tree. The ghost and the type filter still apply.
- ✔️ The first search step gets the matching files. A folder is keyed by `(int) FileBase.id`, not by the folder name or the path.
  - ℹ️ A non-empty `Folder.fetch_files` query matches the filename, ignoring case. The parent ids are the project folders in `folder_map`, including a folder linked in through an alias. The reply is those folder ids packed as native-endian int32 bytes. A file contributes its parent id. A folder contributes its own id. More than 100 matches fails with `RpcErrorCode.TOO_MANY_RESULTS` and sends no rows. An empty query stays a file page. The tree does not hold a second copy of every file.
  - ℹ️ `FolderTreeStore.id_map` is id to folder. The walk starts at a file's `parent_id` or a folder's `id`, then each `parent_id`. It does not look up a path.
- ✔️ More than 100 matches: do not filter the tree. The right list shows ''too many results''. The current file button keeps the open file.
- ✔️ An empty reply resets the tree. The right list shows ''no results''. The current file button keeps the open file.
- ✔️ 100 matches or fewer: take those folder ids and `set` each to `true`. Walk each parent. Stop when that parent is already on the map. Otherwise `set` it to `false` and set that folder's `is_show_empty`, so the bound name is light grey. The caller notifies `css-classes`. The filter keeps a row whose id is on that map. A later reply calls `search_reset` before that fill.
- ✔️ Recent search stays on Recent. It orders matches by how recent they are. It does not jump to Tree.
- ✔️ Clicking a folder while searching shows that folder's matching files on the right, on that same grid. The file list filters on the client. A file stays when its path, under the project, contains the search text, ignoring case. A folder named like the search shows every file in it. An empty search shows every file the type filter allows.
- ℹ️ With no folder selected, the right list stays ''Select a folder''. Showing every match there, and restoring the current file when the search clears, are Phase 4.

#### Visible folders

The visible folders are a `Gee.HashMap<int, bool>`. The key is `(int) FileBase.id`. `true` means a file in that folder matches, or the folder name matches. `false` means that folder has no match and is a parent of one, so the path stays and the name is light grey. A missing key is hidden. Each search clears the map, then `set`s each match id to `true`. The parent walk stops when that id is already on the map. Any other parent is `set` to `false`, and that folder's `is_show_empty` is set. The caller notifies `css-classes`. The filter keeps a row when `has_key` is true for that cast. Folder ids are not expected to exceed an `int`. `ProjectFiles.update_from_recursive` already casts folder ids to `int` for a hash lookup.

- ℹ️ `Gee.ArrayList.contains` scans from the start until it finds the id. `has_key` hashes the id and checks that bucket.
- ✔️ The map holds only those ids. It does not hold the folder. The filter already has the folder it is testing.
- 🚫 The filter does not walk children to decide a row. `filter.changed` already walks every segment. A walk inside the match function is the slow path.
- 🚫 A folder with no key is hidden. A parent whose value is `false` stays, and its name is light grey. Folders that are not on a path to a match are not left on screen.
- 🚫 A folder whose name matches does not keep every child folder. A child stays only when that child matches, or a file or folder under that child matches. RooTerm's ancestor-name test in the filter does the opposite for hosts.
- 🚫 Do not change this map to numbers here. A count in brackets on the tree is Phase 4.

### 2.4 — Overlays on the editor ✅

The popovers go. Windowing with them is nasty. The project list and the file list are drawn on the editor instead.

- ✔️ No popover. Both lists are overlays on the editor area.
- ✔️ The folder overlay is the size of the old popover, 280 wide, on the left of the editor. A click on the editor outside that list closes it. The desktop folder bar has no close button.
- ✔️ The file overlay covers the editor. It is the one that needs a close control.
- ✔️ Hide the document and code buttons. Leave that filter code in place. The right slot does not keep an empty gap.
- ✔️ That slot is a process-stop icon. It closes the file overlay.
- 🔷 ⏳ The folder bar has the same left arrow. It is hidden on the desktop.
- ℹ️ On the Android phone that same arrow is the collapse control, and the folder one is shown there. Desktop does not show it.

---

## Phase 3 — Android review

Review the pull-over on a device after Phase 2. `--phone` and `--tablet` on the desktop binary are only a stand-in.

```
./build/examples/oc-test-source-diff --phone
./build/examples/oc-test-source-diff --tablet
```

- ℹ️ Do not pass `--phone` and `--tablet` together.
- 🔷 ⏳ The same window on an Android build, not only `--phone` on the desktop.
  - ℹ️ `scripts/android/build-source-diff-apk.sh` packages this smoke window. It does not replace the chat APK.

### File navigation classes

- ℹ️ `FileNav` is the base. `FileOverlay` is the desktop sheet. `FilePullout` is the phone and tablet page.
- ℹ️ `form` is the string `desktop`, `phone`, or `tablet` on `FileNav`, `ProjectSelector`, `SelectorPull`, and `CoderView`.
- 🔷 ⏳ `FileNav` does not build widgets.
  - The button, the lists, and the type buttons are drawn by `FileOverlay` and `FilePullout`.
- 🔷 ⏳ The form factor is an enum.
  - Replace the `form` string.

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

The phone does not use a tree. A tree does not work on that screen. It shows one folder level at a time.

From the top of the page:

- ℹ️ Sketch only. Not code to apply. Names are an example.

```
Root. No left arrow. No place line. Tree.
Folders, then files. A root row is one line.

+--------------------------------------+
| OLLMchat                          X  |
|  Tree          Recent                |
|--------------------------------------|
| [folder] android                     |
| [folder] docs                        |
| [file]   meson.build                 |
| [ Search files                     ] |
+--------------------------------------+

Inside docs. Left arrow. Place line is docs.
A row's second line is the path from the
project, including its own name.

+--------------------------------------+
| <  OLLMchat                       X  |
|    docs                              |
|  Tree          Recent                |
|--------------------------------------|
| [folder] plans                       |
|          docs/plans                  |
| [file]   BUILD.md                    |
|          docs/BUILD.md               |
| [ Search files                     ] |
+--------------------------------------+

Recent. A file at the project root is one
line. A short path keeps the name. A long
path drops the name, then keeps the first
folder and ellipsizes the rest.

+--------------------------------------+
| OLLMchat                          X  |
|  Tree          Recent                |
|--------------------------------------|
| [file] meson.build                   |
| [file] FileNav.vala                  |
|        examples/…                    |
| [ Search files                     ] |
+--------------------------------------+

Tablet. Same top, same filters, search at
the bottom. Left is folders only. Right is
the files of that level.

+--------------------------------------------------+
| OLLMchat                                      X  |
|  Tree          Recent                            |
|--------------------------------------------------|
| [folder] android     | [file] Android.vala       |
| [folder] docs        | [file] meson.build        |
|                      |                           |
| [ Search files                                 ] |
+--------------------------------------------------+
```

- 🔷 ⏳ The top row is the left arrow, the place in the tree, and an X.
  - The left arrow is only there when the list is below the project root.
  - The lead text is the project name. At the root of OLLMchat that line is OLLMchat.
  - The place line is the path relative to the project. At the root that line is not shown. Inside `docs` it is `docs`.
  - The X is on the right. It closes the file picker.
  - The left arrow goes up one directory. From `docs` it returns to the project root.
  - The back key does the same as the left arrow. It goes up one level. It does not close the picker.
- 🔷 ⏳ Under that row are two filters, Tree and Recent.
- 🔷 ⏳ The list for the chosen filter sits under those filters.
- 🔷 ⏳ Search sits at the bottom, the same place as on the project page.
  - Tree is the one-level folder list.
  - Recent is the recent files.
- 🔷 ⏳ The first level is the project root.
  - Folders in that folder come first.
  - Files in that folder come after the folders.
- 🔷 ⏳ The folders are one load, and that load stays in memory.
  - Opening a folder does not ask for the folders again.
  - ℹ️ `FolderTreeStore.load` is that load. The phone reads the kept segments.
- 🔷 ⏳ Clicking a folder drills into that one level.
  - Its child folders come first.
  - Its files come after those folders.
- 🔷 ⏳ A row is an icon and a basename. The basename ellipsizes.
  - Below the project root, the second line is the path relative to the project, including the item's own name. `plans` reads `docs/plans`. `BUILD.md` reads `docs/BUILD.md`.
  - The same line is used for a deep folder and for a search result.
  - When the line is too long, drop the item's own name first. The basename is already the title.
  - If it is still too long, keep the first folder under the project and ellipsize the remainder. `examples/oc-test-source-diff/FileNav.vala` becomes `examples/…`. The first folder stays. The middle goes.
  - A row at the project root has no second line.
  - A folder has a folder icon.
  - A file has a file icon.
- 💩 ⏳ A file row shows its size in brackets after the basename, for example `BUILD.md (4 KB)`. Not decided.
- 🔷 ⏳ The next folder slides in from the side.
- 🔷 ⏳ Swipe sideways to move back and forward through the folders already opened.
- ℹ️ The smoke page still draws `FolderTree` above `FileList`. That is not this list.

### Tablet file navigation

The tablet uses the same navigation as the phone. The difference is where the files sit.

- 🔷 ⏳ The top row, Tree and Recent, and the search box at the bottom are the same as the phone.
- 🔷 ⏳ The left side is the one-level folder list. It does not show files.
- 🔷 ⏳ The right side shows the files of that level.
- 🔷 ⏳ Clicking a folder on the left drills into that folder. The left list becomes its child folders. The right list becomes its files.
- 🔷 ⏳ The left arrow and the back key go up one directory, the same as on the phone.

### Chat history

- 🔷 ⏳ Phone and tablet chat history moves onto this same pull-over.
  - The title stays Chat history. That list is sessions, not files.
  - Search moves from the top to the bottom.
  - Opening history must not focus search and must not raise the keyboard.
  - ℹ️ Today `history_toggle_button` grabs `history_browser.search_entry` as soon as history is shown.
- ℹ️ Product `SourceView` header comes after the smoke window.

---

## Phase 3.5 — Semantic file search

Taken out of Phase 4. The file search is semantic. The index and the call already exist, so this phase is small. Phase 3 is still next.

- 🔷 ⏳ The file search uses semantic search. It does not read file text to find matches.
- ℹ️ `Codebase.search` on `ollmfilesd` is that call. `liboctools/CodebaseSearch/Request.vala` already sends it.
- 🔷 It does not replace the tree name filter. Tree and Recent keep matching names.
- 🔷 It is not a tab on the file list. The Search tab stays off.

---

## Phase 4 — Open

Not the next step. Phase 3 is next. Phase 3.5 follows that.

- 🔷 ⏳ With no folder selected during a search, the right list is every matching file. Each row has the path relative to the project underneath the name.
- 🔷 ⏳ Clearing the search returns to the folder that contains the current file, with that file about halfway down the right list. A load with no search still selects nothing and opens at the top. This only matters with the no-folder search above.
- 🔷 ⏳ A number in brackets next to a tree row. The visible map would store numbers instead of bools. Think about it. Do not do it in Phase 2.
- ℹ️ The first open of a project holds the file dialog while the folders load. A second open is already fast. We might have that scan send notifications and show a progress bar on the file dialog. We might leave it.
- ℹ️ Semantic file search is Phase 3.5. It is not in this phase.

---

## LLM notes

- 🚫 Do not remove the header history button in this plan. The view toggle that replaces it is [`CODER-4.2.4-source-view-markdown-preview.md`](CODER-4.2.4-source-view-markdown-preview.md).
- 🚫 Desktop chat history stays where it is.
- 🚫 Do not leave the folder tree for `CODER-4.2.1`. Phase 2 shows folders on the left and files on the right.
- 🚫 Do not put files on the left tree. Do not bind that tree to `Folder.children`, and do not name the holder `FolderStore`. The holder is `FolderTreeStore`.
- 🚫 Do not add a progressive refresh in this plan. A new file from a scan does not update the open tree. Opening the pop-down again is the refresh.
- 🚫 Do not filter a client-held copy of the whole tree. Ask the file server for the folders and for the file results separately.
- 🚫 Do not give the phone the desktop two-pane tree or `FolderTree`. Phone file navigation is one level: folders, then files. A click drills into that folder only. The phone page does have Tree and Recent filters under the title row. The X closes. The left arrow and the back key go up one directory.
- 🚫 Do not give the tablet the desktop tree. It uses the phone drill-down. The left list is folders only. The right list is the files of that level. Search stays at the bottom.
- 🚫 Do not auto-open the file pull-over after a project pick on phone or tablet.
- 🚫 No second smoke app. This stays on `oc-test-source-diff`.
- 🚫 Do not bring back `examples/oc-test-source-diff-selectors.vala`.
- 🚫 Do not start the Android review before the desktop file work.
- 🚫 Do not put a Search tab on the file pop-down. Tree name matches stay on Tree. Recent name matches stay on Recent. Semantic file search is Phase 3.5. Do not scan file text for it.
- 🚫 No wildcard matching (`*` or `?`) in this pass.
- 🚫 Search visibility is not a stamp on the folder, and not a set of paths. It is a `Gee.HashMap<int, bool>` of `(int) FileBase.id`. Above 100 matches, the tree is not filtered. Numbers in that map are Phase 4.
- 🚫 Do not build the no-folder search, or restore the current file when search clears, in Phase 2.4. Both are Phase 4.
- 🚫 Do not keep the project list or the file list as a popover. Phase 2.4 draws them on the editor.
- 🚫 Do not delete the document and code filter. Hide those buttons. The right slot is the file overlay's process-stop icon.
- 🚫 Do not read file size off disk in ''fetch_dir''. The scan stores it on the file row.
- 🚫 Do not copy `ProjectFiles.cached_search` sort orders, and do not use `ProjectFiles.get_recent_list`.
- 🚫 No status theatre. Do not add ✔️ or ✅, rewrite the Status line, or answer with what was ticked, unless the running app already does that thing.
