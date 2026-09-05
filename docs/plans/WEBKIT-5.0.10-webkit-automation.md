# 5.0.10 — WebKit fill / press via automation (not AT-SPI Action)

> **Do not update `docs/plans/WEBKIT-1.0-summary.md` for this plan.**

**Status:** **ON HOLD** — OLLMchat app opt-in landed (steps 1–6 ✔️); Linux hide wired ([`2026-09-02-FIXED-webkit-automation-leaks-into-client-sites.md`](../bugs/done/2026-09-02-FIXED-webkit-automation-leaks-into-client-sites.md)); fill/press smoke still open. Win/Android wired; requires **webview2-gtk ≥ 0.5.9** / **webkitgtk-android ≥ 0.1.5**.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`WEBKIT-5.0-webkit-control.md`](WEBKIT-5.0-webkit-control.md)

**Related:**

- ℹ️ Parent dump / fill / press contract: [`WEBKIT-5.0-webkit-control.md`](WEBKIT-5.0-webkit-control.md) (a11y markdown, `(^fill:KEY)`, `(^press:N)`)
- ℹ️ Fill keys (**DONE**): [`done/5.0.8-DONE-webkit-fill-by-name.md`](done/5.0.8-DONE-webkit-fill-by-name.md)
- ℹ️ Windows WebView host: `/home/alan/git/webview2-gtk` — `WEBKIT_INSPECTOR_SERVER` → CDP; automation Vala API already exists
- ℹ️ Android WebView host: `/home/alan/git/webkitgtk-android` — [`1.4`](file:///home/alan/git/webkitgtk-android/docs/plans/1.4-android-automation-parity.md) Phase 0 CDP bridge ✅ + Phase 1 `WebContext` / `WebView.is_controlled_by_automation` ✅ (`AUTOMATION_SMOKE_PASS`); fill/press consumer is **this** plan
- ℹ️ Linux WebKitGTK 6.0 mouse / keyboard synth: [WebKit #318171](https://bugs.webkit.org/show_bug.cgi?id=318171) — stock distro `libwebkitgtk-6.0` often compiles interactions to `NotImplemented`. Need a 6.0 build with `ENABLE_WEBDRIVER` + interaction flags
- ℹ️ Precedent for build-time platform files (not `#ifdef` class forks): `libocbwrap/windows/*.vala` vs Linux sources in `libocbwrap/meson.build`
- ℹ️ Parent veto unchanged: no page-JS / DOM dump / fill / press (`evaluate_javascript` is not this path)

---

## Purpose

- **🔷** Switch **fill** and **press** off AT-SPI / UIA / AndroidAtspi **Action** + OS key synth (`do_action`, `set_text_contents`, `generate_keyboard_event`).
- **🔷** Deliver input through automation: click at a11y WINDOW coords, then paste (clipboard + Ctrl+A / Ctrl+V). Trailing `\n` in fill text still means Return.
- **🔷** **Dump / locate stay a11y** (`A11y.dump` / `A11yParse`). Press-refs and `(^fill:KEY)` do not change.
- **🔷** Same-process inspector client — **no** `WebKitWebDriver` / `msedgedriver` process, **no** Classic HTTP `/session` to an external driver.
- **🔷** Linux: RemoteInspector GVariant + `Automation.performMouseInteraction` / `performKeyboardInteractions`.
- **🔷** Windows **and** Android: CDP `Input.*` on the loopback port `prepare()` sets as `WEBKIT_INSPECTOR_SERVER`.
- **🔷** Bind inspector **`127.0.0.1` only**. Set `WEBKIT_INSPECTOR_SERVER` in code before any WebView exists.
- **🔷** Only the **primary** `WebView` is `is_controlled_by_automation = true`.
- **🔷** **Platform classes via Meson**, not `#ifdef` forks of the same class — same type name (`OLLMwebkit.WebDriver`, `OLLMwebkit.WebViewAuto`); different source files per platform (see **Architecture**). Prefer this over `#if WINDOWS` / `#if ANDROID` inside method bodies.
- **🔷** Do **not** spoof `navigator.webdriver`.
- **ℹ️** Tool wire (`fetch` / `search` / `press` / `fill` argument / `whereami`) is unchanged.

---

## Architecture

```
prepare()  →  bind 127.0.0.1:<port>, set WEBKIT_INSPECTOR_SERVER
WebViewAuto  →  set_automation_allowed + is_controlled_by_automation
BrowserStack  →  attach() once the primary view exists

fill / press:
  dump (a11y)  →  node x/y/width/height
       →  WebDriver.click(view, center)  →  paste or click
```

### Build-time platform files (🔷 — not `#ifdef` class choice)

- **🔷** Shared: `libocwebkit/WebDriverValue.vala` (JSON-RPC / CDP param types — all platforms).
- **🔷** `OLLMwebkit.WebDriver` — **one class name**, two implementations Meson picks:
  - `libocwebkit/linux/WebDriver.vala` — RemoteInspector (Linux only)
  - `libocwebkit/cdp/WebDriver.vala` — CDP transport (Windows **and** Android)
- **🔷** `OLLMwebkit.WebViewAuto` — **one class name**, three thin files (only `using` / pkg differs):
  - `libocwebkit/linux/WebViewAuto.vala` — `using WebKit;`
  - `libocwebkit/windows/WebViewAuto.vala` — `using WebView2Gtk;`
  - `libocwebkit/android/WebViewAuto.vala` — `using WebKitGtkAndroid;`
- **🔷** `main` / `oc-test-webkit` always: `WebDriver.instance = new WebDriver();` then `prepare()` — no `#if` to pick a subclass.
- **🚫** Do **not** ship a `WebDriverCdp` type name or `#if WINDOWS … new WebDriverCdp()` — the CDP file **is** `WebDriver`.

### Approved helpers (🔷 — nest flattening)

User-approved new methods (do not invent more):

- **🔷** `ingest_message` — Linux `WebDriver`: body of the `while (this.inbox.len >= 5)` loop (parse one framed inspector message + the switch that handles it).
- **🔷** `fill_node` — shared `fill`: body of the inner `foreach (var node in a11y.nodes)` (click center + paste / Return for one matched node).
- **🔷** `await_cdp` — CDP `WebDriver.attach`: the `if (!this.listening) { … }` block (poll `/json/version`, then `open_page`).

### Platform notes

- **🔷** **Linux** — RemoteInspector `WebDriver`. Needs WebKitGTK 6.0 **with interactions** ([#318171](https://bugs.webkit.org/show_bug.cgi?id=318171)).
- **🔷** **Windows** — CDP `WebDriver`. **webview2-gtk** already maps `WEBKIT_INSPECTOR_SERVER`.
- **🔷** **Android** — same CDP `WebDriver` file as Windows. Sibling listen + Vala automation API are ready; wire `prepare()` / `WebViewAuto` / fill+press here.

---

## Suggested order

1. **✔️** **🔷** `WebDriverValue.vala` + Meson platform source lists (`linux/` / `cdp/` / per-OS `WebViewAuto`).
2. **✔️** **🔷** `linux/WebDriver.vala` with `ingest_message` + `fill_node` helpers.
3. **✔️** **🔷** `cdp/WebDriver.vala` (Windows + Android) with `await_cdp` + same `fill_node` / `click` / `press` shape.
4. **✔️** **🔷** Platform `WebViewAuto` files; `Browser` always uses `WebViewAuto`; fill / press always call `WebDriver`.
5. **✔️** **🔷** Drop `A11y.fill` / `A11y.press` / `*_sync` on **all** platforms (dump only).
6. **✔️** **🔷** `prepare()` in `ollmapp` (desktop + Android) + `oc-test-webkit` **before** any WebView — always `new WebDriver()`.
7. **⏸️ ON HOLD** **🔷** Smoke: Google fill + press on Linux, Windows, and Android — Linux hide fixed ([`2026-09-02-FIXED-webkit-automation-leaks-into-client-sites.md`](../bugs/done/2026-09-02-FIXED-webkit-automation-leaks-into-client-sites.md)); smoke still open.

---

## 1. `libocwebkit/WebDriverValue.vala` — JSON-RPC types (new file)

**Why:** Inspector / CDP payloads. GObject forbids a property named `type`; fake `ParamSpec`s expose CDP / Automation JSON keys.

**Where:** new file in `libocwebkit/`.

**Depends on:** none.

**Approved types:** `WebDriverPoint`, `WebDriverMouse`, `WebDriverKey`, `WebDriverKeys`, `WebDriverCall`, `WebDriverValue`, `WebDriverCdpMouse`, `WebDriverCdpKey`, `WebDriverCdpText`.

**Approved methods on those types:** `find_property`, `Json.Serializable.set_property`, `Json.Serializable.get_property`, `serialize_property`, `deserialize_property`, `list_properties` — only as written below (JSON mapping, not extra helpers).

#### Add — full file

Edits are **Add** from the tree; new file.

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * Viewport point for {{{performMouseInteraction}}}.
 *
 * @see OLLMwebkit.WebDriverMouse
 */
public class OLLMwebkit.WebDriverPoint : Object, Json.Serializable
{
	public int x { get; set; default = 0; }
	public int y { get; set; default = 0; }

	public unowned ParamSpec? find_property(string name)
	{
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		base.set_property(pspec.get_name(), value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		base.get_property(pspec.get_name(), ref val);
		return val;
	}
}

/**
 * {{{Automation.performMouseInteraction}}} params.
 *
 * @see OLLMwebkit.WebDriver
 */
public class OLLMwebkit.WebDriverMouse : Object, Json.Serializable
{
	public string handle { get; set; default = ""; }
	public OLLMwebkit.WebDriverPoint position { get; set; default = new OLLMwebkit.WebDriverPoint(); }
	public string button { get; set; default = ""; }
	public string interaction { get; set; default = ""; }
	public Gee.ArrayList<string> modifiers { get; set; default = new Gee.ArrayList<string>(); }

	public unowned ParamSpec? find_property(string name)
	{
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		base.set_property(pspec.get_name(), value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		base.get_property(pspec.get_name(), ref val);
		return val;
	}

	public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
	{
		if (property_name != "modifiers") {
			return default_serialize_property(property_name, value, pspec);
		}
		var arr = new Json.Array();
		var list = value.get_object() as Gee.ArrayList<string>;
		if (list != null) {
			foreach (var modifier in list) {
				arr.add_string_element(modifier);
			}
		}
		var node = new Json.Node(Json.NodeType.ARRAY);
		node.take_array(arr);
		return node;
	}
}

/**
 * One keyboard step in {{{performKeyboardInteractions}}}.
 *
 * JSON key {{{type}}} maps to {{{kind}}} (GObject forbids a {{{type}}} property).
 *
 * @see OLLMwebkit.WebDriverKeys
 */
public class OLLMwebkit.WebDriverKey : Object, Json.Serializable
{
	public string kind { get; set; default = ""; }
	public string key { get; set; default = ""; }
	public string text { get; set; default = ""; }
	private GLib.ParamSpec type_spec { get; set; default = new GLib.ParamSpecString(
		"type", "type", "type", "", GLib.ParamFlags.READABLE | GLib.ParamFlags.WRITABLE); }

	public unowned ParamSpec? find_property(string name)
	{
		if (name == "type") {
			return this.get_class().find_property("kind");
		}
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		var name = pspec.get_name();
		if (name == "type") {
			name = "kind";
		}
		base.set_property(name, value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		var name = pspec.get_name();
		if (name == "type") {
			name = "kind";
		}
		base.get_property(name, ref val);
		return val;
	}

	public override (unowned GLib.ParamSpec)[] list_properties()
	{
		if (this.key != "" && this.text != "") {
			return {
				this.type_spec,
				this.get_class().find_property("key"),
				this.get_class().find_property("text"),
			};
		}
		if (this.key != "") {
			return {
				this.type_spec,
				this.get_class().find_property("key"),
			};
		}
		if (this.text != "") {
			return {
				this.type_spec,
				this.get_class().find_property("text"),
			};
		}
		return {
			this.type_spec,
		};
	}
}

/**
 * {{{Automation.performKeyboardInteractions}}} params.
 *
 * @see OLLMwebkit.WebDriver
 */
public class OLLMwebkit.WebDriverKeys : Object, Json.Serializable
{
	public string handle { get; set; default = ""; }
	public Gee.ArrayList<OLLMwebkit.WebDriverKey> interactions {
		get; set; default = new Gee.ArrayList<OLLMwebkit.WebDriverKey>(); }

	public unowned ParamSpec? find_property(string name)
	{
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		base.set_property(pspec.get_name(), value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		base.get_property(pspec.get_name(), ref val);
		return val;
	}

	public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
	{
		if (property_name != "interactions") {
			return default_serialize_property(property_name, value, pspec);
		}
		var arr = new Json.Array();
		var list = value.get_object() as Gee.ArrayList<OLLMwebkit.WebDriverKey>;
		if (list != null) {
			foreach (var step in list) {
				arr.add_element(Json.gobject_serialize(step));
			}
		}
		var node = new Json.Node(Json.NodeType.ARRAY);
		node.take_array(arr);
		return node;
	}
}

/**
 * Inspector JSON-RPC request. {{{params}}} is the domain object
 * (mouse, keys, or empty {{{WebDriverValue}}}).
 *
 * @see OLLMwebkit.WebDriver
 */
public class OLLMwebkit.WebDriverCall : Object, Json.Serializable
{
	public int64 id { get; set; default = 0; }
	public string method { get; set; default = ""; }
	public GLib.Object params { get; set; default = new GLib.Object(); }

	public unowned ParamSpec? find_property(string name)
	{
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		base.set_property(pspec.get_name(), value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		base.get_property(pspec.get_name(), ref val);
		return val;
	}

	public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
	{
		if (property_name != "params") {
			return default_serialize_property(property_name, value, pspec);
		}
		return Json.gobject_serialize((GLib.Object) value.get_object());
	}
}

/**
 * Inspector JSON-RPC reply, browsing-context row, or empty command params.
 *
 * {{{result}}} / {{{error}}} have no {{{default = new WebDriverValue()}}} —
 * that would recurse on construct.
 *
 * @see OLLMwebkit.WebDriver
 */
public class OLLMwebkit.WebDriverValue : Object, Json.Serializable
{
	public int64 id { get; set; default = 0; }
	public bool failed { get; set; default = false; }
	public string message { get; set; default = ""; }
	public string name { get; set; default = ""; }
	public string handle { get; set; default = ""; }
	public string url { get; set; default = ""; }
	public OLLMwebkit.WebDriverValue result { get; set; }
	public OLLMwebkit.WebDriverValue error { get; set; }
	public Gee.ArrayList<OLLMwebkit.WebDriverValue> contexts {
		get; set; default = new Gee.ArrayList<OLLMwebkit.WebDriverValue>(); }

	public unowned ParamSpec? find_property(string name)
	{
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		base.set_property(pspec.get_name(), value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		base.get_property(pspec.get_name(), ref val);
		return val;
	}

	public override bool deserialize_property(
		string property_name,
		out Value value,
		ParamSpec pspec,
		Json.Node property_node
	) {
		switch (property_name) {
			case "error":
				this.failed = true;
				if (property_node.get_node_type() == Json.NodeType.OBJECT) {
					var obj = property_node.get_object();
					if (obj.has_member("message")) {
						this.message = obj.get_string_member("message");
					}
					if (obj.has_member("name")) {
						this.name = obj.get_string_member("name");
					}
				}
				return default_deserialize_property(property_name, out value, pspec, property_node);

			case "contexts":
				var list = new Gee.ArrayList<OLLMwebkit.WebDriverValue>();
				if (property_node.get_node_type() == Json.NodeType.ARRAY) {
					foreach (var node in property_node.get_array().get_elements()) {
						if (node.get_node_type() != Json.NodeType.OBJECT) {
							continue;
						}
						list.add((OLLMwebkit.WebDriverValue) Json.gobject_deserialize(
							typeof (OLLMwebkit.WebDriverValue), node
						));
					}
				}
				this.contexts = list;
				value = Value(typeof (Gee.ArrayList));
				value.set_object(list);
				return true;

			default:
				return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}

/**
 * CDP {{{Input.dispatchMouseEvent}}} params.
 *
 * Chromium wants JSON keys {{{type}}}, {{{clickCount}}}, {{{pointerType}}}.
 *
 * @see OLLMwebkit.WebDriverCall
 */
public class OLLMwebkit.WebDriverCdpMouse : Object, Json.Serializable
{
	public string kind { get; set; default = ""; }
	public int x { get; set; default = 0; }
	public int y { get; set; default = 0; }
	public string button { get; set; default = "none"; }
	public int buttons { get; set; default = 0; }
	public int click_count { get; set; default = 0; }
	public string pointer_type { get; set; default = "mouse"; }
	private GLib.ParamSpec type_spec { get; set; default = new GLib.ParamSpecString(
		"type", "type", "type", "", GLib.ParamFlags.READABLE | GLib.ParamFlags.WRITABLE); }
	private GLib.ParamSpec click_count_spec { get; set; default = new GLib.ParamSpecInt(
		"clickCount", "clickCount", "clickCount", 0, int.MAX, 0,
		GLib.ParamFlags.READABLE | GLib.ParamFlags.WRITABLE); }
	private GLib.ParamSpec pointer_type_spec { get; set; default = new GLib.ParamSpecString(
		"pointerType", "pointerType", "pointerType", "mouse",
		GLib.ParamFlags.READABLE | GLib.ParamFlags.WRITABLE); }

	public unowned ParamSpec? find_property(string name)
	{
		switch (name) {
			case "type":
				return this.type_spec;
			case "clickCount":
				return this.click_count_spec;
			case "pointerType":
				return this.pointer_type_spec;
		}
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		var name = pspec.get_name();
		switch (name) {
			case "type":
				name = "kind";
				break;
			case "clickCount":
				name = "click_count";
				break;
			case "pointerType":
				name = "pointer_type";
				break;
		}
		base.set_property(name, value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		var name = pspec.get_name();
		switch (name) {
			case "type":
				name = "kind";
				break;
			case "clickCount":
				name = "click_count";
				break;
			case "pointerType":
				name = "pointer_type";
				break;
		}
		base.get_property(name, ref val);
		return val;
	}

	public override (unowned GLib.ParamSpec)[] list_properties()
	{
		return {
			this.type_spec,
			this.get_class().find_property("x"),
			this.get_class().find_property("y"),
			this.get_class().find_property("button"),
			this.get_class().find_property("buttons"),
			this.click_count_spec,
			this.pointer_type_spec,
		};
	}
}

/**
 * CDP {{{Input.dispatchKeyEvent}}} params.
 *
 * @see OLLMwebkit.WebDriverCall
 */
public class OLLMwebkit.WebDriverCdpKey : Object, Json.Serializable
{
	public string kind { get; set; default = ""; }
	public string key { get; set; default = ""; }
	public string code { get; set; default = ""; }
	public int modifiers { get; set; default = 0; }
	public int windows_virtual_key_code { get; set; default = 0; }
	public int native_virtual_key_code { get; set; default = 0; }
	private GLib.ParamSpec type_spec { get; set; default = new GLib.ParamSpecString(
		"type", "type", "type", "", GLib.ParamFlags.READABLE | GLib.ParamFlags.WRITABLE); }
	private GLib.ParamSpec windows_vk_spec { get; set; default = new GLib.ParamSpecInt(
		"windowsVirtualKeyCode", "windowsVirtualKeyCode", "windowsVirtualKeyCode",
		0, int.MAX, 0, GLib.ParamFlags.READABLE | GLib.ParamFlags.WRITABLE); }
	private GLib.ParamSpec native_vk_spec { get; set; default = new GLib.ParamSpecInt(
		"nativeVirtualKeyCode", "nativeVirtualKeyCode", "nativeVirtualKeyCode",
		0, int.MAX, 0, GLib.ParamFlags.READABLE | GLib.ParamFlags.WRITABLE); }

	public unowned ParamSpec? find_property(string name)
	{
		switch (name) {
			case "type":
				return this.type_spec;
			case "windowsVirtualKeyCode":
				return this.windows_vk_spec;
			case "nativeVirtualKeyCode":
				return this.native_vk_spec;
		}
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		var name = pspec.get_name();
		switch (name) {
			case "type":
				name = "kind";
				break;
			case "windowsVirtualKeyCode":
				name = "windows_virtual_key_code";
				break;
			case "nativeVirtualKeyCode":
				name = "native_virtual_key_code";
				break;
		}
		base.set_property(name, value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		var name = pspec.get_name();
		switch (name) {
			case "type":
				name = "kind";
				break;
			case "windowsVirtualKeyCode":
				name = "windows_virtual_key_code";
				break;
			case "nativeVirtualKeyCode":
				name = "native_virtual_key_code";
				break;
		}
		base.get_property(name, ref val);
		return val;
	}

	public override (unowned GLib.ParamSpec)[] list_properties()
	{
		return {
			this.type_spec,
			this.get_class().find_property("key"),
			this.get_class().find_property("code"),
			this.get_class().find_property("modifiers"),
			this.windows_vk_spec,
			this.native_vk_spec,
		};
	}
}

/**
 * CDP {{{Input.insertText}}} params.
 *
 * @see OLLMwebkit.WebDriverCall
 */
public class OLLMwebkit.WebDriverCdpText : Object, Json.Serializable
{
	public string text { get; set; default = ""; }

	public unowned ParamSpec? find_property(string name)
	{
		unowned ParamSpec? pspec = this.get_class().find_property(name);
		if (pspec != null) {
			return pspec;
		}
		return this.get_class().find_property(name.replace("_", "-"));
	}

	public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
	{
		base.set_property(pspec.get_name(), value);
	}

	public new Value Json.Serializable.get_property(ParamSpec pspec)
	{
		var val = Value(pspec.value_type);
		base.get_property(pspec.get_name(), ref val);
		return val;
	}
}
```

---

## 2. `libocwebkit/linux/WebDriver.vala` — Linux RemoteInspector client (new file)

**Why:** Same-process input on Linux. Meson compiles this file **only** on Linux as `OLLMwebkit.WebDriver`.

**Where:** new file under `libocwebkit/linux/`.

**Depends on:** §1.

**Approved methods:** `prepare`, `attach`, `write`, `ingest`, `ingest_message`, `send`, `new_session`, `delete_session`, `click`, `fill`, `fill_node`, `press`.

**🔷** `fill` matches `A11yNode.fill_key` (HTML `name=` / `id=`), **not** press-ref ids.

**🔷** `ingest_message` — whole inner body of the `while (this.inbox.len >= 5)` loop (frame parse + both switches).

**🔷** `fill_node` — inner `foreach` body (one matched node: click + paste + optional Return).

**💩** No on-WebView pointer overlay (click still wanders in from a nearby point).

**ℹ️** Full-file fence below is the Linux implementation. Apply helpers as written (`ingest` / `fill` call them) — do not leave the nested forms.

#### Add — full file

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * Same-process input client for the primary WebView.
 *
 * {{{prepare}}} binds the inspector port. This Linux file talks WebKit
 * RemoteInspector. Windows / Android compile {{{cdp/WebDriver.vala}}} as
 * the same class name. {{{click}}} / {{{fill}}} / {{{press}}} live on
 * each platform file.
 *
 * == Example ==
 *
 * {{{
 * OLLMwebkit.WebDriver.instance = new OLLMwebkit.WebDriver();
 * OLLMwebkit.WebDriver.instance.prepare();
 * yield OLLMwebkit.WebDriver.instance.fill(browser.a11y, browser.web_view, fields);
 * }}}
 *
 * @see OLLMwebkit.Browser
 */
public class OLLMwebkit.WebDriver : Object
{
	/**
	 * Process-wide client. Constructed in {{{main}}} before {{{prepare}}}.
	 */
	public static OLLMwebkit.WebDriver instance;

	/**
	 * Browsing-context handle from {{{Automation.getBrowsingContexts}}}.
	 * Empty until {{{attach}}} succeeds.
	 */
	public string session_id { get; set; default = ""; }

	/**
	 * Session id sent with {{{StartAutomationSession}}}.
	 * Match {{{WebKit.ApplicationInfo}}} name.
	 */
	public string browser_name { get; set; default = ""; }

	/**
	 * RemoteInspector / CDP port ({{{WEBKIT_INSPECTOR_SERVER}}}).
	 */
	public uint16 inspector_port = 0;

	private GLib.SocketConnection sock;
	private GLib.SocketSource read_source;
	private GLib.ByteArray inbox { get; set; default = new GLib.ByteArray(); }
	protected uint64 connection_id = 0;
	protected uint64 target_id = 0;
	protected int command_id = 0;
	protected int reply_id = 0;
	protected OLLMwebkit.WebDriverValue incoming_reply { get; set; default = new OLLMwebkit.WebDriverValue(); }
	private GLib.Variant incoming_message { get; set; default = new GLib.Variant("()"); }
	protected bool have_reply = false;
	protected bool attaching = false;
	protected bool listening = false;
	protected string paste_text = "";
	protected signal void targeted ();
	protected signal void replied ();
	protected signal void attached ();

	/**
	 * Bind a loopback inspector port and set {{{WEBKIT_INSPECTOR_SERVER}}}
	 * before any WebView is created.
	 *
	 * @throws GLib.Error when a loopback bind fails
	 */
	public void prepare() throws GLib.Error
	{
		var probe = new GLib.Socket(GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
		probe.bind(new GLib.InetSocketAddress(new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0), true);
		this.inspector_port = ((GLib.InetSocketAddress) probe.get_local_address()).get_port();
		probe.close();
		GLib.Environment.set_variable("WEBKIT_INSPECTOR_SERVER",
			"127.0.0.1:" + this.inspector_port.to_string(), true);
		GLib.Environment.set_variable("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS", "1", true);
		this.browser_name = "OLLMchat";
	}

	/**
	 * Connect to the inspector socket and start the Automation target.
	 * Idempotent. Failures are logged; {{{session_id}}} stays empty.
	 */
	public virtual async void attach()
	{
		if (this.session_id != "") {
			return;
		}
		if (this.attaching) {
			var wait_id = 0UL;
			wait_id = this.attached.connect(() => {
				this.disconnect(wait_id);
				this.attach.callback();
			});
			yield;
			if (this.session_id != "") {
				return;
			}
		}
		this.attaching = true;
		this.target_id = 0;
		this.connection_id = 0;
		if (!this.listening) {
			var client = new GLib.SocketClient();
			try {
				this.sock = yield client.connect_to_host_async(
					"127.0.0.1", this.inspector_port, null
				);
			} catch (GLib.Error connect_error) {
				this.attaching = false;
				this.attached();
				GLib.warning("%s", connect_error.message);
				return;
			}
			this.sock.get_socket().set_blocking(false);
			this.read_source = this.sock.get_socket().create_source(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR, null
			);
			this.read_source.set_callback((socket, condition) => {
				this.ingest();
				return this.listening;
			});
			this.read_source.attach(null);
			this.listening = true;
		}
		var caps = new GLib.VariantBuilder(new GLib.VariantType("a{sv}"));
		this.write("StartAutomationSession",
			new GLib.Variant("(s@a{sv})", this.browser_name, caps.end()));
		var target_wait = 0UL;
		target_wait = this.targeted.connect(() => {
			this.disconnect(target_wait);
			this.attach.callback();
		});
		yield;
		if (this.target_id == 0) {
			this.attaching = false;
			this.attached();
			GLib.warning("inspector: no automation target");
			return;
		}
		this.write("Setup", new GLib.Variant("(tt)", this.connection_id, this.target_id));
		try {
			yield this.new_session();
		} catch (GLib.Error session_error) {
			this.attaching = false;
			this.attached();
			GLib.warning("%s", session_error.message);
			return;
		}
		this.attaching = false;
		this.attached();
	}

	protected virtual void write(string name, GLib.Variant parameters)
	{
		if (!this.listening) {
			return;
		}
		var payload = parameters.get_data_as_bytes();
		var body_size = name.length + 1 + payload.get_size();
		var stream = new GLib.MemoryOutputStream.resizable();
		var header = new uint8[] {
			(uint8) ((body_size >> 24) & 0xff),
			(uint8) ((body_size >> 16) & 0xff),
			(uint8) ((body_size >> 8) & 0xff),
			(uint8) (body_size & 0xff),
			1
		};
		var zero = new uint8[] { 0 };
		try {
			stream.write_all(header, null);
			stream.write_all(name.data, null);
			stream.write_all(zero, null);
			stream.write_all(payload.get_data(), null);
			stream.close();
			this.sock.get_socket().set_blocking(true);
			this.sock.get_socket().send(stream.steal_as_bytes().get_data());
			this.sock.get_socket().set_blocking(false);
		} catch (GLib.Error write_error) {
			GLib.warning("%s", write_error.message);
		}
	}

	private void ingest()
	{
		if (!this.listening) {
			return;
		}
		var chunk = new uint8[4096];
		var n = 0;
		try {
			n = (int) this.sock.get_socket().receive(chunk);
		} catch (GLib.Error receive_error) {
			if (receive_error is GLib.IOError.WOULD_BLOCK) {
				return;
			}
			this.listening = false;
			GLib.warning("%s", receive_error.message);
			this.attaching = false;
			this.replied();
			this.targeted();
			this.attached();
			return;
		}
		if (n <= 0) {
			this.listening = false;
			this.attaching = false;
			this.replied();
			this.targeted();
			this.attached();
			return;
		}
		this.inbox.append(chunk[0:n]);
		while (this.inbox.len >= 5) {
			if (!this.ingest_message()) {
				return;
			}
		}
	}

	/**
	 * Parse and handle one framed inspector message from {{{inbox}}}.
	 *
	 * @return false when the frame is incomplete (caller should wait for more bytes)
	 */
	private bool ingest_message()
	{
		var body_size = ((uint32) this.inbox.data[0] << 24)
			| ((uint32) this.inbox.data[1] << 16)
			| ((uint32) this.inbox.data[2] << 8)
			| (uint32) this.inbox.data[3];
		var message_size = 5 + (int) body_size;
		if (this.inbox.len < message_size) {
			return false;
		}
		var flags = this.inbox.data[4];
		var name = (string) this.inbox.data[5:message_size];
		var blob = new GLib.Bytes(this.inbox.data[(6 + name.length):message_size]);
		var rest = this.inbox.data[message_size:this.inbox.len];
		this.inbox = new GLib.ByteArray();
		this.inbox.append(rest);
		var signature = "()";
		switch (name) {
			case "SetTargetList":
				signature = "(ta(tsssb))";
				break;
			case "DidStartAutomationSession":
				signature = "(ss)";
				break;
			case "SendMessageToFrontend":
				signature = "(tts)";
				break;
		}
		try {
			this.incoming_message = new GLib.Variant.from_bytes(
				new GLib.VariantType(signature),
				blob,
				false
			);
		} catch (GLib.Error parse_error) {
			GLib.warning("%s", parse_error.message);
			return true;
		}
		if ((flags & 1) == 0) {
			this.incoming_message = this.incoming_message.byteswap();
		}
		switch (name) {
			case "DidStartAutomationSession":
				return true;
			case "SetTargetList":
				this.connection_id = this.incoming_message.get_child_value(0).get_uint64();
				var list = this.incoming_message.get_child_value(1);
				for (var i = 0; i < list.n_children(); i++) {
					var row = list.get_child_value(i);
					if (row.get_child_value(1).get_string() != "Automation") {
						continue;
					}
					this.target_id = row.get_child_value(0).get_uint64();
					break;
				}
				if (this.target_id == 0) {
					return true;
				}
				this.targeted();
				return true;
			case "SendMessageToFrontend":
				var text = this.incoming_message.get_child_value(2).get_string();
				try {
					this.incoming_reply = (OLLMwebkit.WebDriverValue) Json.gobject_from_data(
						typeof (OLLMwebkit.WebDriverValue), text, -1
					);
				} catch (GLib.Error json_error) {
					GLib.warning("%s", json_error.message);
					return true;
				}
				if (this.incoming_reply.id != this.reply_id) {
					return true;
				}
				this.have_reply = true;
				this.replied();
				return true;
			case "DidClose":
				this.session_id = "";
				this.target_id = 0;
				this.replied();
				this.targeted();
				return true;
			default:
				return true;
		}
	}

	/**
	 * Send one Automation inspector command.
	 *
	 * @param method domain method without the {{{Automation.}}} prefix
	 * @param parameters command params object
	 * @return the inspector reply
	 * @throws GLib.Error on transport failure or inspector error
	 */
	public virtual async OLLMwebkit.WebDriverValue send(string method, GLib.Object parameters) throws GLib.Error
	{
		this.command_id++;
		this.reply_id = this.command_id;
		this.have_reply = false;
		var call = new OLLMwebkit.WebDriverCall() {
			id = this.command_id,
			method = "Automation." + method,
			params = parameters,
		};
		var wait_id = 0UL;
		wait_id = this.replied.connect(() => {
			this.disconnect(wait_id);
			this.send.callback();
		});
		this.write("SendMessageToBackend",
			new GLib.Variant("(tts)", this.connection_id, this.target_id, Json.gobject_to_data(call, null)));
		yield;
		if (!this.have_reply) {
			throw new GLib.IOError.FAILED("inspector: no reply");
		}
		if (this.incoming_reply.failed) {
			throw new GLib.IOError.FAILED("inspector: %s %s",
				this.incoming_reply.name, this.incoming_reply.message);
		}
		return this.incoming_reply;
	}

	/**
	 * Resolve the browsing-context handle ({{{Automation.getBrowsingContexts}}}).
	 *
	 * @throws GLib.Error when the command fails or no context exists
	 */
	public async void new_session() throws GLib.Error
	{
		var reply = yield this.send("getBrowsingContexts", new GLib.Object());
		if (reply.result.contexts.size == 0) {
			throw new GLib.IOError.NOT_FOUND("inspector: no browsing context");
		}
		this.session_id = reply.result.contexts.get(0).handle;
	}

	/**
	 * Drop the browsing-context handle.
	 */
	public virtual async void delete_session() throws GLib.Error
	{
		if (this.session_id == "") {
			return;
		}
		this.write("FrontendDidClose", new GLib.Variant("(tt)", this.connection_id, this.target_id));
		this.session_id = "";
	}

	/**
	 * Click at viewport coordinates via Automation mouse.
	 * Wanders in from a nearby point, then left-clicks.
	 *
	 * @param view WebView (GDK scale)
	 * @param x viewport X
	 * @param y viewport Y
	 * @throws GLib.Error when mouse commands fail or there is no session
	 */
	public virtual async void click(Gtk.Widget view, int x, int y) throws GLib.Error
	{
		if (this.session_id == "") {
			throw new GLib.IOError.FAILED("inspector: no session");
		}
		var start_x = (x + GLib.Random.int_range(-220, -40)).clamp(8, int.max(8, x));
		var start_y = (y + GLib.Random.int_range(48, 200)).clamp(8, y + 240);
		var mid_x = ((start_x + x) / 2) + GLib.Random.int_range(-40, 41);
		var mid_y = ((start_y + y) / 2) + GLib.Random.int_range(-28, 29);
		GLib.debug("click wander %d,%d %d,%d click %d,%d", start_x, start_y, mid_x, mid_y, x, y);
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() {
				x = start_x,
				y = start_y,
			},
			button = "None",
			interaction = "Move",
		});
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 80), () => {
			this.click.callback();
			return false;
		});
		yield;
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() {
				x = mid_x,
				y = mid_y,
			},
			button = "None",
			interaction = "Move",
		});
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 80), () => {
			this.click.callback();
			return false;
		});
		yield;
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() {
				x = x,
				y = y,
			},
			button = "Left",
			interaction = "SingleClick",
		});
		GLib.Timeout.add(180 + GLib.Random.int_range(0, 220), () => {
			this.click.callback();
			return false;
		});
		yield;
	}

	/**
	 * Fill by HTML name/id: click at a11y WINDOW coords, then paste.
	 * Clipboard + Ctrl+A / Ctrl+V (not per-character keys).
	 * Trailing newline means Return.
	 *
	 * @param a11y dump whose {{{nodes}}} hold fill_key + coordinates
	 * @param view WebView for GDK scale and clipboard
	 * @param fields fill key → text
	 * @throws GLib.Error when attach, locate, or keys fail
	 */
	public async void fill(
		OLLMwebkit.A11y a11y,
		Gtk.Widget view,
		Gee.HashMap<string, string> fields
	) throws GLib.Error {
		yield this.attach();
		foreach (var key in fields.keys) {
			var found = false;
			foreach (var node in a11y.nodes) {
				if (node.fill_key != key) {
					continue;
				}
				yield this.fill_node(view, node, fields.get(key));
				found = true;
				break;
			}
			if (found) {
				continue;
			}
			throw new GLib.IOError.INVALID_ARGUMENT("Unknown fill key %s", key);
		}
	}

	/**
	 * Click one dump node and paste {{{typed}}} (trailing newline → Return).
	 *
	 * @param view WebView for GDK scale and clipboard
	 * @param node matched a11y node (fill_key already checked by caller)
	 * @param typed fill text for this key
	 * @throws GLib.Error when click or keys fail
	 */
	private async void fill_node(Gtk.Widget view, OLLMwebkit.A11yNode node, string typed) throws GLib.Error
	{
		var scale = int.max(1, view.scale_factor);
		var view_x = (node.x + node.width / 2) / scale;
		var view_y = (node.y + node.height / 2) / scale;
		GLib.debug("fill key=%s a11y=%d,%d %dx%d view=%d,%d",
			node.fill_key, node.x, node.y, node.width, node.height, view_x, view_y);
		yield this.click(view, view_x, view_y);
		var text = typed;
		var press_return = text.has_suffix("\n");
		if (press_return) {
			text = text.substring(0, text.length - 1);
			if (text.has_suffix("\r")) {
				text = text.substring(0, text.length - 1);
			}
		}
		view.get_clipboard().set_text(text);
		this.paste_text = text;
		GLib.debug("fill paste key=%s return=%s chars=%d",
			node.fill_key, press_return.to_string(), (int) text.char_count());
		var select_all = new OLLMwebkit.WebDriverKeys() {
			handle = this.session_id,
		};
		select_all.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyPress",
			key = "Control",
		});
		select_all.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "InsertByKey",
			text = "a",
		});
		select_all.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyRelease",
			key = "Control",
		});
		yield this.send("performKeyboardInteractions", select_all);
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 120), () => {
			this.fill_node.callback();
			return false;
		});
		yield;
		var paste = new OLLMwebkit.WebDriverKeys() {
			handle = this.session_id,
		};
		paste.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyPress",
			key = "Control",
		});
		paste.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "InsertByKey",
			text = "v",
		});
		paste.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyRelease",
			key = "Control",
		});
		yield this.send("performKeyboardInteractions", paste);
		if (!press_return) {
			return;
		}
		GLib.Timeout.add(220 + GLib.Random.int_range(0, 280), () => {
			this.fill_node.callback();
			return false;
		});
		yield;
		var ret = new OLLMwebkit.WebDriverKeys() {
			handle = this.session_id,
		};
		ret.interactions.add(new OLLMwebkit.WebDriverKey() {
			kind = "KeyPress",
			key = "Return",
		});
		yield this.send("performKeyboardInteractions", ret);
		GLib.Timeout.add(180 + GLib.Random.int_range(0, 220), () => {
			this.fill_node.callback();
			return false;
		});
		yield;
	}

	/**
	 * Click a press-ref at a11y WINDOW coords (WebView viewport).
	 *
	 * @param a11y dump whose {{{nodes}}} hold press-ref coordinates
	 * @param view WebView for GDK scale
	 * @param press_id press-ref from the last dump
	 * @throws GLib.Error when attach, locate, or click fails
	 */
	public async void press(OLLMwebkit.A11y a11y, Gtk.Widget view, int press_id) throws GLib.Error
	{
		yield this.attach();
		foreach (var node in a11y.nodes) {
			if (node.press_id != press_id) {
				continue;
			}
			var scale = int.max(1, view.scale_factor);
			var view_x = (node.x + node.width / 2) / scale;
			var view_y = (node.y + node.height / 2) / scale;
			GLib.debug("press press_id=%d a11y=%d,%d %dx%d view=%d,%d",
				press_id, node.x, node.y, node.width, node.height, view_x, view_y);
			yield this.click(view, view_x, view_y);
			return;
		}
		throw new GLib.IOError.INVALID_ARGUMENT("Unknown press-ref %d", press_id);
	}
}
```

---

## 3. `libocwebkit/cdp/WebDriver.vala` — CDP `WebDriver` (Windows + Android)

**Why:** Windows / Android have no RemoteInspector GVariant socket. Hosts listen as CDP on `WEBKIT_INSPECTOR_SERVER`. Meson compiles **this** file (not `linux/WebDriver.vala`) as `OLLMwebkit.WebDriver`.

**Where:** new file under `libocwebkit/cdp/`; Meson adds it when `windows` **or** `android`.

**Depends on:** §1.

**Approved methods:** `prepare`, `attach`, `await_cdp`, `write`, `send`, `new_session`, `delete_session`, `click`, `fill`, `fill_node`, `press`, `mouse`, `keyboard`, `key_press`, `key_release`, `insert_key`, `open_page`, `ingest`.

**🔷** Same class name as Linux — **not** `WebDriverCdp`. No subclass; one complete class per transport file.

**🔷** `await_cdp` — the former `if (!this.listening) { … }` block inside `attach` (poll `/json/version`, then `open_page`).

**🔷** `fill` / `fill_node` / `click` / `press` / `prepare` match the Linux file shapes (copy those method bodies; CDP `click` may set `page_uri` from `((WebView) view).get_uri()` before `base`-less mouse work).

**🔷** Ctrl+V expands to `Input.insertText` with `paste_text`.

**ℹ️** The fence below still shows the old subclass shape in places — **implement as a standalone `public class OLLMwebkit.WebDriver`**, include `prepare` / `fill` / `fill_node` / `press` / `click` from §2, rename overrides to ordinary methods, and extract `await_cdp` as follows.

### 3.1 `attach` — call `await_cdp` when not listening

**Where:** start of CDP `attach` after the attaching/session early returns.

#### Remove (inline listen block)

```vala
		if (!this.listening) {
			this.http.set_timeout(2);
			var version_ok = false;
			for (var i = 0; i < 50; i++) {
				var version_url = "http://127.0.0.1:"
					+ this.inspector_port.to_string() + "/json/version";
				var version_msg = new Soup.Message("GET", version_url);
				try {
					yield this.http.send_and_read_async(
						version_msg, GLib.Priority.DEFAULT, null
					);
				} catch (GLib.Error connect_error) {
					GLib.Timeout.add(200, () => {
						this.attach.callback();
						return false;
					});
					yield;
					continue;
				}
				if (version_msg.status_code == 200) {
					version_ok = true;
					break;
				}
				GLib.Timeout.add(200, () => {
					this.attach.callback();
					return false;
				});
				yield;
			}
			this.http.set_timeout(8);
			if (!version_ok) {
				this.attaching = false;
				this.attached();
				GLib.warning("cdp: /json/version not ready");
				return;
			}
			try {
				yield this.open_page();
			} catch (GLib.Error open_error) {
				this.attaching = false;
				this.attached();
				GLib.warning("%s", open_error.message);
				return;
			}
		}
```

#### Replace with

```vala
		if (!this.listening) {
			if (!yield this.await_cdp()) {
				return;
			}
		}
```

#### Add — `await_cdp` method on CDP `WebDriver`

**Where:** after `attach` in `cdp/WebDriver.vala`.

**What:** poll `/json/version`, then `open_page`; return false on failure (caller already cleared attaching).

```vala
	/**
	 * Wait for CDP {{{/json/version}}} and open the page WebSocket.
	 *
	 * @return false when version never becomes ready or {{{open_page}}} fails
	 */
	private async bool await_cdp()
	{
		this.http.set_timeout(2);
		var version_ok = false;
		for (var i = 0; i < 50; i++) {
			var version_url = "http://127.0.0.1:"
				+ this.inspector_port.to_string() + "/json/version";
			var version_msg = new Soup.Message("GET", version_url);
			try {
				yield this.http.send_and_read_async(
					version_msg, GLib.Priority.DEFAULT, null
				);
			} catch (GLib.Error connect_error) {
				GLib.Timeout.add(200, () => {
					this.await_cdp.callback();
					return false;
				});
				yield;
				continue;
			}
			if (version_msg.status_code == 200) {
				version_ok = true;
				break;
			}
			GLib.Timeout.add(200, () => {
				this.await_cdp.callback();
				return false;
			});
			yield;
		}
		this.http.set_timeout(8);
		if (!version_ok) {
			this.attaching = false;
			this.attached();
			GLib.warning("cdp: /json/version not ready");
			return false;
		}
		try {
			yield this.open_page();
		} catch (GLib.Error open_error) {
			this.attaching = false;
			this.attached();
			GLib.warning("%s", open_error.message);
			return false;
		}
		return true;
	}
```

#### Add — full CDP transport file (reference body)

The remainder of the former `WebDriverCdp` fence (write / send / mouse / keyboard / open_page / ingest) stays, but:

- **🔷** Class line is `public class OLLMwebkit.WebDriver : Object` (not `WebDriverCdp : WebDriver`).
- **🔷** Drop `override` keywords; include full `prepare` / `fill` / `fill_node` / `press` / `click` / `new_session` from §2.
- **🔷** `click` sets `this.page_uri = ((WebView) view).get_uri();` then runs the shared wander+click body (platform `using` supplies `WebView`).
- **🔷** Do **not** leave a `WebDriverCdp` symbol anywhere.

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * CDP {{{WebDriver}}} — Chromium CDP on the loopback port
 * {{{prepare}}} advertises as {{{WEBKIT_INSPECTOR_SERVER}}}.
 *
 * Meson compiles this file for Windows and Android as
 * {{{OLLMwebkit.WebDriver}}} (not a subclass). {{{send}}} expands
 * typed Automation params to CDP {{{Input.*}}}. Include {{{prepare}}},
 * {{{fill}}}, {{{fill_node}}}, {{{press}}}, and {{{click}}} from the
 * Linux file (same bodies); use {{{await_cdp}}} from attach.
 *
 * @see OLLMwebkit.Browser
 */
public class OLLMwebkit.WebDriver : Object
{
	/* 🔷 Standalone CDP class — copy shared fields / signals from linux/WebDriver
	 * (session_id, browser_name, inspector_port, connection_id, target_id,
	 * command_id, reply_id, incoming_reply, have_reply, attaching, listening,
	 * paste_text, targeted / replied / attached) plus prepare / fill / fill_node /
	 * press / new_session. Then the CDP-only members below. */

	private Soup.Session http { get; set; default = new Soup.Session(); }
	private Soup.WebsocketConnection sock;
	private string page_uri = "";
	private string page_opened = "";
	private string inbox_text = "";

	construct
	{
		this.http.set_timeout(8);
	}

	/**
	 * Wait for CDP, open the page WebSocket, then StartAutomationSession
	 * → Setup → {{{new_session}}}.
	 */
	public async void attach()
	{
		if (this.session_id != "") {
			return;
		}
		if (this.attaching) {
			var wait_id = 0UL;
			wait_id = this.attached.connect(() => {
				this.disconnect(wait_id);
				this.attach.callback();
			});
			yield;
			if (this.session_id != "") {
				return;
			}
		}
		this.attaching = true;
		this.target_id = 0;
		this.connection_id = 0;
		if (!this.listening) {
			if (!yield this.await_cdp()) {
				return;
			}
		}
		var caps = new GLib.VariantBuilder(new GLib.VariantType("a{sv}"));
		this.write("StartAutomationSession",
			new GLib.Variant("(s@a{sv})", this.browser_name, caps.end()));
		var target_wait = 0UL;
		target_wait = this.targeted.connect(() => {
			this.disconnect(target_wait);
			this.attach.callback();
		});
		yield;
		if (this.target_id == 0) {
			this.attaching = false;
			this.attached();
			GLib.warning("inspector: no automation target");
			return;
		}
		this.write("Setup", new GLib.Variant("(tt)", this.connection_id, this.target_id));
		try {
			yield this.new_session();
		} catch (GLib.Error session_error) {
			this.attaching = false;
			this.attached();
			GLib.warning("%s", session_error.message);
			return;
		}
		this.attaching = false;
		this.attached();
	}

	protected void write(string name, GLib.Variant parameters)
	{
		if (!this.listening) {
			return;
		}
		switch (name) {
			case "StartAutomationSession":
				this.connection_id = 1;
				this.target_id = 1;
				GLib.Idle.add(() => {
					this.targeted();
					return false;
				});
				return;
			case "Setup":
			case "FrontendDidClose":
			case "SendMessageToBackend":
				return;
			default:
				return;
		}
	}

	/**
	 * Expand typed Automation params to CDP {{{Input.*}}}
	 * (no JSON round-trip through {{{write}}}).
	 */
	public async OLLMwebkit.WebDriverValue send(
		string method,
		GLib.Object parameters
	) throws GLib.Error {
		yield this.open_page();
		if (method == "getBrowsingContexts") {
			var result = new OLLMwebkit.WebDriverValue();
			result.contexts.add(new OLLMwebkit.WebDriverValue() {
				handle = "cdp",
			});
			return new OLLMwebkit.WebDriverValue() {
				result = result,
			};
		}
		var out_calls = new Gee.ArrayList<OLLMwebkit.WebDriverCall>();
		switch (method) {
			case "performMouseInteraction":
				this.mouse((OLLMwebkit.WebDriverMouse) parameters, out_calls);
				break;
			case "performKeyboardInteractions":
				this.keyboard((OLLMwebkit.WebDriverKeys) parameters, out_calls);
				break;
			default:
				throw new GLib.IOError.FAILED("cdp: unknown method %s", method);
		}
		if (out_calls.size == 0) {
			throw new GLib.IOError.FAILED("cdp: empty expand");
		}
		this.have_reply = false;
		var wait_id = 0UL;
		wait_id = this.replied.connect(() => {
			this.disconnect(wait_id);
			this.send.callback();
		});
		for (var i = 0; i < out_calls.size; i++) {
			this.command_id++;
			out_calls.get(i).id = this.command_id;
			if (i == out_calls.size - 1) {
				this.reply_id = this.command_id;
			}
			this.sock.send_text(Json.gobject_to_data(out_calls.get(i), null));
		}
		yield;
		if (!this.have_reply) {
			throw new GLib.IOError.FAILED("inspector: no reply");
		}
		if (this.incoming_reply.failed) {
			throw new GLib.IOError.FAILED("inspector: %s %s",
				this.incoming_reply.name, this.incoming_reply.message);
		}
		return this.incoming_reply;
	}

	public async void delete_session() throws GLib.Error
	{
		if (this.session_id == "") {
			return;
		}
		this.write("FrontendDidClose",
			new GLib.Variant("(tt)", this.connection_id, this.target_id));
		this.session_id = "";
	}

	public async void click(Gtk.Widget view, int x, int y) throws GLib.Error
	{
		this.page_uri = ((WebView) view).get_uri();
		/* Inline the same wander + performMouseInteraction body as linux/WebDriver.click — do not add a click_at helper. */
		if (this.session_id == "") {
			throw new GLib.IOError.FAILED("inspector: no session");
		}
		var start_x = (x + GLib.Random.int_range(-220, -40)).clamp(8, int.max(8, x));
		var start_y = (y + GLib.Random.int_range(48, 200)).clamp(8, y + 240);
		var mid_x = ((start_x + x) / 2) + GLib.Random.int_range(-40, 41);
		var mid_y = ((start_y + y) / 2) + GLib.Random.int_range(-28, 29);
		GLib.debug("click wander %d,%d %d,%d click %d,%d", start_x, start_y, mid_x, mid_y, x, y);
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() { x = start_x, y = start_y },
			button = "None",
			interaction = "Move",
		});
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 80), () => {
			this.click.callback();
			return false;
		});
		yield;
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() { x = mid_x, y = mid_y },
			button = "None",
			interaction = "Move",
		});
		GLib.Timeout.add(80 + GLib.Random.int_range(0, 80), () => {
			this.click.callback();
			return false;
		});
		yield;
		yield this.send("performMouseInteraction", new OLLMwebkit.WebDriverMouse() {
			handle = this.session_id,
			position = new OLLMwebkit.WebDriverPoint() { x = x, y = y },
			button = "Left",
			interaction = "SingleClick",
		});
		GLib.Timeout.add(180 + GLib.Random.int_range(0, 220), () => {
			this.click.callback();
			return false;
		});
		yield;
	}

	private void mouse(OLLMwebkit.WebDriverMouse mouse, Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls)
	{
		switch (mouse.interaction) {
			case "Move":
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.dispatchMouseEvent",
					params = new OLLMwebkit.WebDriverCdpMouse() {
						kind = "mouseMoved",
						x = mouse.position.x,
						y = mouse.position.y,
						button = "none",
					},
				});
				break;
			case "SingleClick":
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.dispatchMouseEvent",
					params = new OLLMwebkit.WebDriverCdpMouse() {
						kind = "mouseMoved",
						x = mouse.position.x,
						y = mouse.position.y,
						button = "none",
					},
				});
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.dispatchMouseEvent",
					params = new OLLMwebkit.WebDriverCdpMouse() {
						kind = "mousePressed",
						x = mouse.position.x,
						y = mouse.position.y,
						button = "left",
						buttons = 1,
						click_count = 1,
					},
				});
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.dispatchMouseEvent",
					params = new OLLMwebkit.WebDriverCdpMouse() {
						kind = "mouseReleased",
						x = mouse.position.x,
						y = mouse.position.y,
						button = "left",
						click_count = 1,
					},
				});
				break;
		}
	}

	private void keyboard(OLLMwebkit.WebDriverKeys keys, Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls)
	{
		var modifiers = 0;
		foreach (var step in keys.interactions) {
			switch (step.kind) {
				case "KeyPress":
					this.key_press(step, out_calls, ref modifiers);
					break;
				case "KeyRelease":
					this.key_release(step, out_calls, ref modifiers);
					break;
				case "InsertByKey":
					this.insert_key(step, out_calls, modifiers);
					break;
			}
		}
	}

	private void key_press(
		OLLMwebkit.WebDriverKey step,
		Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls,
		ref int modifiers
	) {
		switch (step.key) {
			case "Control":
				modifiers = 2;
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.dispatchKeyEvent",
					params = new OLLMwebkit.WebDriverCdpKey() {
						kind = "keyDown",
						key = "Control",
						code = "ControlLeft",
						modifiers = 2,
						windows_virtual_key_code = 17,
						native_virtual_key_code = 17,
					},
				});
				break;
			case "Return":
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.dispatchKeyEvent",
					params = new OLLMwebkit.WebDriverCdpKey() {
						kind = "keyDown",
						key = "Enter",
						code = "Enter",
						windows_virtual_key_code = 13,
						native_virtual_key_code = 13,
					},
				});
				out_calls.add(new OLLMwebkit.WebDriverCall() {
					method = "Input.dispatchKeyEvent",
					params = new OLLMwebkit.WebDriverCdpKey() {
						kind = "keyUp",
						key = "Enter",
						code = "Enter",
						windows_virtual_key_code = 13,
						native_virtual_key_code = 13,
					},
				});
				break;
		}
	}

	private void key_release(
		OLLMwebkit.WebDriverKey step,
		Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls,
		ref int modifiers
	) {
		if (step.key != "Control") {
			return;
		}
		out_calls.add(new OLLMwebkit.WebDriverCall() {
			method = "Input.dispatchKeyEvent",
			params = new OLLMwebkit.WebDriverCdpKey() {
				kind = "keyUp",
				key = "Control",
				code = "ControlLeft",
				windows_virtual_key_code = 17,
				native_virtual_key_code = 17,
			},
		});
		modifiers = 0;
	}

	private void insert_key(
		OLLMwebkit.WebDriverKey step,
		Gee.ArrayList<OLLMwebkit.WebDriverCall> out_calls,
		int modifiers
	) {
		if (modifiers == 2 && step.text == "v") {
			out_calls.add(new OLLMwebkit.WebDriverCall() {
				method = "Input.insertText",
				params = new OLLMwebkit.WebDriverCdpText() {
					text = this.paste_text,
				},
			});
			return;
		}
		if (step.text != "a") {
			return;
		}
		out_calls.add(new OLLMwebkit.WebDriverCall() {
			method = "Input.dispatchKeyEvent",
			params = new OLLMwebkit.WebDriverCdpKey() {
				kind = "keyDown",
				key = "a",
				code = "KeyA",
				modifiers = modifiers,
				windows_virtual_key_code = 65,
				native_virtual_key_code = 65,
			},
		});
		out_calls.add(new OLLMwebkit.WebDriverCall() {
			method = "Input.dispatchKeyEvent",
			params = new OLLMwebkit.WebDriverCdpKey() {
				kind = "keyUp",
				key = "a",
				code = "KeyA",
				modifiers = modifiers,
				windows_virtual_key_code = 65,
				native_virtual_key_code = 65,
			},
		});
	}

	private async void open_page() throws GLib.Error
	{
		if (this.listening && this.page_uri == this.page_opened) {
			return;
		}
		if (this.listening) {
			this.sock.close(Soup.WebsocketCloseCode.NORMAL, "");
			this.listening = false;
		}
		var list_url = "http://127.0.0.1:" + this.inspector_port.to_string() + "/json/list";
		var list_msg = new Soup.Message("GET", list_url);
		var list_bytes = yield this.http.send_and_read_async(
			list_msg, GLib.Priority.DEFAULT, null
		);
		if (list_msg.status_code != 200) {
			throw new GLib.IOError.FAILED("cdp: /json/list HTTP %u", list_msg.status_code);
		}
		var parser = new Json.Parser();
		parser.load_from_data((string) list_bytes.get_data(), (ssize_t) list_bytes.get_size());
		var root = parser.get_root();
		if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
			throw new GLib.IOError.FAILED("cdp: /json/list is not an array");
		}
		var arr = root.get_array();
		var picked = "";
		var picked_url = "";
		var fallback = "";
		var fallback_url = "";
		for (var i = 0; i < arr.get_length(); i++) {
			var o = arr.get_object_element(i);
			if (o == null) {
				continue;
			}
			if (o.get_string_member_with_default("type", "") != "page") {
				continue;
			}
			var url = o.get_string_member_with_default("url", "");
			var ws = o.get_string_member_with_default("webSocketDebuggerUrl", "");
			if (ws == "") {
				continue;
			}
			if (fallback == "") {
				fallback = ws;
				fallback_url = url;
			}
			if (this.page_uri == "") {
				continue;
			}
			if (url != this.page_uri && !url.has_prefix(this.page_uri)
					&& !this.page_uri.has_prefix(url)) {
				continue;
			}
			picked = ws;
			picked_url = url;
			break;
		}
		if (picked == "") {
			picked = fallback;
			picked_url = fallback_url;
		}
		if (picked == "") {
			throw new GLib.IOError.NOT_FOUND("cdp: no page in /json/list");
		}
		GLib.debug("cdp page url=%s want=%s", picked_url, this.page_uri);
		var http_ws = picked.replace("ws://", "http://").replace("wss://", "https://");
		var ws_msg = new Soup.Message("GET", http_ws);
		this.sock = yield this.http.websocket_connect_async(
			ws_msg, null, null, GLib.Priority.DEFAULT, null
		);
		this.sock.message.connect((type, message) => {
			if (type != Soup.WebsocketDataType.TEXT) {
				return;
			}
			this.inbox_text = (string) message.get_data();
			this.ingest();
		});
		this.sock.closed.connect(() => {
			this.listening = false;
			this.session_id = "";
			this.target_id = 0;
			this.replied();
			this.targeted();
		});
		this.listening = true;
		this.page_opened = this.page_uri;
	}

	private void ingest()
	{
		try {
			this.incoming_reply = (OLLMwebkit.WebDriverValue) Json.gobject_from_data(
				typeof (OLLMwebkit.WebDriverValue), this.inbox_text, -1
			);
		} catch (GLib.Error json_error) {
			GLib.warning("%s", json_error.message);
			return;
		}
		if (this.incoming_reply.id != this.reply_id) {
			return;
		}
		this.have_reply = true;
		this.replied();
	}
}
```

---

## 4. Platform `WebViewAuto` files (new)

**Why:** Construct-only `is_controlled_by_automation` + `create-web-view` must return the **same** primary view. Three files — only the `using` line differs (no `#ifdef` soup in one file).

