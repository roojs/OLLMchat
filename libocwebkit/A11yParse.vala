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
 * One registered a11y node with window coordinates for layout emit.
 */
public class OLLMwebkit.A11yNode : GLib.Object
{
	public int x { get; set; default = 0; }
	public int y { get; set; default = 0; }
	public string label { get; set; default = ""; }
	public string value { get; set; default = ""; }
	public string display_role { get; set; default = ""; }
	public string uri { get; set; default = ""; }
	public int press_id { get; set; default = 0; }
	public bool heading { get; set; default = false; }
	public bool pressable { get; set; default = false; }

	/**
	 * Content fragment for this node (heading, pressable, or plain text).
	 */
	public string to_string()
	{
		if (this.heading) {
			return @"### $(this.label)";
		}
		if (!this.pressable) {
			return this.label;
		}
		if (this.value != "" && this.display_role != "link") {
			return @"[$(this.label)](^press:$(this.press_id)){$(this.x),$(this.y)} = $(this.value)";
		}
		return @"[$(this.label)](^press:$(this.press_id)){$(this.x),$(this.y)}";
	}

	/**
	 * References line for a pressable, or empty.
	 */
	public string to_ref()
	{
		if (!this.pressable) {
			return "";
		}
		if (this.uri != "") {
			return @"(^press:$(this.press_id)): [$(this.label)]($(this.uri))\n";
		}
		if (this.value != "") {
			return @"(^press:$(this.press_id)): [$(this.display_role)] $(this.label) = $(this.value)\n";
		}
		return @"(^press:$(this.press_id)): [$(this.display_role)] $(this.label)\n";
	}
}

/**
 * One AT-SPI tree walk that builds a11y Content / References markdown.
 *
 * Create once per document with {@link root} / {@link route}. {@link walk}
 * registers nodes via {@link walk_node}, then {@link emit} lays out Content
 * by window ''y'' (same row → same line, left-to-right by ''x'').
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

	private Gee.ArrayList<A11yNode> nodes {
		get;
		set;
		default = new Gee.ArrayList<A11yNode>();
	}
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
	 * Register the tree, then emit Content / References by line.
	 */
	public void walk()
	{
		// One bottom→top pass so below-fold names fill in (no per-step jumping).
		try {
			this.root.scroll_to(Atspi.ScrollType.BOTTOM_EDGE);
			this.root.scroll_to(Atspi.ScrollType.TOP_EDGE);
		} catch (GLib.Error e) {
		}

		var name = this.root.get_name();
		var role_name = this.root.get_role_name();
		this.walk_node(
			this.root,
			this.route,
			name != null ? name : "",
			role_name != null ? role_name : ""
		);
		this.emit();
	}

	/**
	 * Lay out registered nodes: sort by ''y'' then ''x''; same ''y'' shares a line.
	 */
	private void emit()
	{
		this.nodes.sort((a, b) => {
			if (a.y != b.y) {
				return a.y - b.y;
			}
			return a.x - b.x;
		});
		this.content = "";
		this.refs = "";
		var last_y = 0;
		var have_y = false;
		foreach (var node in this.nodes) {
			if (node.heading) {
				if (this.content != "") {
					if (!this.content.has_suffix("\n")) {
						this.content += "\n";
					}
					if (!this.content.has_suffix("\n\n")) {
						this.content += "\n";
					}
				}
				this.content += node.to_string() + "\n";
				have_y = false;
				continue;
			}
			if (have_y && node.y != last_y) {
				this.content += "\n";
			}
			if (have_y && node.y == last_y && this.content != "" && !this.content.has_suffix("\n")) {
				this.content += " ";
			}
			this.content += node.to_string();
			this.refs += node.to_ref();
			last_y = node.y;
			have_y = true;
		}
		if (this.content != "" && !this.content.has_suffix("\n")) {
			this.content += "\n";
		}
	}

	/**
	 * Register one accessible node, then recurse into children.
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

		var is_heading = display_role == "heading" || role_name == "heading";
		var is_text = false;
		switch (display_role) {
			case "paragraph":
			case "text":
			case "static text":
				is_text = true;
				break;
		}
		var child_count = acc.get_child_count();
		var value = "";
		if (has_text) {
			var nchars = acc.get_text_iface().get_character_count();
			if (nchars > 0) {
				value = acc.get_text_iface().get_text(0, nchars);
			}
		}

		var label = name;
		if (label == "") {
			var desc = acc.get_description();
			label = desc != null ? desc : "";
		}
		// Editable fields often put the current value in the accessible name —
		// strip only there. Doing it for links turns "Page 2" into "Page".
		var editable = false;
		switch (display_role) {
			case "textbox":
			case "searchbox":
			case "entry":
			case "password text":
			case "combobox":
			case "combo box":
				editable = true;
				break;
		}
		if (editable && value != "" && label.has_suffix(value)) {
			label = label.substring(0, label.length - value.length).strip();
		}
		label = label == "" ? value : label;
		label = label == "\uFFFC" ? "" : label;
		label = string.joinv(" ", GLib.Regex.split_simple("\\s+", label)).strip();
		value = string.joinv(" ", GLib.Regex.split_simple("\\s+", value)).strip();

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

		if (!is_pressable && !skip_emit && !is_heading && !is_text && child_count <= 0) {
			is_text = true;
		}

		if (is_pressable || (!skip_emit && (is_heading || is_text))) {
			var ext = acc.get_extents(Atspi.CoordType.WINDOW);
			var node = new A11yNode() {
				x = ext.x,
				y = ext.y,
				label = label,
				value = value,
				display_role = display_role,
				heading = is_heading,
				pressable = is_pressable
			};
			if (is_pressable) {
				node.press_id = this.next_press;
				this.next_press++;
				this.press_routes.set(node.press_id, node_route);
				if (display_role == "link") {
					var hl = acc.get_hyperlink();
					if (hl != null && hl.get_n_anchors() > 0) {
						node.uri = hl.get_uri(0);
					}
				}
			}
			this.nodes.add(node);
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
