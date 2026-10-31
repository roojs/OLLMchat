# Approved phone row is titled ollmchat

**Status:** ⏳ open. The list title is the constant sent at registration. The phone name was specified and not shipped.

## Problem

- 🔷 The desktop connections list titles this phone `ollmchat`. That is the app, not the handset.
- 🔷 Expected: registration stores the Android phone name, and that string is the row title.
- 🔷 This was already the requester goal. It was not delivered.

## Evidence

- ✔️ `ApprovedClientRow` sets the expander title from `client.requester`. `ollmapp/SettingsDialog/ApprovedClientRow.vala`.
- ✔️ The phone sends that field as the literal `ollmchat` on `ClientCert.request_registration`. `libollmchat/Settings/FilesdClient.vala`, the `args("sss", pin, csr, "ollmchat")` call.
- ✔️ [`RPC-8.2.8.1`](../plans/done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) says the requester is a device string. The example is Android `Build.MODEL`, a Samsung model such as `SM-A110O`. The desktop only stores and shows it.
- ✔️ [`RPC-8.2.8.2`](../plans/done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) then sent `PRETTY_NAME` and wrote “no `Build.MODEL`”.
- ✔️ [`RPC-1.11.2`](../plans/RPC-1.11.2-android-discovery-and-pair-cli.md) keeps the requester as `ollmchat`, the same string hello sends.
- ℹ️ This handset’s adb model is `SM_S9380`. Nothing in the tree reads `Build.MODEL` or the Android device-name setting.
- 🚫 The hello name stays `ollmchat`. This bug is the registration string the connections list shows.

## Root cause

- ✔️ Pairing stores the constant `ollmchat` in `client_cert.requester`. The row title is that column. The phone-name read from [`8.2.8.1`](../plans/done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) was never added.

## Next

- 💩 ⏳ Read the Android phone name on the handset and pass that string as `requester` instead of `ollmchat`. The connections row then titles this phone, not the app.