**Where:**

- `libocwebkit/linux/WebViewAuto.vala` — `using WebKit;`
- `libocwebkit/windows/WebViewAuto.vala` — `using WebView2Gtk;`
- `libocwebkit/android/WebViewAuto.vala` — `using WebKitGtkAndroid;`

**Depends on:** none (constructed from `Browser`).

**Approved type:** `OLLMwebkit.WebViewAuto` with constructor `WebViewAuto(Browser browser)` — same in each file.

#### Add — body (identical in all three files after the `using` line)

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/* Platform file: set the matching using line only —
 * linux: using WebKit;
 * windows: using WebView2Gtk;
 * android: using WebKitGtkAndroid;
 */

/**
 * WebView constructed for automation.
 *
 * Sets construct-only automation properties and hands
 * {{{browser.web_view}}} to the automation session.
 *
 * == Example ==
 *
 * {{{
 * this.web_view = new OLLMwebkit.WebViewAuto(this);
 * }}}
 *
 * @see OLLMwebkit.Browser
 */
public class OLLMwebkit.WebViewAuto : WebView
{
	/**
	 * @param browser owner whose {{{web_view}}} is returned when the
	 *        driver session starts
	 */
	public WebViewAuto(OLLMwebkit.Browser browser)
	{
		var context = WebContext.get_default();
		context.set_automation_allowed(true);
		Object(
			hexpand: true,
			vexpand: true,
			web_context: context,
			is_controlled_by_automation: true,
			network_session: context.get_network_session_for_automation(),
			website_policies: (WebsitePolicies) GLib.Object.new(
				typeof(WebsitePolicies),
				"autoplay", AutoplayPolicy.DENY
			)
		);
		context.automation_started.connect((session) => {
			var info = new ApplicationInfo();
			info.set_name("OLLMchat");
			info.set_version(1, 0, 0);
			session.set_application_info(info);
			session.create_web_view.connect(() => {
				return browser.web_view;
			});
			GLib.debug("automation-started session=%s", session.get_id());
		});
		this.get_settings().enable_developer_extras = true;
	}
}
```

**ℹ️** Delete the old single-file `WebViewAuto.vala` proposal that used `#if WINDOWS` / `#elif LINUX`.

