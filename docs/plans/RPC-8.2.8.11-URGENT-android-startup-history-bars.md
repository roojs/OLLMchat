# 8.2.8.11 URGENT — Android startup hello, history, and bars

**Status:** **URGENT** · Phases 1–6 **⏳**

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 11

**Split from:** [`RPC-8.2.8.9-DONE-android-agent-pi.md`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phases 3–8. That plan is closed. Phase 1 here was Phase 3 there, through Phase 6 here = Phase 8 there.

**Depends on:**

- Phone connection flow, user-closed 2026-09-23 (Check stays up, row survives restart)
- [`RPC-8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) — `FilesdClient.State`, Agent Pi on `SOCKET` / `LIVE`, Check listen
- [`RPC-8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md) — `ChatDesktopInterface`, phone stack, tablet column

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`. Code fences after each phase is agreed, or when the existing bullets are enough to apply.

---

## Purpose

- **🔷** Leftover Android Agent Pi work from [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md). That file closed after state + visibility.
- **🔷** This ticket is **URGENT**.
- **🔷** Each phase below is the whole design for that slice. Read that phase on its own.
- **ℹ️** State enum, dropdown filter, Manager `LIVE` listen, and Check reconnect are already in tree ([`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phases 1–2).
- **ℹ️** Still one desktop environment. Home, office, and an online proxy host are [`8.2.8`](RPC-8.2.8-filesd-connections-ui.md) Phase 13.
- **ℹ️** Remote `bash` is [`8.2.8.10`](RPC-8.2.8.10-android-remote-bash.md). Not this plan.

---

## Phase 1 — Startup hello (`⏳`)

