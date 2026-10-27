# CODER-4.2.7 Coder view outstanding work

**Status:** ⏳ proposed — semantic search, filesystem-notification integration,
and mainline testing remain

> **Do not update `docs/plans/CODER-1.0-summary.md` again for this sub-plan**
> until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**.
Proposed Vala code must follow `docs/coding-standards.md`.

**Completed baseline:**

- ℹ️ The coder screen, file navigation, source view, markdown preview, and diff
  review are in `liboccoder` on mainline.
- ℹ️ `examples/oc-test-source-diff.vala` builds the library implementation.
- ℹ️ The completed design and implementation plans are archived under
  `docs/plans/done/`.

---

## Purpose

- 🔷 Keep one open tracker for the remaining coder/source-view work.
- 🔷 ⏳ Add semantic file search as a third file-navigation tab.
- 🔷 ⏳ Refresh folder and file navigation from filesystem notifications for
  the project open in this window.
- 🔷 ⏳ Test the coder screen from mainline on desktop and Android.
- 🔷 ⏳ Record any failures found during that testing as concrete follow-up
  bullets here.

---

## Semantic search

- 🔷 ⏳ Add a third tab for semantic search alongside `Tree` and `Recent`.
- 🔷 The third tab uses semantic search rather than replacing the existing
  filename filtering.
- 🔷 `Tree` and `Recent` keep their current name-based search behavior.
- ℹ️ The existing server call is `Codebase.search` on `ollmfilesd`.
- ℹ️ `liboctools/CodebaseSearch/Request.vala` already sends that call.
- 🔷 ⏳ Confirm the third-tab label, result-row content, and empty/error states
  during implementation review.

---

## Filesystem notification integration

- ℹ️ Open-project monitoring, daemon file-state refresh, shallow-scan fallback,
  and per-client event routing belong to
  [`FILES-2.10.4.8`](FILES-2.10.4.8-per-client-project-notifications.md).
- 🔷 Each window has one open project. This coder view consumes the events
  routed for that window's project.
- 🔷 ⏳ Refresh the affected folder and file lists when the filesystem plan
  reports a structural change.
- 🔷 ⏳ Keep the selected file and folder stable when an unrelated directory
  changes.
- 🔷 ⏳ Verify create, remove, rename, move, and content changes without
  restarting the daemon or reopening the project.

---

## Mainline testing

- 🔷 ⏳ Build and run `examples/oc-test-source-diff` from mainline.
- 🔷 ⏳ Desktop:
  - Project selection and file navigation use the `liboccoder` screen.
  - Tree and Recent open files and preserve their current filters.
  - Markdown files switch between rendered and source views.
  - Pending changes show the diff review bar.
  - Accept, reject, reset, save, and diff resync behave correctly.
- 🔷 ⏳ Android phone:
  - Project and file navigation work on the packaged mainline screen.
  - An opened source file starts in view mode.
  - Tap and long-hold behavior does not raise the keyboard unexpectedly.
  - Pinch changes source font size.
  - Source syntax highlighting is present.
  - The phone footer opens browser, editor, and chat correctly.
- 🔷 ⏳ Android tablet:
  - The project pull-over and file overlay use the mainline screen.
  - Folder drill-down, file opening, markdown preview, and diff review work.

---

## LLM notes

- 🚫 Do not reopen the archived smoke-to-mainline migration plans.
- 🚫 Do not replace Tree or Recent filename matching with semantic search.
- 🚫 Do not design project monitors or filesystem scanning in this plan.
  `FILES-2.10.4.8` owns that work.
- 🚫 Do not create another source-view backlog document. Add newly found
  mainline test failures to this plan.