---

## 5. `libocwebkit/meson.build` — platform source lists

**Why:** Compile the right `WebDriver` / `WebViewAuto` without `#ifdef` class forks (same pattern as `libocbwrap` `windows/` stubs).

**Where:** after `ocwebkit_src = files([…])`.

**Depends on:** §1–§4.

#### Add — after the `ocwebkit_src = files([…])` closing `])`

```meson
ocwebkit_src += files('WebDriverValue.vala')
if is_windows
  ocwebkit_src += files(
    'cdp/WebDriver.vala',
    'windows/WebViewAuto.vala',
  )
elif is_android_cross
  ocwebkit_src += files(
    'cdp/WebDriver.vala',
    'android/WebViewAuto.vala',
  )
else
  ocwebkit_src += files(
    'linux/WebDriver.vala',
    'linux/WebViewAuto.vala',
  )
endif
```

**🔷** `cdp/WebDriver.vala` may use a **single** top-of-file `using` select (`#if ANDROID` / `#else` → `WebKitGtkAndroid` / `WebView2Gtk`) — that is the only `#if` allowed in that transport file. Prefer not to duplicate the whole CDP class under `windows/` and `android/`.

**🚫** Do **not** add a `WebDriverCdp.vala` source name.

---

## 6. `libocwebkit/A11yParse.vala` — extents width / height; public `nodes`

