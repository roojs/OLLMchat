# Android phone — remote desktop row, Agent Pi, file load

**Status:** ⏳ open — phone SM-S9380. ✅ on a heading is confirmed on the phone 2026-09-28. ✔️ is in the tree, not confirmed yet. Problems 3, 7, and 8 are still open. Problem 4 is in the tree.

**Logs:** Phone SM-S9380, `chat.androidpoc`, 2026-09-28 09:50–09:53. The buffer starts mid pid 24460. Pids 32608 and 32754 are full starts.

**Package:** `org.roojs.ollmchat.androidpoc`

**Related:**

- **ℹ️** Earlier phone list: [`2026-09-27-android-phone-issues.md`](2026-09-27-android-phone-issues.md). Expanders and `session_fetch` stay there.

---

## Problem 1 — Footer plus is missing ✅

- **🔷** Connections footer. A plus icon, then `LLM Connection`. A plus icon, then `Remote Desktop Connection`.
- **🔷** 2026-09-28: the plus is not there. The word Add was removed and only the remaining words show.
- **🔷** The remote-desktop label should say `Remote Desktop Connection`, the same shape as `LLM Connection`. Each word starts with a capital.

### Evidence

- **ℹ️** `ollmapp/SettingsDialog/ConnectionsPage.vala` sets `icon_name = "list-add-symbolic"` and then `label`.
- **ℹ️** `gtk_button_set_label` replaces the button child with a label. `gtk_button_set_icon_name` replaces it with an image. The initializer sets the icon first and the label second, so the plus is discarded.
- **✔️** The phone APK has `files/share/icons/Adwaita/symbolic/actions/list-add-symbolic.svg` (228 bytes, 2026-09-27 19:33). The glyph is installed. The button never keeps it.

### Root cause

- **✔️** `Gtk.Button` keeps either an icon or a label, not both. The label wins.

### Proposed fix

- **🔷** One child box on each footer button: a `list-add-symbolic` image, then the label. The desktop label is `Remote Desktop Connection`. `Gtk.Button` does not keep an icon and a label together.

#### Replace with

```vala
var llm_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
llm_box.append(new Gtk.Image.from_icon_name("list-add-symbolic"));
var llm_label = new Gtk.Label("LLM Connection") {
	ellipsize = Pango.EllipsizeMode.END,
	hexpand = true
};
llm_box.append(llm_label);
this.add_btn = new Gtk.Button() {
	child = llm_box,
	hexpand = true,
	css_classes = {"suggested-action"}
};
```

#### Replace with

```vala
var desktop_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
desktop_box.append(new Gtk.Image.from_icon_name("list-add-symbolic"));
var desktop_label = new Gtk.Label("Remote Desktop Connection") {
	ellipsize = Pango.EllipsizeMode.END,
	hexpand = true
};
desktop_box.append(desktop_label);
this.add_file_btn = new Gtk.Button() {
	child = desktop_box,
	hexpand = true
};
```

---

## Problem 2 — Registration row stays after the desktop is active ✅

- **🔷** After Check returns and the connection is active, the Registration row and its Check button should be gone.
- **🔷** 2026-09-28: Check returns and that whole Registration row is still there.

### Evidence

- **✔️** Phone config `files/etc/ollmchat/config.2.json` at 2026-09-28: `filesd-client.url` is `https://192.168.0.16:8443`, `state` is `3` (`FilesdClient.State.LIVE`).
- **ℹ️** The Registration action row and Check button are always added. `check()` sets the subtitle to `Active` and leaves that row in place.
- **ℹ️** Logcat for pid 8663 (started 08:22:14) has no `file connection check` line.

### Proposed fix

- **🔷** Bind the Registration row's `visible` to `filesd_client.state`. The row is visible while the state is `REQUESTED`. `LIVE` or active (`ENABLED`, `SOCKET`) hides it. Do not add or remove the row by hand.

#### Add

```vala
this.client.bind_property("state", check_row, "visible",
	GLib.BindingFlags.SYNC_CREATE,
	(binding, from_value, ref to_value) => {
		var state = (FilesdClient.State) from_value.get_enum();
		to_value.set_boolean(state == FilesdClient.State.REQUESTED);
		return true;
	});
```

