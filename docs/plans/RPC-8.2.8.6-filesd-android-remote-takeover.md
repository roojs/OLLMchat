# 8.2.8.6 — Remote file connection: Android takeover + tablet shell

**Status:** **PROPOSED** — design only; code proposals not yet written

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Split from:** [`RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) Phase E.

**Depends on:**

- [`RPC-8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) — desktop Check / `reconnect` / Linux takeover (Phases C–D)
- [`RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) — `OLLMrpc.Client.http`, `ProjectManager.replace_rpc` + `notification`
- [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) Phase 1 — Android Connections UI + `FileConnectionAdd.request()`

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Replace the `OLLMfiles.ProjectManager` stub so an approved + enabled file connection talks to remote `ollmfilesd` over HTTPS.
- **🔷** Android startup: when `url != "" && enabled && approved`, HTTPS `replace_rpc` as [`8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) §1, then `yield rpc.connect(hello)` with **no** `ClientBoot`.
- **🔷** Compile **full** `liboccoder` on Android (same sources as desktop). Implication is meson + deps, not a second agent API.
- **🔷** Do **not** register occoder agent factories on Android in this plan (Agent Pi / Code Assistant / Skill Runner). Later.
- **🔷** Android `OllmchatWindow` implements `OLLMchat.ChatDesktopInterface`.
  - Phone: browser and code editor use today's globe pattern (`chat_widget.view_stack` swap).
  - Tablet: double pane — chatter | browser-or-editor (one right slot). Device class, not a width breakpoint. Landscape only. No portrait phone shell on tablet. Split is **not** a resizable paned.
- **ℹ️** Operator nginx doc: [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md).

---

## Current behaviour