**Why:** `WebDriver.fill` / `press` click the **center** of the control (`x + width/2`). Dump already calls `get_extents`; width / height were dropped.

**Where:** `A11yNode` properties; `A11yParse.nodes`; `walk_node` node initializer.

**Depends on:** none.

### 6.1 `A11yNode` — add `width` / `height`

#### Add — after `public int y { get; set; default = 0; }`

```vala
	public int width { get; set; default = 0; }
	public int height { get; set; default = 0; }
```

### 6.2 `A11yParse.nodes` — public (WebDriver walks the last dump)

#### Remove

```vala
	private Gee.ArrayList<A11yNode> nodes { get; set; default = new Gee.ArrayList<A11yNode>(); }
```

#### Replace with

```vala
	public Gee.ArrayList<A11yNode> nodes { get; set; default = new Gee.ArrayList<A11yNode>(); }
```

### 6.3 `walk_node` — copy extents size onto the node

**Where:** the `new A11yNode() { … }` initializer in `walk_node`.

#### Remove

```vala
			var node = new A11yNode() {
				x = ext.x,
				y = ext.y,
				label = label,
				value = value,
				display_role = display_role,
				heading = is_heading,
				pressable = is_pressable && fill_key == "",
				fill_key = fill_key
			};
```

#### Replace with

