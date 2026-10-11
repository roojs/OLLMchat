# Android Retry hides the desktop dialog and skips the checking spinner

**Status:** ⏳ emulator pass shows the unavailable dialog, the checking page, and a clean header after Close. The activate-project banner did not run on this emulator (no project). Not phone-checked.

**Related:** ℹ️ `docs/bugs/done/2026-10-08-CLOSED-android-remote-connection-lifecycle.md`, ℹ️ `docs/bugs/done/2026-10-10-CLOSED-desktop-unreachable-give-up.md`, ℹ️ `docs/bugs/done/2026-10-10-CLOSED-agent-manager.md`

## Problem

- **🔷** Laptop is off. Phone starts OLLMchat.
- **🔷** Startup reports that the desktop cannot be reached and shows the Retry or Close dialog.
- **🔷** Retry dismisses that dialog, then the phone behaves as if the desktop connection is working.
- **🔷** The laptop is still off, so the connection is not working.
- **🔷** Retry must show the startup checking spinner for the whole probe. Startup already does this: the startup page spinner and the label `Checking desktop environment…` while `initialize_client` probes the desktop.
- **🔷** The dialog must stay dismissed only while that check is on screen. A miss brings the Retry or Close dialog back. A hit is the only path that may treat the desktop as connected.

## Evidence

- **ℹ️** Startup desktop probe sets `startup_status_label` to `Checking desktop environment…` on the startup page, which already has a `Gtk.Spinner` (`ollmapp/android/OllmchatWindow.vala`, `initialize_client`).
- **ℹ️** The Retry or Close dialog is `Agent.Manager.on_unavailable`. Retry emits `client.filesd.retry` and returns. The window handler calls `reconnect.begin()` and returns. Neither path presents the startup spinner or a `BusyDialog`.
- **ℹ️** `reconnect` probes up to three times, then either sets `LIVE` or emits `client.filesd.unreachable` again. No phone log from this pass shows which of those ran after Retry.

## Root cause

- **✔️** `initialize_client` leaves `view_stack` on `chat` before the user can press Retry. The Retry handler calls `reconnect.begin()` and returns. The startup page is not shown, so the chat stays on screen for the whole probe.

## Ruled out

- **🚫** Treating Retry as success because the dialog closed. Closing the dialog is the button. The probe still has to run, and the checking spinner has to stay up until it finishes.

## Proposed fix

- **✔️** Retry shows the startup page and `Checking desktop environment…` until `reconnect` finishes. The chat page comes back when that call returns. A miss still emits `client.filesd.unreachable`.

#### Replace with

```vala
				if (notif.method == "client.filesd.retry") {
					this.view_stack.visible_child_name = "startup";
					this.startup_status_label.label = "Checking desktop environment…";
					this.reconnect.begin(true, (obj, res) => {
						this.reconnect.end(res);
						this.view_stack.visible_child_name = "chat";
					});
					return;
				}
```

## Attempts / changelog

- **✔️** 2026-10-11: `OllmchatWindow` Retry shows the startup page for the probe, then returns to chat. Desktop `ollmapp/ollmchat` linked. That build does not compile the Android window. The phone APK was not installed.

## Phone pass 09:32

- **🔷** A folder fetch while the desktop RPC is down must not raise the header banner. The unavailable dialog is the warning.
- **✔️** `Client.call` throws `RpcErrorCode.NOT_CONNECTED` when `connected` is false. The catch handler emits `client.filesd.unreachable` with that code. It does not emit `Banner.show` or `Alert.show`.
- **✔️** Android `Agent.Manager` shows the desktop-unavailable dialog for that notice. The window's banner and alert cases only display those methods.
- **ℹ️** Checking desktop environment stays up for the whole probe. A miss can take three passes, and each hello waits up to 10 seconds. Close returns to chat.

## Emulator pass 11:16

- **✔️** `emulator-5554`, desktop `10.0.2.2:1` connection refused. Startup shows `Desktop unavailable` / `The desktop environment is unavailable.` Retry and Close. The header has no project warning.
- **✔️** Retry shows the startup page: spinner and `Checking desktop environment…`. Three probes, then the same dialog. Logcat has no `Could not activate project` and no `not connected`.
- **✔️** Close returns to Chatter. The header stays empty.
- **ℹ️** This emulator has no project, so `ProjectManager.rpc_activate_project` never ran. A not-connected RPC emits `client.filesd.unreachable`. The Android handler shows the desktop-unavailable dialog.

## Next

- **⏳** 🔷 Phone, desktop unreachable, with a project open: a `not connected` activate or folder fetch must not leave a header banner. The warning is the desktop-unavailable dialog.