- **ℹ️** `android_poc` links reduced `occoder` (`AgentPi/Skill.vala` + `SkillSet.vala` only) via `liboccoder/meson.build` `is_android_cross` + `subdir_done()`.
- **ℹ️** `OLLMfiles.ProjectManager` is a stub in `ollmapp/android/AndroidToolTypes.vala`. `libocfiles` is not in the Android `subdir()` list.
- **ℹ️** Phone shell: `Gtk.Stack` (`startup` / `chat` / `history`). Browser globe toggles `chat_widget.view_stack` (`"chat"` vs tool name). No right pane.
- **ℹ️** Desktop split is `ollmapp/WindowPane.vala` (`Gtk.Paned` + `Adw.ViewStack tab_view`). Showing the pane **grows** the window. Not in `android_poc` sources.
- **ℹ️** `AgentPi.Factory.activate` casts the window to `ChatDesktopInterface` and `tab_view()` to `Adw.ViewStack`, then mounts `OLLMcoder.SourceView`. Android window is `ChatUserInterface` only.
- **ℹ️** [`8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) `FileConnectionRow` / `ConnectionsPage.render_approved` already call `win.project_manager`, `win.notification`, `win.window_config()`.

---

## Design decisions

- **🔷** Same HTTPS client construction as desktop: `Transport.Cert.ensure()` then `tls.certificate` / `tls.trust` on `HttpClient`.
- **🔷** Full liboccoder compiles on Android. Registration of those factories stays off.
- **🔷** `ChatDesktopInterface` is the host surface. No separate Android `activate` path.
- **🔷** Browser and editor share one secondary surface. Phone: full-stack swap. Tablet: chat stays visible, secondary is the other column.
- **🔷** Tablet vs phone is a **device class**, not a live wide/narrow cutoff. A tablet does not flip to the phone shell when rotated.
- **🔷** Tablet UI is landscape only. Do not show a vertical (portrait) phone layout on tablet.
- **🔷** Tablet split is a **fixed** two-column layout. Not a user-draggable sash (`Gtk.Paned` / desktop `WindowPane`).
- **💩** Detect tablet with the platform's tablet signal (Android `smallestScreenWidthDp` / `sw600dp`, or equivalent Gdk screen layout). Confirm the exact API when coding.
- **💩** Lock tablet orientation in the Android manifest / activity (`landscape` / `sensorLandscape`) so the phone stack never appears there.
- **💩** Tablet `tab_view()` is still an `Adw.ViewStack` so factory casts match desktop. Columns are a `Gtk.Box`, not `WindowPane`.
- **ℹ️** `register_default_agents()` is Chatter only (`ChatUserInterface`). Coder factories are a separate desktop `Window.initialize_client` block. Leave that block off Android.

---

## Phase 1 — Real `ProjectManager` + full `liboccoder` (`⏳`)

- **🔷** `⏳` `libocfiles` in the Android `subdir()` list. `ocfiles_vapi_dep` + `--pkg=ocfiles` on `android_poc`.
- **🔷** `⏳` Drop the `is_android_cross` Skill-only `subdir_done()` in `liboccoder/meson.build`. Build the same `occoder_src` as desktop (GtkSourceView, tree-sitter, `SourceView`, factories).
- **🔷** `⏳` Drop / replace the stub in `ollmapp/android/AndroidToolTypes.vala`.
- **ℹ️** Cross-build picks up `tree-sitter`, `sqlite3`, `gmodule-2.0`, `gtksourceview-5`.
- **⏳** Code proposals — after design sign-off.

---

## Phase 2 — HTTPS takeover at Android startup (`⏳`)

- **🔷** `⏳` `OllmchatWindow.initialize_client` (Android): when `filesd_client.url != "" && enabled && approved`, mint the device `Cert`, `HttpClient`, `OLLMrpc.Client` with `http` set, `replace_rpc`, `yield rpc.connect(hello)` (no `ClientBoot`).
- **🔷** `⏳` Copy the Cert / HttpClient literals from `FileConnectionAdd.request()` (no fourth helper).
- **🔷** `⏳` Expose `project_manager`, `notification`, `window_config()` on the Android window so `FileConnectionRow.reconnect` compiles (same names as desktop).
- **⏳** Code proposals — after Phase 1 compiles.

---

## Phase 3 — `ChatDesktopInterface` + phone / tablet pane (`⏳`)

- **🔷** `⏳` `OllmchatWindow` implements `OLLMchat.ChatDesktopInterface`.
- **🔷** `⏳` Detect tablet once (device class). Phone keeps today's globe stack. Tablet always uses the landscape two-column shell.
- **🔷** `⏳` Tablet: chatter | browser-or-editor. One right slot (`tab_view`). Fixed columns, not `Gtk.Paned`.
- **🔷** `⏳` Tablet: lock landscape. No portrait / phone-stack fallback on that device.
- **🔷** `⏳` Route the existing Android browser `tool_toggle` into that same secondary surface (stack on phone, right column on tablet).
- **🚫** Register `AgentPi.Factory` / `AgentFactory` / Skill Runner on Android in this plan.
- **🚫** `WindowPane` on Android (resizable sash + grow-the-window).
- **🚫** `Adw.Breakpoint` / window-width switching between phone and tablet layouts.
- **⏳** Code proposals — after Phase 2 can connect.

---

## Verify before starting

- **ℹ️** `ConnectionsPage.render_approved` already references `win.project_manager.rpc`.
- **ℹ️** `FileConnectionRow.reconnect` already references `win.project_manager`, `win.notification`, `win.window_config()`.
- **🔷** `⏳` Fix `android_poc` compile errors in this plan. No `#if ANDROID` stubs on the desktop row.

---

## Follow-ups (`⏳`, not in this plan)

- **🔷** `⏳` Register `OLLMcoder.AgentPi.Factory` when the remote file connection is live (Android gate). Linux stays as today.

---

## Suggested order

1. **⏳** Phase 1 — `libocfiles` + full `liboccoder` + real `ProjectManager`
2. **⏳** Phase 2 — HTTPS `replace_rpc` + window APIs `FileConnectionRow` already calls
3. **⏳** Phase 3 — `ChatDesktopInterface` + phone stack / tablet landscape columns (browser now, editor host ready)

---

## LLM notes

- **ℹ️** Desktop Check / live toggle / Linux takeover stay in [`8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md).
- **🚫** `ClientBoot` on Android (no local Unix `ollmfilesd`).
- **🚫** Gating Linux Agent Pi on the remote connection.
- **🚫** Registering occoder agents on Android in this plan.
- **🚫** A second Android-only `activate` that avoids `ChatDesktopInterface`.
- **🚫** `WindowPane` / `Gtk.Paned` on Android (resizable sash, grow-the-window).
- **🚫** Width breakpoint that swaps phone ↔ tablet as the window rotates or resizes.
- **🚫** Portrait phone shell on a tablet.
- **🚫** Multiple file-server URLs.
- **🚫** `ensure_trust()` / `try/catch` around `Cert.ensure()`.
