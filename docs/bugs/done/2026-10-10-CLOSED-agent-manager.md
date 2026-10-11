# Agent manager for section visibility

**Status:** 🚫 CLOSED — user closed the redesign. It is in the tree. Not a phone pass.

**Related:** ℹ️ `docs/bugs/done/2026-10-10-CLOSED-desktop-unreachable-give-up.md`, ℹ️ `docs/plans/done/1.7-DONE-agent-management.md`

## Problem

- **🔷** One GTK object owns which sections are visible for the active agent: editor, browser, and chat.
- **🔷** The class is `Manager` in namespace `OLLMapp.Agent`, file `ollmapp/Agent/Manager.vala`. The phone and tablet window uses `OLLMapp.Android.AgentManager`.
- **🔷** When the lifecycle bug reports `client.filesd.unreachable`, this object asks Retry or Close. No Configure. Close does not quit. Close leaves Agent Pi and starts a Chatter session.
- **🚫** Do not put this in `OLLMchat.Agent`. `libollmchat` is built with no GTK dependency.
- **🚫** Do not put the dialog or the section visibility in the agent dropdown. The dropdown lists agents and applies a user pick.
- **ℹ️** Emitting `client.filesd.unreachable`, and stopping give-up from building a session itself, stay on the lifecycle bug.

## What it does

- **✔️** The desktop window creates `Agent.Manager` after the chat bar exists. `is_phone` and `is_android` stay false.
- **✔️** The Android window creates `Android.AgentManager`. `is_android` is true. `is_phone` is true only on a phone, so a tablet keeps the pane beside the chat.
- **✔️** An editor agent shows that agent's page and the pane. A phone replaces the chat with the pane. A tablet shows the pane column. The desktop widens the window.
- **✔️** A non-editor agent leaves the browser up when that page is already showing, and otherwise shows the chat. A phone always returns to the chat.
- **✔️** Leaving an editor agent hides the pane.
- **✔️** The manager creates the browser button, the editor button, and the tool toggles. On Android it also creates the chat button, visible only on a phone. The dropdown stays on the window.
- **✔️** The Android editor button mounts the editor page, then shows it.
- **✔️** `client.filesd.unreachable` shows Retry and Close. Retry emits `client.filesd.retry`. Close starts a Chatter session.

## Rejected

- **🚫** A second manager class, and a desktop subclass. Android overrides the shared manager.
- **🚫** `#if ANDROID` scattered through the manager. `is_phone` and `is_android` are construct properties.

## Attempts / changelog

- **✔️** Split from the Android remote lifecycle bug. `switch_to_session` emits `agent_deactivated` and `agent_activated` when the agent name changes.
- **✔️** The manager is constructed by both windows and owns the picker buttons, the tool strip, and the pane. Desktop build linked. Not run on a phone.

## Next

- **ℹ️** Give-up calling this dialog is `docs/bugs/done/2026-10-10-CLOSED-desktop-unreachable-give-up.md`.
