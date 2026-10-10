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
- **✔️** `ProjectSelector` logs the Recent and All click, the toggle, and the list counts. Run `./build/examples/oc-test-source-diff --debug --selectors`. The log is `~/.cache/ollmchat/com.roojs.ollmchat.test-source-diff.debug.log`.

## Evidence

- **✔️** 10:59:21 click All: `recent notify active=false`, then `all toggled active=true`. 10:59:21 click Recent: `all toggled active=false`, then `recent notify active=true`. 10:59:22 click All again. No `focus leave` line, so the pop-down stayed open.
- **✔️** None of those clicks logged `recent=... shown=...`. That line is the only call to `filter.changed`.
- **✔️** Vala compiled `project_recent` as a private field. `project_selector_set_project_recent` assigns the field and does not emit `notify`. The property is not installed on the class, so `notify["project-recent"]` never runs.

## Root cause

- **✔️** The toggle updates the flag. The list refresh is only connected to a notify that this private property does not emit.

## Proposed changes

- **💩** `project_recent` is a real property (`public` get, `private` set) so the existing notify handler runs `filter.changed` and swaps the sorter.

## Next

- **🔷** ⏳ Click All again with `--debug` and confirm a `recent=false` line whose `shown` count is the full project total.
