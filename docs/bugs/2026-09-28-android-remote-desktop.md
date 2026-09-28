# Android phone — remote desktop row, Agent Pi, file load

**Status:** ⏳ open — phone SM-S9380. A ✔️ on a problem heading means the change is in the tree, not yet confirmed on the phone. Problems 3 and 4 are still open.

**Package:** `org.roojs.ollmchat.androidpoc`

**Related:**

- **ℹ️** Earlier phone list: [`2026-09-27-android-phone-issues.md`](2026-09-27-android-phone-issues.md). Expanders and `session_fetch` stay there.

---

## Problem 1 — Footer plus is missing ✔️

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

## Problem 2 — Registration row stays after the desktop is active ✔️

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

## Problem 3 — Agent Pi appears only after restart

- **🔷** Once the remote desktop connection is active, Agent Pi should show in the header without quitting the app.
- **🔷** It shows only after the app is shut down and started again.

### Evidence

- **ℹ️** `AgentDropdown.wire()` hides factory `agent-pi` unless `filesd_client.state` is `LIVE` or `SOCKET`, then listens for `notify["state"]`.
- **ℹ️** `History.Manager` is supposed to open a new `agent-pi` session when `state` becomes `LIVE`.
- **ℹ️** Android startup (`OllmchatWindow`) forces a new `agent-pi` session only when the desktop was already reachable at launch. Setting `state` to `LIVE` when it is already `LIVE` does not notify.
- **✔️** Saved window agent is `just-ask` while `state` is already `LIVE`. The in-session switch did not stick. Restart is the path that selects Agent Pi.

### Next

- **⏳** **🔷** Debug, not a switch change yet.
- **✔️** `GLib.debug` on the agent-list filter (`agent-pi list state=`), on `notify["state"]` (`agent list notify state=`), and in `History.Manager` (`filesd state=` `session=`). `FileConnectionRow` logs `check ok state=` and `reconnect live url=`.
- **ℹ️** Those lines print when `OLLMchat.debug_on` is set (`--debug`). The touch overlay flag is not that switch.

---

## Problem 4 — Agent Pi file is always empty

- **🔷** Agent Pi file load fails completely, including after a restart. Opening a file shows an empty buffer. There is no content.
- **🚫** This is not “files work after restart.” Restart does not fill the buffer.

### Evidence

- **ℹ️** `SourceView.open_file` calls `file.buffer.read_async()`. On error it sets `gtk_buffer.text = ""`.
- **⏳** No file-read error in the 08:22 logcat buffer. Whether the read throws or returns an empty string is not in a log yet.

### Next

- **⏳** **✔️** `GLib.debug` after that read: `file read path=` `loaded=` `chars=`. Next open of an Agent Pi file should show the path and the character count.

---

## Problem 5 — Touch overlay was left on ✔️

- **🔷** A line on the chat said `touch end` and a widget name. That overlay was not asked for.
- **✔️** Flag file `files/touch-debug` was created 2026-09-27 19:33 during expander debugging. Pid 8663 logged `touch-debug: enabled` at 08:22:15.
- **✔️** The flag file is removed. This process still shows the overlay until the next start. The next start will not enable it.

---

## Problem 6 — Row title is only the host ✔️

- **🔷** Once the connection is on, the row should read `Remote Desktop Connection: ` plus the URL (`https://…`).
- **🔷** The phone shows `192.168.0.16`.
- **ℹ️** `FileConnectionRow` sets the expander title to `GLib.Uri.parse(client.url).get_host()`.
- **🚫** That title is not the Registration-row fix.