```vala
			var node = new A11yNode() {
				x = ext.x,
				y = ext.y,
				width = ext.width,
				height = ext.height,
				label = label,
				value = value,
				display_role = display_role,
				heading = is_heading,
				pressable = is_pressable && fill_key == "",
				fill_key = fill_key
			};
```

---

## 7. `libocwebkit/A11y.vala` — public `nodes`; drop fill / press on all platforms

**Why:** Dump still walks a11y. Fill / press leave this class everywhere — `Browser` → `WebDriver`.

**Where:** class properties; `dump_sync` assignment; **delete** `fill` / `press` / `fill_sync` / `press_sync` (do not `#if ANDROID` keep them).

**Depends on:** §6.

### 7.1 property `nodes`

#### Add — after the `html_names` property block

```vala
	/**
	 * Nodes from the last {{{dump}}} (fill_key / press_id + WINDOW coords).
	 */
	public Gee.ArrayList<A11yNode> nodes { get; private set; default = new Gee.ArrayList<A11yNode>(); }
```

### 7.2 `dump_sync` — copy parse nodes

**Where:** after `this.html_names = parse.html_names;`

#### Add — after `this.html_names = parse.html_names;`

```vala
		this.nodes = parse.nodes;
```

### 7.3 Remove `fill` / `press` / `fill_sync` / `press_sync`

