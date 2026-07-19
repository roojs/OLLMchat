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
		switch (this.action) {
			case "help":
			case "":
				if (this.topic != "") {
					return "help topic=" + this.topic;
				}
				return "help";
			default:
				return "action=" + this.action;
		}
	}

	protected override bool build_perm_question()
	{
		return false;
	}

	protected override async string execute_request() throws GLib.Error
	{
		var act = this.action.strip().down();
		var fmt = this.format.strip();
		if (fmt == "") {
			fmt = "a11y";
		}
		switch (act) {
			case "":
			case "help":
				var topic = this.topic.strip();
				if (topic == "") {
					return (string) GLib.resources_lookup_data(
						"/ocwebkit/help.md", GLib.ResourceLookupFlags.NONE).get_data();
				}
				return (string) GLib.resources_lookup_data(
					"/ocwebkit/help-" + topic.down() + ".md",
					GLib.ResourceLookupFlags.NONE).get_data();
			case "fetch":
				if (this.url.strip() == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("url is required for fetch");
				}
				yield ((OLLMwebkit.Tool) this.tool).stack.primary.load(this.url.strip());
				return yield ((OLLMwebkit.Tool) this.tool).stack.primary.dump(fmt);
			case "search":
				if (this.query.strip() == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("query is required for search");
				}
				yield ((OLLMwebkit.Tool) this.tool).stack.primary.load(
					"https://www.google.com/search?q=" + GLib.Uri.escape_string(this.query.strip()));
				return yield ((OLLMwebkit.Tool) this.tool).stack.primary.dump(fmt);
			case "whereami":
				return yield ((OLLMwebkit.Tool) this.tool).stack.primary.dump(fmt);
			case "press":
				if (this.fill.size > 0) {
					yield ((OLLMwebkit.Tool) this.tool).stack.primary.fill(this.fill);
				}
				if (this.press <= 0) {
					throw new GLib.IOError.INVALID_ARGUMENT("press (integer) is required for action press");
				}
				yield ((OLLMwebkit.Tool) this.tool).stack.primary.press(this.press);
				return yield ((OLLMwebkit.Tool) this.tool).stack.primary.dump(fmt);
			case "download":
				throw new GLib.IOError.NOT_SUPPORTED("%s — Phase 7", act);
			default:
				throw new GLib.IOError.INVALID_ARGUMENT("Unknown action: %s", this.action);
		}
	}
}
