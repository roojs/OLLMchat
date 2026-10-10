# Project All filter does not change the list

**Status:** ⏳ debug is in the selector; the click has not been logged yet

## Problem

- **🔷** Recent is the default and shows projects that contain a viewed file.
- **🔷** All should show every project, A to Z, ignoring case. Search still applies.
- **🔷** Clicking All does not change the list.

## Attempts / changelog

- **💩** Swapped the sorter and called `filter.changed` from `project_recent`. No visible change.
- **💩** Deferred the focus-leave pop-down so the click was not eaten. No visible change.
- **💩** Treated the search entry's text child as still inside the entry. No visible change.
- **✔️** `ProjectSelector` now logs the Recent and All click, the toggle, `project_recent`, viewed versus total versus shown, and which widget has focus when the pop-down considers closing. Run `./build/examples/oc-test-source-diff --debug --selectors`. Lines also go to `~/.cache/ollmchat/oc-test-source-diff.debug.log`.

## Next

- **🔷** ⏳ Click All once and read those lines before changing the filter again.
