/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Markdown.Document
{

	public abstract class Node : Object, Json.Serializable
	{
		/** Set when added to a container; null for root. Exclude from JSON to avoid cycles. */
		public Node? parent { get; set; }
		public Gee.ArrayList<Node> children { get; set; 
			default = new Gee.ArrayList<Node>((a, b) => a.uid == b.uid); }

		/** Block/format kind (PARAGRAPH, HEADING_1..6, TEXT, ITALIC, etc.). Default NONE for Document, List, ListItem. */
		public FormatType kind { get; set; default = FormatType.NONE; }

		/** For JSON polymorphic deserialization of children (Document→DOCUMENT, Block→BLOCK, List→LIST, ListItem→LIST_ITEM, Format→FORMAT). */
		public virtual FormatType node_type { get; set; default = FormatType.NONE; }

		/** Unique id within the document; assigned when the node is created. Used for traversal and position lookup. */
		public int uid { get; set; default = -1; }

		/** Call when adding a child: child.parent = this (omit for Format if desired). */
		public void adopt(Node child)
		{
			this.children.add(child);
			child.parent = this;
		}

		/** Root document; null if this node is not in a document tree. */
		public Document? document()
		{
			Node? n = this;
			while (n != null) {
				if (n is Document) {
					return (Document) n;
				}
				n = n.parent;
			}
			return null;
		}

		/** Next sibling in parent's children list; null if last or no parent. */
		public Node? next()
		{
			if (this.parent == null) {
				return null;
			}
			int i = this.parent.children.index_of(this);
			if (i < 0 || i + 1 >= this.parent.children.size) {
				return null;
			}
			return this.parent.children.get(i + 1);
		}

		/** Flattened text of this node (e.g. for ListItem: first paragraph/inline subtree as single line). */
		public virtual string text_content()
		{
			string[] parts = {};
			foreach (var child in this.children) {
				if (child is Format) {
					var f = (Format) child;
					parts += f.text != "" ? f.text : child.text_content();
					continue;
				}
				if (child is Block) {
					var b = (Block) child;
					if (b.kind == FormatType.PARAGRAPH
						|| (b.kind >= FormatType.HEADING_1 && b.kind <= FormatType.HEADING_6)) {
						parts += b.text_content();
						break;
					}
					continue;
				}
				parts += child.text_content();
			}
			return string.joinv("", parts).strip();
		}

		/** Convert this node (and children) back to markdown text. Override in subclasses. */
		public virtual string to_markdown()
		{
			string result = "";
			foreach (var child in this.children) {
				result += child.to_markdown();
			}
			return result;
		}

		public override Json.Node serialize_property(string property_name, GLib.Value value, GLib.ParamSpec pspec)
		{
			switch (property_name) {
				case "headings":
					return null;
				case "parent":
					return null;
				case "node_type":
				case "node-type":
					var nt = new Json.Node(Json.NodeType.VALUE);
					nt.set_int((int)this.node_type);
					return nt;
				case "kind":
					var nk = new Json.Node(Json.NodeType.VALUE);
					nk.set_int((int)this.kind);
					return nk;
				case "children":
					var arr = new Json.Array();
					foreach (var child in this.children) {
						arr.add_element(Json.gobject_serialize(child));
					}
					var n = new Json.Node(Json.NodeType.ARRAY);
					n.init_array(arr);
					return n;
				case "task_checked":
				case "task-checked":
					if (this is ListItem) {
						var bn = new Json.Node(Json.NodeType.VALUE);
						bn.set_boolean((this as ListItem).task_checked);
						return bn;
					}
					return default_serialize_property(property_name, value, pspec);
				case "is_task_item":
				case "is-task-item":
					if (this is ListItem) {
						var bn = new Json.Node(Json.NodeType.VALUE);
						bn.set_boolean((this as ListItem).is_task_item);
						return bn;
					}
					return default_serialize_property(property_name, value, pspec);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(string property_name, out GLib.Value value, GLib.ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "headings":
					return false;
				case "parent":
					return false;
				case "node_type":
				case "node-type":
					value = GLib.Value(typeof(FormatType));
					value.set_enum((int)property_node.get_int());
					return true;
				case "kind":
					value = GLib.Value(typeof(FormatType));
					value.set_enum((int)property_node.get_int());
					return true;
				case "children":
					this.children.clear();
					var json_arr = property_node.get_array();
					for (uint i = 0; i < json_arr.get_length(); i++) {
						var child = this.deserialize_child(json_arr.get_element(i));
						if (child != null) {
							child.parent = this;
							this.children.add(child);
						}
					}
					value = GLib.Value(typeof(Gee.ArrayList));
					value.set_object(this.children);
					return true;
				case "task-checked":
					if (this is ListItem) {
						(this as ListItem).task_checked = property_node.get_boolean();
						value = GLib.Value(typeof(bool));
						value.set_boolean((this as ListItem).task_checked);
						return true;
					}
					return default_deserialize_property(property_name, out value, pspec, property_node);
				case "is-task-item":
					if (this is ListItem) {
						(this as ListItem).is_task_item = property_node.get_boolean();
						value = GLib.Value(typeof(bool));
						value.set_boolean((this as ListItem).is_task_item);
						return true;
					}
					return default_deserialize_property(property_name, out value, pspec, property_node);
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}

		/** Polymorphic child deserialization: dispatch by node_type. We write this JSON; one key, fixed format. */
		protected virtual Node? deserialize_child(Json.Node elem)
		{
			var obj = elem.get_object();
			FormatType type_val = (FormatType)(int)obj.get_member("node-type").get_int();
			switch (type_val) {
				case FormatType.DOCUMENT:
					return Json.gobject_deserialize(typeof(Document), elem) as Document;
				case FormatType.BLOCK:
					return Json.gobject_deserialize(typeof(Block), elem) as Block;
				case FormatType.LIST:
					return Json.gobject_deserialize(typeof(List), elem) as List;
				case FormatType.LIST_ITEM:
					return Json.gobject_deserialize(typeof(ListItem), elem) as ListItem;
				case FormatType.FORMAT:
					return Json.gobject_deserialize(typeof(Format), elem) as Format;
				default:
					return null;
			}
		}
	}
}
