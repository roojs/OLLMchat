# File sheet opens at the project, not the open file

**Status:** ⏳ logged. Not started.

## Problem

- 🔷 Opening the tablet file sheet (the look-around view) always starts at the project root.
- 🔷 When a file is already open in the editor, the sheet should open on that file's folder.
- 🔷 The open file should be highlighted in the file list.
- 🔷 That highlight is not a selection. The row is not the selected file, and opening the sheet does not act as if that file was chosen.
- 🔷 With no file open, the sheet still starts at the project.

## Evidence

- ℹ️ `FileOverlay.activate` sets `level` to the project and loads that folder. `examples/oc-test-source-diff/FileOverlay.vala`.
- ℹ️ The editor's open file is `SourceView.current_file`. `CoderView` hears `file_changed` and only updates the header label. `examples/oc-test-source-diff/CoderView.vala`.
- ℹ️ The file grid uses `Gtk.SingleSelection` with `autoselect` off. A selected row is the keyboard target. `examples/oc-test-source-diff/FileList.vala`.

## Next

- ⏳ Open the sheet while a file is open and land on its folder, with that file highlighted and not selected.
