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
