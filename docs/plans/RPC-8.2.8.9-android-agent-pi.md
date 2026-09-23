# 8.2.8.9 — Android Agent Pi when the desktop environment is live

**Status:** **PROPOSED**

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 10

**Depends on:**

- Phone connection flow, user-closed 2026-09-23 (Check stays up, row survives restart)
- [`RPC-8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) — Android `ProjectManager`, HTTPS hello
- [`RPC-8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md) — `ChatDesktopInterface`, phone stack, tablet column

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`. Layout is chosen below. Hunks wait until this plan is approved.

---

## Purpose

- **🔷** After Check succeeds, Agent Pi is available on the phone.
- **🔷** That same moment makes Agent Pi the active agent.
- **🔷** On startup, if the desktop environment is already live, Agent Pi is the agent the session starts on.
- **🔷** Phone flips among browser, text editor, and chat from the bottom bar (where the browser button and model selector already sit).
- **🔷** While chat is occurring, the chat button cycles the thinking icon (`weather-fog-symbolic`): one wavy line, then two, then three. Not a spinner.
- **🔷** Editor chrome is two bars, then the text, then review at the bottom when review is active.
- **ℹ️** Desktop Linux already registers Agent Pi at window setup (`ollmapp/Window.vala`). This plan does not change that.
- **ℹ️** Only Agent Pi. Not Code Assistant. Not Skill Runner. Parent decision in [`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md).
- **ℹ️** Still one desktop environment. Home, office, and an online proxy host are [`8.2.8`](RPC-8.2.8-filesd-connections-ui.md) Phase 11.

---

## Current behaviour

- **ℹ️** Android `register_default_agents()` adds Chatter only (`ollmapp/ChatUserInterface.vala`).
- **ℹ️** Android `OllmchatWindow` never constructs `OLLMcoder.AgentPi.Factory`.
- **ℹ️** `AgentPi.Factory.activate` casts the window to `ChatDesktopInterface`, mounts `SourceView` on `tab_view()`, then `schedule_pane_update(true)`.
- **ℹ️** Phone `schedule_pane_update(true)` replaces the chat: `chat_widget.view_stack` child `"pane"`. `false` puts `"chat"` back. That is the same swap the browser globe uses.
- **ℹ️** Tablet `schedule_pane_update` only shows or hides the right column. Chat stays on the left.
- **ℹ️** `liboccoder/meson.build` `occoder_src` already lists `AgentPi/Factory.vala` and `SourceView.vala` for the Android host. This plan does not start by inventing a second library.

---

## When Agent Pi turns on

Live means the desktop-environment row is approved, Enabled is on, and the HTTPS hello succeeded.

- **🔷** Check success (already connects when Enabled is on) then registers the factory if it is missing, then selects Agent Pi on the current session.
- **🔷** Startup hello success does the same select, so a phone that already has a live desktop environment opens on Agent Pi.
- **🔷** No live desktop environment: stay on Chatter. Do not show Agent Pi in the agent list.
- **💩** Turning Enabled off, or Remove, leaves the current session on Agent Pi until the user picks another agent. Do not force Chatter mid-edit. Confirm before building that.
- **💩** A later Check on an already-registered factory only selects Agent Pi again. It does not construct a second factory.

---

## Bottom bar — flip browser, editor, chat

The phone does not keep a left-rail toggle and does not split the screen. The bottom bar (`OLLMchatGtk.ChatBar`) already holds the browser toggle and the model selector. That row is where you change what fills the screen.

- **🔷** Three pickers: browser, text editor, chat.
- **🔷** One of them is the visible page. Picking another replaces it. Chat, browser, and editor each take the whole content area.
- **🔷** While the session is running, the chat picker shows that thinking mark, even if the editor or the browser is the visible page. That is how you see that chat is occurring without leaving the file.
- **🔷** The mark is `weather-fog-symbolic`, the thinking icon on the model dropdown (`libollmchatgtk/List/ModelUsageFactory.vala`). It is three wavy lines. Each frame hides lines: show one, then two, then three, then back to one.
- **ℹ️** The icon is one Adwaita symbolic, not three files. Extract each wavy line into its own icon (the other lines hidden) and cycle those on the chat picker while `session.is_running`.
- **💩** Idle chat picker uses the full three-line thinking icon, static. Only the running state cycles the frames.
- **🔷** `⏳` Later, same bar on phone and tablet: pickers sit on the right, model selector moves fully left.
  - Phone: three pickers (browser, text editor, chat).
  - Tablet: two pickers (browser, code). Chat is the left column, so it is not a picker.
- **ℹ️** Today `ChatBar.tool_button_box` is on the left and the model dropdown follows it. The right-hand picker row is the later pass, not the first slice.

---

## Editor chrome

When the text editor is the visible page, the column is four bands, top to bottom.

- **🔷** The normal OLLMchat header stays on top.
- **🔷** Under that, a second bar: project dropdown and file dropdown. Those already exist inside the coder (`ProjectDropdown`, `FileDropdown`).
- **🔷** Then the text area.
- **🔷** When review is active, the review bar sits at the bottom of the text area. Not in the first slice unless review is already showing there on desktop.
- **ℹ️** Desktop review footer is `liboccoder/Diff/ReviewBar.vala`. Phone reuses that band. It does not invent a second review widget.

---

## Tablet

- **🔷** Browser and code are the same kind of choice as on the phone. Chat stays in the left column ([`8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md)).
- **🔷** Those two buttons sit on the right of the left column's bottom bar, not on its left edge.
- **🔷** `⏳` Selecting Agent Pi still fills the right column with the editor. The buttons choose browser vs code in that column.
- **ℹ️** The shared "pickers on the right, model on the left" pass is the later decision in the bottom-bar section. First tablet slice only moves browser and code to the right of that left-column bar.

---

## Phases

1. **🔷** `⏳` Register `OLLMcoder.AgentPi.Factory` on Android after a successful hello, and select it.
2. **🔷** `⏳` Startup with an already-live desktop environment selects Agent Pi before the first session paint.
3. **🔷** `⏳` Phone bottom bar: browser, text editor, chat. Chat picker cycles the thinking-icon lines while the session runs.
4. **🔷** `⏳` Editor page: header, project and file bar, text area. Review band when review is active.
5. **🔷** `⏳` Tablet: browser and code buttons on the right of the left column's bottom bar.
6. **🔷** `⏳` Later: pickers on the right and the model selector fully left. Phone three buttons, tablet two.

---

## LLM notes

- **🚫** Code Assistant and Skill Runner on Android.
- **🚫** Changing Linux Agent Pi registration.
- **🚫** A left-rail editor toggle.
- **🚫** A phone split (editor over a short chat strip) and a draggable sash (`Gtk.Paned`).
- **🚫** A spinner on the chat picker. The indicator is `weather-fog-symbolic`, one wavy line at a time.
- **🚫** More than one desktop environment. That is parent Phase 11.