---

## Problem 3 — Agent Pi is not in the list

- **🔷** The agent dropdown list does not contain Agent Pi. This is not a closed header sitting on the wrong row while Agent Pi is already in the list.
- **🔷** Once the remote desktop connection is active, Agent Pi should be in that list without quitting the app.
- **🔷** 2026-09-28 after the 08:53 install: still not in the list.

### Ruled out

- **🚫** Selecting row 0 because `dropdown-pos` was unset. That would leave Agent Pi in the list and only change which row is selected.
- **🚫** The popup skipping a row that is in the model. Pid 32608, 09:51:14, state `LIVE`: model `n=3` includes `agent-pi`, and bind paints `pos=0 name=agent-pi label=OLLMchat Agent 𝚷`.

### Log

- **✔️** Pid 32608, 09:51:14: store is `agent-pi`, `just-ask`, `chatter`. `show=true`. The open list can contain Agent Pi when the object `wire()` is watching is already `LIVE`.
- **✔️** Pid 32754, 09:51:34, the next start: same store, `state=REQUESTED` `show=false`. Model `n=2` is `just-ask` then `chatter`. Bind never paints `agent-pi`.
- **✔️** Same pid, 09:52:13 `file connection request ok`, 09:52:58 `check ok state=REQUESTED`, then `reconnect live`. There is no `agent list notify` and no `filesd state=` after that. The filter stays on the startup snapshot.

### Diagnosis

- **✔️** `AndroidStartup.run` builds `History.Manager` on `app.config`. The manager and `AgentDropdown.wire` listen to that object's `filesd_client`.
- **✔️** `OllmchatWindow.load_config_and_initialize` then does `app.config = load_config()` again and passes that second object to `initialize_client`. Settings, Check, and Remove edit the second object.
- **✔️** Check set the second object to `LIVE`. The dropdown was still watching the first object, which stayed `REQUESTED`, so Agent Pi stayed out of the list.

### Proposed fix

- **🔷** After `startup.run`, keep that same `Config2`. Do not load a second one for `initialize_client`. Check and Remove then notify the dropdown that `wire()` already attached.

---

## Problem 4 — Agent Pi file is always empty ✔️

- **🔷** Agent Pi file load fails completely, including after a restart. Opening a file shows an empty buffer. There is no content.
- **🔷** 2026-09-28 after the 08:53 install: selecting a file still does not load.
- **🚫** This is not “files work after restart.” Restart does not fill the buffer.

### Evidence

- **✔️** Phone pid 18967, 2026-09-28 08:57:43, after selecting a file:
  - `Failed to read file /home/alan/gitlive/OLLMchat/docs/bugs/2026-09-27-http-async-rpc-pause.md: File not found: /home/alan/gitlive/OLLMchat/docs/bugs/2026-09-27-http-async-rpc-pause.md`
  - `file read path=… loaded=false chars=0`
- **ℹ️** The project list is the remote daemon (`opening project path=/home/alan/gitlive/OLLMchat`, 1811 files).
- **ℹ️** `SourceView.open_file` then calls `file.buffer.read_async()`. `GtkSourceFileBuffer` reads `GLib.File.new_for_path` on that desktop path. The path is not on the phone, so the read throws and the editor is set to `""`.
- **ℹ️** `OLLMfiles.File.read` already loads the same path with `RPC-File.read`. Its comment says a thin client does not read local disk.

### Root cause

- **✔️** Opening a file reads the desktop path on the phone. The list comes from the daemon. The bytes do not.

### Proposed fix

- **✔️** `SourceView.open_file` calls `file.read()` (`RPC-File.read`). `File.read` clears the buffer first, which sets `is_loaded`, then applies the RPC text. It does not call `buffer.read_async()`.

#### Replace with

```vala
yield file.read();
```

---

## Problem 5 — Touch overlay was left on ✅

- **🔷** A line on the chat said `touch end` and a widget name. That overlay was not asked for.
- **✔️** Flag file `files/touch-debug` was created 2026-09-27 19:33 during expander debugging. Pid 8663 logged `touch-debug: enabled` at 08:22:15.
- **✔️** The flag file is removed. This process still shows the overlay until the next start. The next start will not enable it.

