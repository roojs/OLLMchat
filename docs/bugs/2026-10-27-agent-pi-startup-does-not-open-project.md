# Agent Pi startup does not open the project filesystem

**Status:** ⏳ open — reported; reproduction and root cause pending

## Problem

- 🔷 On desktop startup, the application has access to the file daemon and
  selects Agent Pi by default.
- 🔷 The project filesystem does not open.
- 🔷 Expected: when the desktop can use the file daemon and starts on Agent Pi,
  its project/file view opens with the window's project context.
- 🔷 Actual: Agent Pi is selected, but no project filesystem is opened.

## Evidence

- 🔷 Reported on 2026-10-27.
- ℹ️ The failure has not yet been reproduced with debug logging.
- ℹ️ Per-window project restoration is documented in
  `docs/plans/done/2.10.4.7-DONE-active-project-file-outside-db.md`.
- ℹ️ Per-client project registration and monitoring are tracked separately in
  `docs/plans/FILES-2.10.4.8-per-client-project-notifications.md`.
- ℹ️ Coder-view follow-up work is
  `docs/plans/CODER-4.2.7-coder-view-outstanding.md`.

## Root cause

- 🔷 ⏳ Unknown.
- 💩 ⏳ Check whether the window config contains a saved project path at
  startup.
- 💩 ⏳ Check whether project restoration runs after the file daemon becomes
  available.
- 💩 ⏳ Check whether selecting Agent Pi mounts `CoderView` without applying
  the window's project context.

## Proposed fix

- 🔷 ⏳ No fix proposal until the startup sequence is reproduced and the
  missing step is identified.
- 🚫 Do not add a fallback project, force a global active project, or hide the
  missing restoration state.

## Attempts / changelog

- ℹ️ 2026-10-27: standalone bug created from the coder-view tail-end review.
- ℹ️ No product code or debug instrumentation changed.

## Next

- 🔷 ⏳ Reproduce on desktop with the file daemon available and Agent Pi as
  the startup agent.
- 💩 ⏳ Capture the file-daemon state, selected agent, saved window project
  path, project-restoration call, and resulting `CoderView` state.
- 🔷 ⏳ Compare startup with manually selecting Agent Pi or manually opening a
  project after startup.
- 🔷 ⏳ Document the confirmed root cause and a concrete fix before changing
  product code.
