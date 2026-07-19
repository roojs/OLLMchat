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
 * One AT-SPI tree walk that builds a11y Content / References markdown.
 *
 * Create once per document with {@link root} / {@link route}. {@link walk}
 * starts recursion; {@link walk_node} converts a node then recurses into
 * children, setting {@link content}, {@link refs}, and {@link press_routes}.
 *
 * == Example ==
 *
 * {{{
 * var parse = new OLLMwebkit.A11yParse(walk_root, walk_route);
 * parse.walk();
 * var md = parse.content;
 * }}}
 */
public class OLLMwebkit.A11yParse : GLib.Object
{
	/**
	 * Document (or app) accessible to start from.
	 */
	public Atspi.Accessible root { get; construct; }

	/**
	 * Child-index path from the application root to {@link root}.
	 */
	public Gee.ArrayList<int> route {
		get;
		construct;
		default = new Gee.ArrayList<int>();
	}

	/**
	 * Press-ref id → child-index route from the AT-SPI application root.
	 */
	public Gee.HashMap<int, Gee.ArrayList<int>> press_routes {
		get;
		private set;
		default = new Gee.HashMap<int, Gee.ArrayList<int>>();
	}

	/**
	 * ## Content body (no page header).
	 */
	public string content { get; private set; default = ""; }

	/**
	 * ## References body.
	 */
	public string refs { get; private set; default = ""; }

	private int next_press = 1;

	/**
	 * @param root document (or app) accessible to start from
	 * @param route child-index path from the application root to ''root''
	 */
	public A11yParse(Atspi.Accessible root, Gee.ArrayList<int> route)
	{
		Object(root: root, route: route);
	}

	/**
	 * Recurse from {@link root} via {@link walk_node}.
	 */
	public void walk()
	{
		var name = this.root.get_name();
		var role_name = this.root.get_role_name();
		this.walk_node(
			this.root,
			this.route,
			name != null ? name : "",
			role_name != null ? role_name : ""
		);
	}

	/**
	 * Convert one accessible node, then recurse into children.
	 *
	 * @param acc node to convert
	 * @param node_route child-index path from the application root to ''acc''
	 * @param name accessible name (never null)
	 * @param role_name AT-SPI role name (never null)
	 */
	private void walk_node(
		Atspi.Accessible acc,
		Gee.ArrayList<int> node_route,
		string name,
		string role_name
	)
	{
		var display_role = role_name;
		var attrs = acc.get_attributes();
		if (attrs != null) {
			var computed = attrs.get("computed-role");
			if (computed != null && computed != "") {
				display_role = computed;
			}
			if (display_role == "form" && attrs.get("tag") == "a") {
				display_role = "link";
			}
		}

		var has_text = false;
		var has_action = false;
		var ifaces = acc.get_interfaces();
		if (ifaces != null) {
			for (var ii = 0; ii < ifaces.length; ii++) {
				if (ifaces.index(ii) == "Text") {
					has_text = true;
				}
				if (ifaces.index(ii) == "Action") {
					has_action = true;
				}
			}
		}

		var value = "";
		if (has_text) {
			var nchars = acc.get_text_iface().get_character_count();
			if (nchars > 0) {
				value = acc.get_text_iface().get_text(0, nchars);
			}
		}

		var label = name;
		if (value != "" && label.has_suffix(value)) {
			label = label.substring(0, label.length - value.length).strip();
		}
		label = label == "" ? value : label;
		label = label == "\uFFFC" ? "" : label;
		label = string.joinv(" ", GLib.Regex.split_simple("\\s+", label)).strip();
		value = string.joinv(" ", GLib.Regex.split_simple("\\s+", value)).strip();

		var is_pressable = false;
		switch (display_role) {
			case "button":
			case "link":
			case "textbox":
			case "searchbox":
			case "combobox":
			case "checkbox":
			case "radio":
			case "switch":
			case "tab":
			case "menuitem":
			case "entry":
			case "password text":
			case "combo box":
			case "check box":
			case "radio button":
			case "push button":
			case "embedded":
				is_pressable = has_action || has_text;
				break;

			default:
				if (role_name == "password text" || role_name == "entry") {
					is_pressable = true;
				}
				break;
		}

		var skip_emit = false;
		switch (role_name) {
			case "application":
			case "frame":
			case "panel":
			case "filler":
			case "scroll pane":
			case "redundant object":
			case "page":
			case "section":
			case "document text":
			case "document frame":
				skip_emit = label == "";
				break;
		}
		if (label.strip() == "") {
			skip_emit = true;
			is_pressable = false;
		}

		var child_count = acc.get_child_count();

		if (is_pressable) {
			var press_id = this.next_press;
			this.next_press++;
			this.press_routes.set(press_id, node_route);
			var ext = acc.get_extents(Atspi.CoordType.WINDOW);
			this.content += "[" + label + "](^press:" + press_id.to_string() + ")";
			this.content += "{" + ext.x.to_string() + "," + ext.y.to_string() + "}";
			if (value != "" && display_role != "link") {
				this.content += " = " + value;
			}
			this.content += "\n";

			var uri = "";
			if (display_role == "link") {
				var hl = acc.get_hyperlink();
				if (hl != null && hl.get_n_anchors() > 0) {
					uri = hl.get_uri(0);
				}
			}
			if (uri != "") {
				this.refs += "(^press:" + press_id.to_string() + "): [" + label + "](" + uri + ")\n";
			}
			if (uri == "" && value != "") {
				this.refs += "(^press:" + press_id.to_string() + "): [" + display_role + "] " + label + " = " + value + "\n";
			}
			if (uri == "" && value == "") {
				this.refs += "(^press:" + press_id.to_string() + "): [" + display_role + "] " + label + "\n";
			}
		}
		if (!is_pressable && !skip_emit) {
			switch (display_role) {
				case "heading":
					this.content += "\n### " + label + "\n";
					break;

				case "paragraph":
				case "text":
				case "static text":
					this.content += label + "\n";
					break;

				default:
					if (role_name == "heading") {
						this.content += "\n### " + label + "\n";
						break;
					}
					if (child_count <= 0) {
						this.content += label + "\n";
					}
					break;
			}
		}

		for (var j = 0; j < child_count; j++) {
			var child = acc.get_child_at_index(j);
			var next_route = new Gee.ArrayList<int>();
			foreach (var part in node_route) {
				next_route.add(part);
			}
			next_route.add(j);
			var child_name = child.get_name();
			var child_role = child.get_role_name();
			this.walk_node(
				child,
				next_route,
				child_name != null ? child_name : "",
				child_role != null ? child_role : ""
			);
		}
	}
}