---

## Problem 6 — Row title is only the host ✔️

- **🔷** Once the connection is on, the expander title should name the desktop and the URL.
- **🔷** 2026-09-28: `Remote Desktop Connection: https://…` is too long on the phone. The expander title drops the word Connection. It reads `Remote Desktop: ` plus the URL.
- **🔷** The footer button stays `Remote Desktop Connection`.
- **ℹ️** The URL row inside the expander still shows the full URL.

---

## Problem 7 — Remove does not drop the desktop

- **🔷** Remove on the remote desktop row should drop that connection and keep it dropped.
- **🔷** It should also leave the Agent Pi session, take Agent Pi out of the agent list, and select the first agent that is still in that list.
- **🔷** 2026-09-28: the connection was removed and it came back. Possibly the config never reached disk.

### What Remove does

- **ℹ️** `ConnectionsPage.render_file_connection` replaces `config.filesd_client` with a new empty `FilesdClient` and calls `config.save()`.
- **ℹ️** `Config2.save` writes with `Json.Generator.to_file`. Android's durable write is `AndroidApplication.persist_config` (`FileUtils.set_contents`, log `saved config to`). That runs when the settings dialog closes, not from Remove.
- **ℹ️** `AgentDropdown.wire` and `History.Manager` listen to the `FilesdClient` object that existed at startup. Remove swaps in a new object and does not change the old one's `state`, so `notify["state"]` does not run.
- **ℹ️** The Manager handler only opens an Agent Pi session when `state` becomes `LIVE`. Nothing opens a different session when the desktop is removed.

### Diagnosis

- **✔️** Pid 32608 started `LIVE`. Pid 32754, the next start, was `REQUESTED` and had to register again. There is no `Failed to save config` or `config save failed`. That restart did keep the connection off disk. `saved config to` ran at 09:51:21 on 32608 and 09:51:33 on 32754.
- **🚫** A failed `to_file` is not what this buffer shows.
- **✔️** Remove still does not reset the session or the list. The dropdown and the manager listen to the first `Config2`. Remove edits the second, and it also replaces `filesd_client` with a new object, so `notify["state"]` does not run on the object they hold. The manager only switches *to* Agent Pi when state becomes `LIVE`. Nothing selects the first remaining agent.

### Proposed fix

- **🔷** Clear `url` and set `state` to `DISABLED` on the existing `FilesdClient`, so the listeners already attached see `notify["state"]`.
- **🔷** On Android, write that with `persist_config`. Desktop keeps `config.save()`.
- **🔷** If the session is `agent-pi`, start a new session on the first factory still in the filtered dropdown and select that row.

---

## Problem 8 — An already approved certificate stays Requested

- **🔷** Registering a certificate the desktop has already approved leaves the row at Requested. Check is still required.
- **🔷** `RPC-ClientCert.request_registration` should say the certificate is already accepted, and the phone should skip Check and become active.
- **🔷** 2026-09-28 pid 32754: register at 09:52:13, Check at 09:52:58. Check was still required.

### Evidence

- **ℹ️** `ClientCert.request_registration`: an existing fingerprint with `status != 0` replies `msg = "ok"`. That is the same reply as a new pending request. `status` `1` is approved, `0` is pending, `-1` is an IP ban, `-2` is rejected.
- **ℹ️** `FileConnectionAdd` ignores `response.msg`. Any success sets `registered_url` and closes.
- **ℹ️** `ConnectionsPage` then sets `filesd_client.state` to `REQUESTED` and toasts `Registration pending — accept the request on the desktop`.

### Diagnosis

- **✔️** Pid 32754: `file connection request ok` at 09:52:13, then `check ok state=REQUESTED` at 09:52:58. The phone stored `REQUESTED` and waited for Check. The client never logs `response.msg`, and the daemon's already-approved reply is the same `ok` as a new pending request.

### Proposed fix

- **🔷** When the existing row's `status` is `1`, reply `msg = "already accepted"`. A ban or a rejection stays an error, not `ok`.
- **🔷** `FileConnectionAdd` reads `response.msg`. `already accepted` does not set `REQUESTED` and does not toast pending. It takes the Check path: `ENABLED`, then `reconnect`, which sets `LIVE`.