**Where:** delete those four methods entirely (including Android branches).

#### Remove (class brief that claims fill/press)

```vala
 * Platform tree via ''using'' ({@link Atspi} / {@link Win32Atspi} /
 * {@link AndroidAtspi}) — same shape as {@link A11yParse}. Linux offsloads
 * AT-SPI dump/fill/press to a GLib worker (main-thread AT-SPI deadlocks;
 * set ''GTK_A11Y=atspi'' before GTK init). Windows stays on the UI thread
 * (COM). Android yields {@link AndroidAtspi.refresh_async} first so the
 * host walk runs on the Android UI thread without GTK sync-waiting (IME
 * ''blockForMain'' ANR — webkitgtk-android
 * ''2026-07-23-a11y-walk-gtk-thread-anr''). No page JavaScript.
```

#### Replace with

```vala
 * Platform tree via ''using'' ({@link Atspi} / {@link Win32Atspi} /
 * {@link AndroidAtspi}) — same shape as {@link A11yParse}. Dump stays
 * a11y. Linux offsloads AT-SPI dump to a GLib worker (main-thread AT-SPI
 * deadlocks; set ''GTK_A11Y=atspi'' before GTK init). Windows dump stays
 * on the UI thread (COM). Android yields {@link AndroidAtspi.refresh_async}
 * first so the host walk runs on the Android UI thread without GTK
 * sync-waiting (IME ''blockForMain'' ANR — webkitgtk-android
 * ''2026-07-23-a11y-walk-gtk-thread-anr''). Fill and press go through
 * {@link WebDriver} on every platform. No page JavaScript.
```

