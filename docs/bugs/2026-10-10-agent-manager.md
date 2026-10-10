# Agent manager for section visibility

**Status:** ⏳ desktop window constructs `Agent.Manager` after picker buttons and tool toggles exist; Android still owns its own pane updates

**Related:** ℹ️ `docs/bugs/2026-10-08-android-remote-connection-lifecycle.md`, ℹ️ `docs/plans/done/1.7-DONE-agent-management.md`

## Problem

- **🔷** One GTK object owns which sections are visible for the active agent: editor, browser, and chat.
- **🔷** A dropped desktop connection is not the Enabled switch. The connection code retries, then reports that the desktop is unreachable. It does not hide the editor or start a session.
- **🔷** That report is answered here. The dialog matches the model-unavailable alert and offers Retry and Close. It has no Configure action. Close does not quit the app.
- **🔷** Retry asks the window to run the connection attempt again. Close leaves Agent Pi, hides the editor, and starts a Chatter session.
- **🔷** The class is `Manager` in namespace `OLLMapp.Agent`, file `ollmapp/Agent/Manager.vala`.
- **🚫** Do not put this in `OLLMchat.Agent`. `libollmchat` is built with no GTK dependency.
- **🚫** Do not put the dialog or the section visibility in `AgentDropdown`. The dropdown lists agents and applies a user pick.

## Evidence

- **✔️** `libollmchat/meson.build` says the library has no GTK dependency. `OLLMchat.Agent` lives in that library. `Adw.AlertDialog` and `schedule_pane_update` are GTK.
- **✔️** Both main windows are `OLLMapp` and already implement `schedule_pane_update`. Desktop uses `WindowPane`. Android uses `OllmchatWindow.pane_stack`.
- **✔️** `AgentPi.Factory.activate` and `deactivate` call `schedule_pane_update` on the window. `OllmchatWindow` and desktop `Window` also listen to `agent_activated` and hide the pane themselves.
- **✔️** `History.Manager` stores the session and emits `agent_activated` and `agent_deactivated`. `switch_to_session` now emits those signals when the agent name changes. That code is in the tree and has not been tried on the phone.
- **✔️** `OllmchatWindow.reconnect` tries three passes, then sets `UNREACHABLE`, shows a banner, and switches to Chatter itself. There is no Retry or Close choice.
- **ℹ️** `docs/plans/done/1.7-DONE-agent-management.md` is the old agent picker. It is not a visibility manager.

## Root cause

- **✔️** Nothing owns section visibility. Factories and both windows each show and hide panes. A connection failure in the window then builds a session because there is no manager to answer the drop.

## Duties

The desktop window constructs the manager after the picker buttons and tool toggles exist, then the manager subscribes. `ChatUserInterface` is unchanged. Android still has its own pane updates.

- **🔷** `History.Manager.agent_activated` and `session_restored`. An editor factory shows `{factory}-widget`. A non-editor factory keeps the browser when that page is already visible, and otherwise hides the pane. `editor_picker.visible` stays on each window. The phone "always hide" branch stays in `ollmapp/android/OllmchatWindow.vala` because `is_tablet` is private. The browser, editor, and chat picker clicks are not signals on the shell, so this draft does not subscribe to them.
- **🔷** `History.Manager.agent_deactivated` for an editor factory hides the pane. Same pane line as `AgentPi.Factory.deactivate`, `OLLMcoder.AgentFactory.deactivate`, and `Skill.Factory.deactivate`. Creating the source view, loading projects, the skill progress strip, and `can_queue(false)` stay in the factories.
- **🔷** `ChatBar.tool_toggle` and each tool's `UiWidgets.show_view`. Taken from desktop `Window` tool chrome. Turning a tool on shows its page. Turning it off hides the pane only while the editor strip is down. `show_view` while that strip is down only flips the toggle, so `tool_toggle` does the show.
- **🔷** `ChatDesktopInterface.notification` method `client.filesd.unreachable` asks Retry or Close. Retry emits `client.filesd.retry`. Close starts a Chatter session the way `OllmchatWindow.reconnect` does today. That session change emits `agent_deactivated`, which is what hides the editor. No Configure. Close does not quit.
- **💩** The manager creates the desktop browser button, editor button, and tool toggles, and shows or hides those strips. The agent dropdown stays on the window. Android pickers stay on `android/OllmchatWindow.vala`.
- **💩** Desktop `Window` constructs `Agent.Manager` after those buttons exist. Its `schedule_pane_update` forwards to the manager. The window's `tool_toggle`, `show_view`, and pane hide on `agent_activated` are gone. Picker clicks still call `schedule_pane_update`. Factories still call it through `ChatDesktopInterface`.
- **🚫** Do not add `Agent/Manager.vala` to the Android sources. It uses desktop `WindowPane`.

## Proposed changes

- **💩** Desktop window constructs the manager and forwards `schedule_pane_update`. Desktop tool and agent pane listeners that the manager owns are removed.
- **🔷** ⏳ Android pane updates, and stop the factories calling `schedule_pane_update` once the manager's own handlers cover that path on both builds.
- **🔷** ⏳ On give-up, `reconnect` only sets `UNREACHABLE` and emits `client.filesd.unreachable`. The subscription answers that. The window notification handler runs `reconnect` again for `client.filesd.retry`.

## Attempts / changelog

- **✔️** Split from the Android remote lifecycle bug. The lifecycle tree already contains the connection fixes and the `switch_to_session` agent signals.
- **💩** Drafted the class at the real path. Not in the Meson sources. No window constructs it.
- **💩** Replaced the poke methods with subscriptions to signals the shell already has. The class docblock states when the browser, editor, and chat are shown and hidden. The `section` signal added on `ChatUserInterface` was removed. That file is compiled, and this draft does not change it.
- **💩** Desktop `ollmchat` constructs the manager after the picker buttons and tool toggles exist. `Window.schedule_pane_update` forwards to it. The desktop `tool_toggle`, `show_view`, and `agent_activated` pane updates are removed. Desktop build linked.

## Next

- **🔷** ⏳ Android pane updates stay on `android/OllmchatWindow.vala` until the manager can show that pane without desktop `WindowPane`.
- **🔷** ⏳ Stop `reconnect` from switching session itself, and emit `client.filesd.unreachable` for the manager's notification subscription.
