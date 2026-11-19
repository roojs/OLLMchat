# Agent Pi startup does not open the project filesystem

**Status:** ✅ closed 2026-11-19. Desktop startup calls `startup_activate_session`. Agent Pi opens the saved project tree.

## Problem

- 🔷 On desktop startup, the application has access to the file daemon and
  selects Agent Pi by default.
- 🔷 The project filesystem does not open.
- 🔷 Expected: when the desktop can use the file daemon and starts on Agent Pi,
  its project/file view opens with the window's project context.
- 🔷 Actual: Agent Pi is selected, but no project filesystem is opened.

## Evidence

- 🔷 Reported on 2026-10-27.
- ℹ️ Reproduced 2026-11-19. See Attempts.
- ℹ️ Per-window project restoration is documented in
  `docs/plans/done/2.10.4.7-DONE-active-project-file-outside-db.md`.
- ℹ️ Per-client project registration and monitoring are tracked separately in
  `docs/plans/FILES-2.10.4.8-per-client-project-notifications.md`.
- ℹ️ Coder-view follow-up work is
  `docs/plans/CODER-4.2.7-coder-view-outstanding.md`.

## Root cause

- ✔️ The saved window already has the project. `config.2.json` is
  `agent=agent-pi`, `project=/home/alan/gitlive/OLLMchat`,
  `file=examples/oc-test-source-diff.vala`.
- ✔️ 2026-11-19 08:32:21, `./build/ollmapp/ollmchat --debug`. Files daemon
  hello succeeded (`SOCKET`). The dropdown listed Agent Pi. The next line
  was `client ready agent=agent-pi project=/home/alan/gitlive/OLLMchat
  file=.../oc-test-source-diff.vala`. There was no `agent_activated`,
  `session_activated`, `session_restored`, `agent activate`, `db_projects`,
  or `file sheet shown`.
- ✔️ `Window.initialize_client` writes `win_cfg.agent` onto the empty
  session, then `Dropdown.select_only` shows that row with the selection
  handler blocked. `Factory.activate` runs only from `agent_activated`,
  `session_activated`, and `session_restored`. None of those fire.
  `activate` is what builds `CoderView`, calls `restore_active_state`, and
  opens the file sheet. The right pane stays hidden because it starts
  hidden and `Agent.Manager` shows it from those same signals.
- ✔️ Android reaches the same widgets through
  `startup_activate_session` at the end of its `initialize_client`.
  Desktop never calls it.

## Proposed fix

- 🔷 After the desktop agent signals are connected, run the same startup
  call Android uses. That emits `session_activated` and `session_restored`,
  which open the coder view and restore the window project.
- 🚫 Do not add a fallback project, force a global active project, or hide the
  missing restoration state.
- 🚫 Do not call `activate_agent` with the name already stored on the
  session. `EmptySession.activate_agent` returns without a signal when the
  name is unchanged.

#### Add — `ollmapp/Window.vala` `initialize_client`, immediately after `startup_connect_signals()`

```vala
			yield this.startup_activate_session();
```

## Attempts / changelog

- ℹ️ 2026-10-27: standalone bug created from the coder-view tail-end review.
- ℹ️ 2026-11-19: `~/.config/ollmchat/config.2.json` window row is
  `agent=agent-pi`, `project=/home/alan/gitlive/OLLMchat`,
  `file=examples/oc-test-source-diff.vala`. Files daemon pid 2084018 was
  already up. Desktop `ollmchat` was not running.
- ✔️ 2026-11-17 09:07 in `~/.cache/ollmchat/ollmchat.debug.log`: dropdown
  lists Agent Pi with filesd state `SOCKET`. About one second later
  `ProjectManager.db_projects` runs, then `restoring window config project
  path=/home/alan/gitlive/OLLMchat`, then `Folder.fetch_files` and
  `Folder.fetch_children`. Review queue is 1 file. `tests/README.md` is
  read at 09:07:57. The saved vala file is read at 09:08:12.
- ℹ️ 2026-11-19: temporary debug added, then removed. The desktop binary
  links `/lib/x86_64-linux-gnu/liboccoder.so`, so the coder-library lines
  never appeared. The app lines did.
- ✔️ 2026-11-19 08:34:25 after `yield activate_session_and_sync_ui()`:
  `ProjectManager.db_projects`, then `session_activated` and
  `session_restored` for `agent-pi`, then `restoring window config project
  path=/home/alan/gitlive/OLLMchat`, then `Folder.fetch_files` and
  `Folder.fetch_children`. That fetch pair is the file sheet loading the
  project tree.
- ℹ️ 2026-11-19: `activate_session_and_sync_ui` is
  `startup_activate_session`. `connect_agent_factory_signals` is
  `startup_connect_signals`. Same two startup calls.
- ✔️ 2026-11-19 08:36:59, same sequence on the build with the debug lines
  removed. The window title is OLLMchat, the header agent is Agent Pi, the
  project button reads OLLMchat, and the file sheet is open on the project
  tree (`android`, `pixiewood-wraps`, `config`, and the rest).

## Next

- ✅ Closed. No open work on this bug.
