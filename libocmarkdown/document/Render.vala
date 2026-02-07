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

	public class Render : Markdown.RenderBase
	{
		public Document document { get; private set; }

		/** Emitted when a block is closed (fired from pop_block before removing from stack). */
		public signal void block_ended(Document document, Block block);

		private Gee.ArrayList<Object> block_stack = new Gee.ArrayList<Object>();
		private Gee.ArrayList<Format> format_stack = new Gee.ArrayList<Format>();
		private Node? current_block_with_inlines = null;
		private Gee.ArrayList<Node> inline_target_stack { get; set;
			default = new Gee.ArrayList<Node>((a, b) => a.uid == b.uid); }
		private ListItem? current_list_item = null;
		private bool last_task_checked = false;
		private bool current_list_is_task_list = false;
		private Gee.ArrayList<uint> list_stack = new Gee.ArrayList<uint>();

		public Render()
		{
			base();
			this.document = new Document();
			this.document.uid = 0;
			this.block_stack.add(this.document);
		}

		private void pop_inline()
		{
			if (this.format_stack.size == 0) {
				return;
			}
			var top = this.format_stack.get(this.format_stack.size - 1);
			this.format_stack.remove_at(this.format_stack.size - 1);
			this.add_format_to_current(top);
		}

		private void add_format_to_current(Format f)
		{
			f.uid = this.document.uid_count++;
			if (this.format_stack.size > 0) {
				this.format_stack.get(this.format_stack.size - 1).children.add(f);
				return;
			}
			if (this.current_block_with_inlines != null) {
				this.current_block_with_inlines.children.add(f);
			}
		}

		private void add_block_to_current(Block b)
		{
			b.uid = this.document.uid_count++;
			var parent = this.block_stack.get(this.block_stack.size - 1) as Node;
			parent.adopt(b);
		}

		private void push_block(Block b)
		{
			this.add_block_to_current(b);
			this.block_stack.add(b);
			if (b.kind == FormatType.PARAGRAPH
			    || (b.kind >= FormatType.HEADING_1 && b.kind <= FormatType.HEADING_6)
			    || b.kind == FormatType.TABLE_CELL
			    || b.kind == FormatType.TABLE_HCELL
			    || b.kind == FormatType.BLOCKQUOTE) {
				if (this.current_block_with_inlines != null) {
					this.inline_target_stack.add(this.current_block_with_inlines);
				}
				this.current_block_with_inlines = b;
			}
		}

		private void push_list(List list)
		{
			list.uid = this.document.uid_count++;
			var parent = this.block_stack.get(this.block_stack.size - 1) as Node;
			parent.adopt(list);
			this.block_stack.add(list);
		}

		private void pop_block()
		{
			if (this.block_stack.size <= 1) {
				return;
			}
			var top = this.block_stack.get(this.block_stack.size - 1);
			if (top is Block) {
				this.block_ended(this.document, (Block)top);
			}
			this.block_stack.remove_at(this.block_stack.size - 1);
			if (top == this.current_block_with_inlines) {
				this.current_block_with_inlines = this.inline_target_stack.size > 0
					? this.inline_target_stack.remove_at(this.inline_target_stack.size - 1)
					: null;
			}
		}

		private void pop_list()
		{
			if (this.block_stack.size <= 1) {
				return;
			}
			this.block_stack.remove_at(this.block_stack.size - 1);
			this.current_list_item = null;
			this.current_list_is_task_list = false;
		}

		private void on_block(Block? node)
		{
			if (node == null) {
				this.pop_block();
				return;
			}
			this.push_block(node);
		}

		private void on_inline(Format? node)
		{
			if (node == null) {
				this.pop_inline();
				return;
			}
			this.format_stack.add(node);
		}

		/** Current RenderBase pipeline: one switch on type for string-based events. */
		public override void on_node(
			FormatType type,
			bool is_start, 
			string s1 = "", 
			string s2 = "", 
			string s3 = "")
		{
			switch (type) {
				case FormatType.TEXT:
					if (s1 != "") {
						this.add_format_to_current(new Format.from_text(s1));
					}
					return;
				case FormatType.IMAGE:
					this.add_format_to_current(new Format(FormatType.IMAGE) { src = s1, title = s2 });
					return;
				case FormatType.PARAGRAPH:
					this.on_block(is_start ? new Block(FormatType.PARAGRAPH) : null);
					return;
				case FormatType.HEADING_1:
				case FormatType.HEADING_2:
				case FormatType.HEADING_3:
				case FormatType.HEADING_4:
				case FormatType.HEADING_5:
				case FormatType.HEADING_6:
					this.on_block(is_start ? new Block(type) {
						 level = (uint)(type - FormatType.HEADING_1 + 1) } : null);
					return;
				case FormatType.ITALIC:
				case FormatType.BOLD:
				case FormatType.ITALIC_ASTERISK:
				case FormatType.ITALIC_UNDERSCORE:
				case FormatType.BOLD_ASTERISK:
				case FormatType.BOLD_UNDERSCORE:
				case FormatType.BOLD_ITALIC_ASTERISK:
				case FormatType.BOLD_ITALIC_UNDERSCORE:
				case FormatType.CODE:
				case FormatType.STRIKETHROUGH:
				case FormatType.U:
					this.on_inline(is_start ? new Format(type) : null);
					return;
				case FormatType.HTML:
					this.on_inline(is_start ? new Format(FormatType.HTML) {
						 tag = s1, tag_attributes = s2 } : null);
					return;
				case FormatType.OTHER:
					this.on_inline(is_start ? new Format(FormatType.OTHER) {
						 tag_name = s1 } : null);
					return;
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.on_block(is_start ? new Block(type) { lang = s1, fence_indent = s2 } : null);
					return;
				case FormatType.TABLE:
					this.on_block(is_start ? new Block(FormatType.TABLE) : null);
					return;
				case FormatType.TABLE_ROW:
					if (is_start) {
						var row = new Block(FormatType.TABLE_ROW);
						row.uid = this.document.uid_count++;
						var table = this.block_stack.get(this.block_stack.size - 1) as Node;
						table.adopt(row);
						this.block_stack.add(row);
						return;
					} 
					this.pop_block();
					return;
				case FormatType.BR:
					this.add_format_to_current(new Format(FormatType.BR));
					return;
				case FormatType.CODE_TEXT:
					var code_parent = this.block_stack.get(this.block_stack.size - 1);
					if (!(code_parent is Block)) {
						return;
					}
					var pb = (Block)code_parent;
					if (pb.kind != FormatType.FENCED_CODE_QUOTE && pb.kind != FormatType.FENCED_CODE_TILD) {
						return;
					}
					pb.code_text += s1;
					return;
				case FormatType.HORIZONTAL_RULE:
					this.add_block_to_current(new Block(FormatType.HORIZONTAL_RULE));
					return;
				case FormatType.SOFTBR:
					this.add_format_to_current(new Format.from_text("\n"));
					return;
				case FormatType.ENTITY:
					this.add_format_to_current(new Format.from_text(s1));
					return;
				case FormatType.TASK_LIST:
				case FormatType.TASK_LIST_DONE:
					// In list item with no inlines yet: this is the checkbox; set current item state (round-trip).
					if (this.current_list_item != null && this.current_list_item.children.size == 0) {
						this.current_list_item.task_checked = (type == FormatType.TASK_LIST_DONE);
						this.current_list_item.is_task_item = true;
						this.last_task_checked = (type == FormatType.TASK_LIST_DONE);
						this.current_list_is_task_list = true;
						return;
					}
					// In paragraph/heading/blockquote/table or after other inlines: emit as literal.
					this.add_format_to_current(new Format(type));
					return;
				default:
					return;
			}
		}

		/** Int/uint-based callbacks (parser calls on_node_int). */
		public override void on_node_int(FormatType type, bool is_start, int v1 = 0)
		{
			switch (type) {
				case FormatType.UNORDERED_LIST:
				case FormatType.ORDERED_LIST:
					if (is_start) {
						this.list_stack.add((uint)v1);
						this.push_list(new List() {
							ordered = (type == FormatType.ORDERED_LIST),
							indentation = (uint)v1
						});
						return;
					}
					this.list_stack.remove_at(this.list_stack.size - 1);
					this.pop_list();
					return;
				case FormatType.LIST_ITEM:
					if (is_start) {
						uint indent = (uint)v1;
						// Pop lists until we're at the right level (indent <= stack top)
						while (this.list_stack.size > 0 && indent < this.list_stack.get(this.list_stack.size - 1)) {
							this.list_stack.remove_at(this.list_stack.size - 1);
							this.pop_list();
						}
						if (this.list_stack.size > 0 && indent > this.list_stack.get(this.list_stack.size - 1)) {
							// Nested list: open under the last item of the current list (we already closed it with LIST_ITEM false)
							var current_list = this.block_stack.get(this.block_stack.size - 1) as List;
							if (current_list != null && current_list.children.size > 0) {
								var last_item = current_list.children.get(current_list.children.size - 1) as ListItem;
								if (last_item != null) {
									var nested = new List() {
										ordered = current_list.ordered,
										indentation = indent
									};
									last_item.adopt(nested);
									this.block_stack.add(nested);
									this.list_stack.add(indent);
								}
							}
						}
						var item = new ListItem() {
							task_checked = this.last_task_checked,
							is_task_item = this.current_list_is_task_list
						};
						item.uid = this.document.uid_count++;
						this.last_task_checked = false;
						var parent = this.block_stack.get(this.block_stack.size - 1) as List;
						parent.adopt(item);
						this.block_stack.add(item);
						if (this.current_block_with_inlines != null) {
							this.inline_target_stack.add(this.current_block_with_inlines);
						}
						this.current_block_with_inlines = item;
						this.current_list_item = item;
						return;
					}
					this.block_stack.remove_at(this.block_stack.size - 1);
					this.current_block_with_inlines = this.inline_target_stack.size > 0
						? this.inline_target_stack.remove_at(this.inline_target_stack.size - 1)
						: null;
					this.current_list_item = null;
					return;
				case FormatType.BLOCKQUOTE:
					this.on_block(is_start ? new Block(FormatType.BLOCKQUOTE) { 
						level = (uint)v1 } : null);
					return;
				case FormatType.TABLE_HCELL:
				case FormatType.TABLE_CELL:
					this.on_block(is_start ? new Block(type) { align = v1 } : null);
					return;
				default:
					return;
			}
		}

		/** Set task list state when BlockMap recognized - [ ] / - [x] at block level. */
		public override void on_li(bool is_start, uint indent = 0, int task_checked = -1)
		{
			if (is_start && task_checked >= 0 && this.current_list_item != null) {
				this.current_list_item.is_task_item = true;
				this.current_list_item.task_checked = (task_checked == 1);
			}
		}

		/** Only two callbacks remain public and are called directly by the parser. */
		public override void on_a(bool is_start, string href, string title, bool is_reference)
		{
			this.on_inline(is_start ? new Format(FormatType.LINK) { 
				href = href, title = title, is_reference = is_reference } : null);
		}

		public override void on_code(bool is_start, string lang, char fence_char)
		{
			var kind = (fence_char == '~') ? FormatType.FENCED_CODE_TILD : FormatType.FENCED_CODE_QUOTE;
			this.on_block(is_start ? new Block(kind) { lang = lang } : null);
		}
	}
}