#### Remove (example that calls fill/press on `A11y`)

```vala
 * var a11y = new OLLMwebkit.A11y();
 * var md = yield a11y.dump(uri, title);
 * yield a11y.fill(fields);
 * yield a11y.press(3);
```

#### Replace with

```vala
 * var a11y = new OLLMwebkit.A11y();
 * var md = yield a11y.dump(uri, title);
```

**🔷** Delete the four method bodies in full (no `#if ANDROID` wrappers).

---

## 8. `libocwebkit/Browser.vala` — `WebViewAuto`; fill / press → `WebDriver`

**Why:** Primary view must be automation-controlled; tool fill / press must not call a11y Action.

**Where:** constructor WebView creation; `fill` / `press` methods; class doc.

**Depends on:** §2–§4, §7.

### 8.1 constructor — always `WebViewAuto`

**Where:** `public Browser(…)` — the `this.web_view = new WebView()` assignment.

#### Remove

```vala
		this.web_view = new WebView() {
			hexpand = true,
			vexpand = true,
		};
```

#### Replace with

```vala
		this.web_view = new WebViewAuto(this);
```

### 8.2 `fill` — always WebDriver

**Where:** method `fill`.

#### Remove

```vala
	public async void fill(Gee.HashMap<string, string> fields) throws GLib.Error
	{
		yield this.a11y.fill(fields);
	}
```