- **🔷** `⏳` On startup, if the desktop environment is already live, the session starts on Agent Pi. Same switch as [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phase 2, before the first session paint.
- **🔷** That check is a short-timeout hello to the file server. The desktop may be on another network. Do not sit on the normal RPC wait.
- **ℹ️** The probe is `RPC-Daemon.hello`, not an ICMP ping.
- **ℹ️** `OllmchatWindow.initialize_client` already sends that hello when the row is approved and enabled. Failure today is `Alert.show` ("File server: …") and startup continues. `Client.call_timeout_seconds` defaults to 120.
- **🔷** Hello succeeds → state `LIVE` (remote) or `SOCKET` (local, empty `url`), then [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phase 2's Agent Pi visibility. Remote `LIVE` still switches the session.
- **🔷** Startup hellos the remote URL when `url != ""` and state is `ENABLED`, `LIVE`, `UNREACHABLE`, or `SOCKET`.
- **🔷** Hello fails or times out:
  - State `UNREACHABLE` (Phase 1 on [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md)). Do not add Agent Pi. Do not show it in the agent list.
  - Start a new Chatter session. Do not keep the open chat on Agent Pi.
  - Header banner: the desktop environment is unavailable.
- **🔷** That notice is `Banner.show` on `window.notification`.
  - **ℹ️** `Banner.show` is the dismissible header banner (`Adw.Banner` on desktop, `tool_error_banner`).
  - **ℹ️** `Alert.show` is a modal OK dialog. This notice is not that dialog.
  - **ℹ️** `ActivityBanner` is scan and index progress. Not this notice.
  - **ℹ️** Android today turns both `Banner.show` and `Alert.show` into `Adw.AlertDialog`. This notice still uses `Banner.show`. Android must show that as a banner, not a dialog.

---

## Phase 2 — History when Agent Pi is off (`⏳`)

- **🔷** `⏳` An Agent Pi session cannot be restored while Agent Pi is not in the agent list.
- **🔷** The history row stays in the list. It shows the agent name and "disabled". Tapping it does nothing until that agent is available again.
- **ℹ️** The row today is the title plus `display_info` (model and message count). `agent_name` is stored and not shown (`SessionPlaceholder.display_info`, `HistoryBrowser`).
- **ℹ️** `Manager.load_sessions` drops a row whose model is missing (`find_model_by_name` returns null). A missing agent is different: it rewrites `agent_name` to `just-ask` in memory only and still lists the row. That rewrite is the bug. Do not hide the row, and do not retarget it to Chatter.

---

## Phase 3 — Phone bottom bar (`⏳`)

The phone does not keep a left-rail toggle and does not split the screen. The bottom bar (`OLLMchatGtk.ChatBar`) already holds the browser toggle and the model selector. That row is where you change what fills the screen.

- **ℹ️** Phone `schedule_pane_update(true)` replaces the chat: `chat_widget.view_stack` child `"pane"`. `false` puts `"chat"` back. That is the same swap the browser globe uses.
- **ℹ️** Today `ChatBar.tool_button_box` is on the left and the model dropdown follows it. Moving the pickers to the right is Phase 6.
- **🔷** `⏳` Three pickers: browser, text editor, chat.
- **🔷** One of them is the visible page. Picking another replaces it. Chat, browser, and the editor each take the whole content area.
- **🔷** While the session is running, the chat picker shows the thinking mark, even if the editor or the browser is the visible page. That is how you see that chat is occurring without leaving the file.
- **🔷** The mark is `weather-fog-symbolic`, the thinking icon on the model dropdown (`libollmchatgtk/List/ModelUsageFactory.vala`). It is three wavy lines. Each frame hides lines: show one, then two, then three, then back to one. Not a spinner.
- **ℹ️** The icon is one Adwaita symbolic, not three files. Extract each wavy line into its own icon (the other lines hidden) and cycle those on the chat picker while `session.is_running`.
- **🔷** When the session is idle, the chat picker is a speech bubble. The thinking icon is only the running state.

---

## Phase 4 — Editor chrome (`⏳`)

When the text editor is the visible page, the column is four bands, top to bottom.

- **🔷** `⏳` The normal OLLMchat header stays on top.
- **🔷** Under that, a second bar: project dropdown and file dropdown. Those already exist inside the coder (`ProjectDropdown`, `FileDropdown`).
- **🔷** Then the text area.
- **🔷** When review is active, the review bar sits at the bottom of the text area. Not in this slice unless review is already showing there on desktop.
- **ℹ️** Desktop review footer is `liboccoder/Diff/ReviewBar.vala`. The phone reuses that band. It does not invent a second review widget.

---

## Phase 5 — Tablet bar (`⏳`)

- **ℹ️** Tablet `schedule_pane_update` only shows or hides the right column. Chat stays on the left ([`8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md)).
- **🔷** `⏳` Browser and code are the same kind of choice as on the phone. Those two buttons sit on the right of the left column's bottom bar, not on its left edge.
- **🔷** Selecting Agent Pi still fills the right column with the editor. The buttons choose browser vs code in that column.
- **ℹ️** Moving the model selector fully left, on phone and tablet together, is Phase 6. This phase only moves browser and code to the right of that left-column bar.

---

## Phase 6 — Pickers on the right (`⏳`)

- **🔷** `⏳` Later, the same bar on phone and tablet: pickers sit on the right, and the model selector moves fully left.
  - Phone: three pickers (browser, text editor, chat).
  - Tablet: two pickers (browser, code). Chat is the left column, so it is not a picker.

---

## Suggested order

1. **⏳** Phase 1 — startup hello (short timeout, `UNREACHABLE`, `Banner.show`, Chatter if miss)
2. **⏳** Phase 2 — history rows for a missing agent stay listed, marked disabled, cannot restore
3. **⏳** Phase 3 — phone bottom bar: browser / editor / chat + thinking icon
4. **⏳** Phase 4 — editor chrome (header, project/file dropdowns, text, review bar)
5. **⏳** Phase 5 — tablet bar: browser and code on the right of the left-column bar
6. **⏳** Phase 6 — pickers on the right, model selector fully left

---

## LLM notes

- **🚫** Code Assistant and Skill Runner on Android.
- **🚫** Changing Linux Agent Pi registration.
- **🚫** A left-rail editor toggle.
- **🚫** A phone split (editor over a short chat strip) and a draggable sash (`Gtk.Paned`).
- **🚫** A spinner on the chat picker. Running is `weather-fog-symbolic`, one wavy line at a time. Idle is a speech bubble.
- **🚫** More than one desktop environment. That is parent Phase 13.
- **🚫** An ICMP ping. Reachability is `RPC-Daemon.hello`.
- **🚫** Waiting the default 120s RPC timeout when the file server is off-network.
- **🚫** `Alert.show` for desktop-environment unavailable.
- **🚫** Turning the saved connection to `DISABLED` because one startup hello missed. That miss is `UNREACHABLE`.
- **🚫** Rewriting a missing `agent_name` to `just-ask`, or hiding that history row.
- **🚫** Registering in-process `Bash` on Android. That is [`8.2.8.10`](RPC-8.2.8.10-android-remote-bash.md).
- **🚫** Reopening [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) for these hunks.
