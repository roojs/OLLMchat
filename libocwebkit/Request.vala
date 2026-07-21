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
 * Deserialized ''browser'' tool call parameters and execution.
 */
public class OLLMwebkit.Request : OLLMchat.Tool.RequestBase
{
	public string action { get; set; default = ""; }
	public string topic { get; set; default = ""; }
	public string url { get; set; default = ""; }

	/**
	 * Optional download label (e.g. WebKit suggested filename). Empty → derive from url path.
	 */
	public string download_display_name { get; set; default = ""; }

	public string query { get; set; default = ""; }
	public int press { get; set; default = 0; }
	public string format { get; set; default = "a11y"; }

	/**
	 * Optional fill map for action ''press'': press-ref id (string key) → text to type.
	 */
	public Gee.HashMap<string, string> fill {
		get;
		set;
		default = new Gee.HashMap<string, string>();
	}

	public Request()
	{
	}

	public override bool deserialize_property(
		string property_name,
		out GLib.Value value,
		GLib.ParamSpec pspec,
		Json.Node property_node
	)
	{
		if (property_name != "fill") {
			return this.default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
		this.fill.clear();
		if (property_node.get_node_type() == Json.NodeType.OBJECT) {
			var obj = property_node.get_object();
			foreach (var key in obj.get_members()) {
				this.fill.set(key, obj.get_string_member(key));
			}
		}
		value = GLib.Value(typeof(Gee.HashMap));
		value.set_object(this.fill);
		return true;
	}

	public override string to_summary()
	{
		switch (this.action.strip().down()) {
			case "help":
			case "":
				if (this.topic.strip() != "") {
					return "help topic=" + this.topic.strip();
				}
				return "help";

			case "search":
				return "search " + this.query.strip();

			case "fetch":
			case "download":
				return this.action.strip().down() + " " + this.url.strip();

			case "press":
				if (((OLLMwebkit.Tool) this.tool).stack.primary.a11y.press_labels.has_key(this.press)) {
					return "press \""
						+ ((OLLMwebkit.Tool) this.tool).stack.primary.a11y.press_labels.get(this.press)
						+ "\" (#" + this.press.to_string() + ")";
				}
				return "press #" + this.press.to_string();

			case "whereami":
				return "whereami";

			default:
				return "action=" + this.action;
		}
	}

	public override bool build_perm_question()
	{
		switch (this.action.strip().down()) {
			case "press":
				if (this.press <= 0) {
					return false;
				}
				var browser = ((OLLMwebkit.Tool) this.tool).stack.primary;
				var label = "";
				if (browser.a11y.press_labels.has_key(this.press)) {
					label = browser.a11y.press_labels.get(this.press);
				}
				if (label.strip() == "") {
					label = "#" + this.press.to_string();
				}
				this.permission_target_path = "browser_press#"
					+ browser.current_uri + "#" + label + "#" + this.press.to_string();
				this.permission_operation = OLLMchat.ChatPermission.Operation.EXECUTE;
				this.permission_question = "Agent wants to press \"" + label + "\"?";
				return true;

			case "download":
				if (this.url.strip() == "") {
					return false;
				}
				var dl_url = this.url.strip();
				this.permission_target_path = "browser_download#" + dl_url;
				this.permission_operation = OLLMchat.ChatPermission.Operation.WRITE;
				var host = "";
				var path = "/";
				try {
					var uri = GLib.Uri.parse(dl_url, GLib.UriFlags.NONE);
					host = uri.get_host() != null ? uri.get_host() : "";
					path = uri.get_path() != null && uri.get_path() != ""
						? uri.get_path() : "/";
				} catch (GLib.Error e) {
					host = "";
					path = dl_url;
				}
				var file = this.download_display_name.strip();
				if (file == "") {
					file = GLib.Path.get_basename(path);
				}
				// Clear filename if it does not look like one (e.g. "download", "index").
				if (file == "" || file == "/" || file == "." || !file.contains(".")) {
					file = "";
				}
				if (file != "") {
					this.permission_question = "Agent wants to download \"" + file
						+ "\" from " + host + "?";
					return true;
				}
				this.permission_question = "Agent wants to download " + path
					+ " from " + host + "?";
				return true;

			default:
				return false;
		}
	}

	protected override async string execute_request() throws GLib.Error
	{
		var act = this.action.strip().down();
		var fmt = this.format.strip();
		if (fmt == "") {
			fmt = "a11y";
		}
		var browser = ((OLLMwebkit.Tool) this.tool).stack.primary;
		browser.agent = this.agent;
		browser.tool = this.tool;
		this.agent.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced(
				"text.oc-frame-info.collapsed browser " + this.to_summary(),
				this.to_summary())));
		var result = "";
		switch (act) {
			case "":
			case "help":
				var topic = this.topic.strip();
				if (topic == "") {
					result = (string) GLib.resources_lookup_data(
						"/ocwebkit/help.md", GLib.ResourceLookupFlags.NONE).get_data();
					break;
				}
				result = (string) GLib.resources_lookup_data(
					"/ocwebkit/help-" + topic.down() + ".md",
					GLib.ResourceLookupFlags.NONE).get_data();
				break;

			case "fetch":
				if (this.url.strip() == "") {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"url is required for fetch — call {\"action\": \"help\", \"topic\": \"fetch\"} for usage");
				}
				yield browser.load(this.url.strip());
				result = yield browser.dump(fmt);
				break;

			case "search":
				if (this.query.strip() == "") {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"query is required for search — call {\"action\": \"help\", \"topic\": \"search\"} for usage");
				}
				yield browser.load(
					"https://www.google.com/search?q="
					+ GLib.Uri.escape_string(this.query.strip())
					+ "&hl=en");
				result = yield browser.dump(fmt);
				break;

			case "whereami":
				result = yield browser.dump(fmt);
				break;

			case "press":
				if (this.fill.size > 0) {
					yield browser.fill(this.fill);
				}
				if (this.press <= 0) {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"press (integer) is required for action press — call {\"action\": \"help\", \"topic\": \"press\"} for usage");
				}
				yield browser.press(this.press);
				result = yield browser.dump(fmt);
				break;

			case "download":
				if (this.url.strip() == "") {
					throw new GLib.IOError.INVALID_ARGUMENT(
						"url is required for download — call {\"action\": \"help\", \"topic\": \"download\"} for usage");
				}
				result = yield browser.download(this.url.strip());
				break;

			default:
				throw new GLib.IOError.INVALID_ARGUMENT(
					"Unknown action: %s — call {\"action\": \"help\"} for the action list",
					this.action);
		}
		var reply_prefix = (fmt == "markdown") ? "markdown" : "text";
		this.agent.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced(
				reply_prefix + ".oc-frame-success.collapsed browser reply",
				result)));
		return result;
	}
}