#### Replace with

```vala
	public async void fill(Gee.HashMap<string, string> fields) throws GLib.Error
	{
		if (this.get_root() is Gtk.Window) {
			((Gtk.Window) this.get_root()).present();
		}
		yield OLLMwebkit.WebDriver.instance.fill(this.a11y, this.web_view, fields);
	}
```

### 8.3 `press` — always WebDriver

**Where:** method `press`.

#### Remove

```vala
	public async void press(int id) throws GLib.Error
	{
		yield this.a11y.press(id);
	}
```

#### Replace with

```vala
	public async void press(int id) throws GLib.Error
	{
		yield OLLMwebkit.WebDriver.instance.press(this.a11y, this.web_view, id);
	}
```

### 8.4 class doc

Dump still via {@link A11y}. Fill and press via {@link WebDriver} on every platform.

---

## 9. `libocwebkit/BrowserStack.vala` — `attach()` after primary exists

**Why:** Inspector target exists only once the automation WebView is constructed.

**Where:** constructor, after `this.primary = new OLLMwebkit.Browser(this);` and stack add.

**Depends on:** §2, §8, §11 (`instance` set in `main` before any `BrowserStack`).

#### Add — after `this.stack.visible_child = this.primary;`

```vala
		OLLMwebkit.WebDriver.instance.attach.begin((obj, res) => {
			try {
				OLLMwebkit.WebDriver.instance.attach.end(res);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		});
```

---

## 10. `libocwebkit/examples/oc-test-webkit.vala` — `prepare()` before WebKit

**Why:** `WEBKIT_INSPECTOR_SERVER` must be set before the first WebView.

**Where:** `int main` (not `run_test`).

**Depends on:** §2, §3.

#### Remove

```vala
int main(string[] args)
{
	var app = new OcTestWebkitApp();
	return app.run(args);
}
```

#### Replace with

```vala
int main(string[] args)
{
	OLLMwebkit.WebDriver.instance = new OLLMwebkit.WebDriver();
	try {
		OLLMwebkit.WebDriver.instance.prepare();
	} catch (GLib.Error e) {
		GLib.warning("%s", e.message);
	}
	var app = new OcTestWebkitApp();
	return app.run(args);
}
```

---

## 11. `ollmapp` mains — `prepare()` before `app.run`

**Why:** Chat `Tool` constructs `BrowserStack` after activate; inspector env must already be set. Meson already picked the right `WebDriver` implementation.

**Where:**

- `ollmapp/Application.vala` — desktop `int main`
- `ollmapp/android/OllmchatWindow.vala` — Android `int main`

**Depends on:** §2, §3.

### 11.1 Desktop `Application.vala`

#### Remove

```vala
	int main(string[] args)
	{
		var app = new OllmchatApplication();
		return app.run(args);
	}
```

#### Replace with

```vala
	int main(string[] args)
	{
		OLLMwebkit.WebDriver.instance = new OLLMwebkit.WebDriver();
		try {
			OLLMwebkit.WebDriver.instance.prepare();
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
		}
		var app = new OllmchatApplication();
		return app.run(args);
	}
```

### 11.2 Android `OllmchatWindow.vala` `main`

**Where:** after TLS module setup, before `new AndroidApplication()`.

#### Add — before `var app = new AndroidApplication();`

```vala
		OLLMwebkit.WebDriver.instance = new OLLMwebkit.WebDriver();
		try {
			OLLMwebkit.WebDriver.instance.prepare();
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
		}
```

---

## 12. `docs/meson.build` — valadoc inputs

**Why:** New public types.

**Where:** `libocwebkit` source list (Linux valadoc).

**Depends on:** §1, §2, §4.

#### Add — after `'../libocwebkit/Tool.vala',`

```meson
    '../libocwebkit/WebDriverValue.vala',
    '../libocwebkit/linux/WebDriver.vala',
    '../libocwebkit/linux/WebViewAuto.vala',
```

**🚫** Do not list `cdp/WebDriver.vala` or Windows/Android `WebViewAuto` on the Linux valadoc pass.

---

## LLM notes

- Standard-priority **proposed** plan. Android sibling Phase 0+1 is ready — include Android in this wire (same CDP `WebDriver` as Windows).
- Platform classes via **Meson file lists**, not `#ifdef` picking `WebDriverCdp` vs `WebDriver`. Always `new WebDriver()`.
- Approved helpers only: `ingest_message`, `fill_node`, `await_cdp`.
- Dump stays a11y. Do not replace dump with page source / Find Element / `evaluate_javascript`.
- Do not spawn `WebKitWebDriver`. Do not hide `navigator.webdriver`.
- Inspector listen is `127.0.0.1` only.
- Fill keys are HTML `name=` / `id=` (`fill_key`), not press-ref integers.
- Linux click/sendKeys need a WebKitGTK 6.0 **with interactions**; empty `unsupported operation` means the distro lib, not a missing Vala call.
- Do not add an on-WebView pointer overlay unless the user asks.
