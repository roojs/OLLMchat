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

namespace MarkdownGtk
{
	/**
	 * Handles SourceView widget creation and management for code blocks.
	 * 
	 * Provides methods to create, size, and manage SourceView widgets
	 * for displaying code blocks with syntax highlighting.
	 */
	public class RenderSourceView : Object
	{
		private Render renderer;
		
		// Code block state
		private GtkSource.View? source_view = null;
		private GtkSource.Buffer? source_buffer = null;
		private string code_language = "";
		private StringBuilder code_content = new StringBuilder();
		
		// Widget references for expand/collapse functionality
		private Gtk.ScrolledWindow scrolled_window;
		private Gtk.Button expand_button;
		private Gtk.Button new_chat_button;
		
		// Phase 2: nested markdown (stack + view-source toggle)
		private Gtk.Stack stack;
		private Gtk.Box rendered_box;
		private Gtk.Button view_source_toggle;
		private bool showing_source = false;
		private Gtk.ScrolledWindow source_scrolled;  // inner scrolled for source page; used for scroll-to-bottom
		private MarkdownGtk.Render? nested_markdown_render = null;  // streamed nested renderer for ```markdown blocks
		
		private enum ResizeMode
		{
			INITIAL,    // Initial sizing: min(natural, max_height), hide button if fits
			EXPAND,     // Expanded state: natural height
			COLLAPSE,   // Collapsed state: min(natural, max_height)
			FINAL       // Final sizing when code block ends: min(natural, max_height), hide button if fits
		}
		
		/**
		 * Creates a new RenderSourceView instance and starts a code block.
		 *
		 * @param renderer The Render instance (provides access to box and
		 *        code_block_ended signal)
		 * @param language_id Info string after the fence (use "" for none).
		 *        Used for syntax highlighting and frame header.
		 */
		public RenderSourceView(Render renderer, string language_id)
		{
			this.renderer = renderer;
			this.code_content = new StringBuilder();
			
			var info = language_id.strip();
			var language = info;
			var description = "";
			var leading = language_id.has_prefix(" ") || language_id.has_prefix("\t");
			if (info != "" && leading) {
				language = "";
				description = info;
			}
			if (info != "" && !leading) {
				int p = info.index_of_char(' ');
				if (p >= 0) {
					language = info.substring(0, p);
					description = info.substring(p + 1).strip();
				}
			}
 			var header_text = (description != "") ? description :
				 ((language != "") ? language : "code");
			// Post-process language: split on ".", first part = language, rest = frame classes
			var lang_parts = language.split(".");
			language = lang_parts.length > 0 ? lang_parts[0] : language;
			this.code_language = language.down();
			string[] frame_theme_classes = lang_parts.length > 1 ?
				 lang_parts[1:lang_parts.length] : new string[0];
			bool is_user_frame = "oc-frame-user" in frame_theme_classes;




			// Create buffer with language (first token only) for syntax highlighting
			GtkSource.Buffer source_buffer;
			if (language != "") {
				var mapped_id = this.map_language_id(language);
				var lang_manager = GtkSource.LanguageManager.get_default();
				var gtk_lang = lang_manager.get_language(mapped_id);
				if (gtk_lang != null) {
					source_buffer = new GtkSource.Buffer.with_language(gtk_lang);
				} else {
					source_buffer = new GtkSource.Buffer(null);
				}
			} else {
				source_buffer = new GtkSource.Buffer(null);
			}

			// Create view
			this.source_view = new GtkSource.View() {
				editable = false,
				cursor_visible = false,
				show_line_numbers = false,  // true to debug extra lines / scrollbar
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false,
				can_focus = false,
				focus_on_click = false,
				css_classes = { "code-editor" }
			};
			this.source_view.set_buffer(source_buffer);
			this.source_buffer = source_buffer;
			this.source_buffer.implicit_trailing_newline = false;
			this.source_view.pixels_below_lines = 0;
			// GtkSource.Gutter in gtksourceview-5 has no set_padding; was removed from API

			// Set monospace font for code display using CSS
			this.source_view.add_css_class("code-editor");


			// Create widget structure and add to box
			// Create header box with title on left and buttons on right (like user messages)
			var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false,
				margin_start = 0,
				margin_end = 0,
				margin_top = 0,
				margin_bottom = 0
			};
			header_box.add_css_class("oc-frame-header");
			
			var title_label = new Gtk.Label("<b>%s</b>".printf(GLib.Markup.escape_text(header_text, -1))) {
				hexpand = true,
				halign = Gtk.Align.START,
				valign = Gtk.Align.START,
				margin_start = 9,
				margin_top = 4,
				ellipsize = Pango.EllipsizeMode.END,
				tooltip_text = header_text,
				use_markup = true
			};
			title_label.add_css_class("oc-code-frame-title");
			title_label.max_width_chars = 30;
			header_box.append(title_label);
			
			// Add spacer to push buttons to the right
			header_box.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			
			// Create horizontal box for buttons at top-right
			var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = false,
				vexpand = false
			};
			
			// Create Copy to Clipboard button with icon
			var copy_button = new Gtk.Button() {
				icon_name = "edit-copy-symbolic",
				tooltip_text = "Copy to Clipboard",
				hexpand = false,
				margin_start = 5,
				margin_end = 0,
				margin_top = 0,
				margin_bottom = 0,
				can_focus = false,
				focus_on_click = false
			};
			copy_button.clicked.connect(() => {
				this.copy_source_view_to_clipboard(this.source_buffer);
			});
			
			// Track expanded state for this code block
			bool is_expanded = false;
			
			// Create Expand/Collapse button with icon (created hidden, made visible by other code)
			var expand_button = new Gtk.Button() {
				icon_name = "pan-down-symbolic",
				tooltip_text = "Expand",
				hexpand = false,
				margin_start = 5,
				margin_end = 5,
				margin_top = 0,
				margin_bottom = 0,
				can_focus = false,
				focus_on_click = false,
				visible = false
			};
			
			// Create ScrolledWindow for the SourceView
			// Start with vexpand = true (no fixed height) - will clamp when it reaches max_height
			this.scrolled_window = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true,
				margin_start = 2
			};
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			
			// Phase 2: always create stack (rendered + source pages) and view-source toggle
			this.rendered_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = false
			};
			this.rendered_box.add_css_class("oc-nested-markdown-content");
			this.stack = new Gtk.Stack() { hexpand = true, vexpand = false };
			this.stack.add_named(this.rendered_box, "rendered");
			this.source_scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true,
				margin_start = 2
			};
			this.source_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.source_scrolled.set_child(this.source_view);
			this.stack.add_named(this.source_scrolled, "source");
			
			this.view_source_toggle = new Gtk.Button() {
				icon_name = "object-flip-horizontal-symbolic",
				tooltip_text = "View source",
				can_focus = false,
				focus_on_click = false
			};
			this.view_source_toggle.clicked.connect(() => {
				this.showing_source = !this.showing_source;
				this.stack.visible_child_name = this.showing_source ? "source" : "rendered";
				this.view_source_toggle.tooltip_text = this.showing_source ? "View rendered" : "View source";
				this.view_source_toggle.icon_name = this.showing_source ? "x-office-document-symbolic" : "object-flip-horizontal-symbolic";
				// Resize frame after a short delay so layout has settled (especially when closing render view)
				var widget_to_measure = this.showing_source ? (Gtk.Widget) this.source_view : (Gtk.Widget) this.rendered_box;
				GLib.Idle.add(() => {
					return this.resize_widget_callback(widget_to_measure, ResizeMode.INITIAL);
				});
			});
			
			// Store expand button reference
			this.expand_button = expand_button;
			
			// Connect expand/collapse button click handler
			expand_button.clicked.connect(() => {
				is_expanded = !is_expanded;
				if (is_expanded) {
					expand_button.icon_name = "pan-up-symbolic";
					expand_button.tooltip_text = "Collapse";
					GLib.Idle.add(() => {
						return this.resize_widget_callback(this.source_view, ResizeMode.EXPAND);
					});
				} else {
					expand_button.icon_name = "pan-down-symbolic";
					expand_button.tooltip_text = "Expand";
					GLib.Idle.add(() => {
						return this.resize_widget_callback(this.source_view, ResizeMode.COLLAPSE);
					});
				}
			});
			
			// Add buttons to button box (Start new chat, then copy, view-source toggle, expand)
			this.new_chat_button = new Gtk.Button() {
				icon_name = "list-add-symbolic",
				tooltip_text = "Start new chat with this",
				hexpand = false,
				margin_start = 5,
				margin_end = 5,
				can_focus = false,
				focus_on_click = false,
				visible = is_user_frame
			};
			this.new_chat_button.clicked.connect(() => {
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				this.source_buffer.get_bounds(out start_iter, out end_iter);
				var text = this.source_buffer.get_text(start_iter, end_iter, false);
				this.renderer.start_new_chat_requested(text);
			});
			button_box.append(this.new_chat_button);
			button_box.append(copy_button);
			button_box.append(this.view_source_toggle);
			button_box.append(expand_button);
			
			// Add button box to header
			header_box.append(button_box);
			
			// Create vertical container box for header and SourceView
			var container_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = false
			};
			
			// Add header box to container
			container_box.append(header_box);
			
			// Set SourceView properties
			this.source_view.hexpand = true;
			this.source_view.vexpand = false;
			
			// Add stack to ScrolledWindow (stack has "rendered" and "source" pages)
			this.scrolled_window.set_child(this.stack);
			
			// Show view-source toggle and default to rendered view only for markdown blocks
			if (this.code_language == "markdown") {
				this.view_source_toggle.visible = true;
				this.stack.visible_child_name = "rendered";
				this.nested_markdown_render = new MarkdownGtk.Render(this.rendered_box);
				this.nested_markdown_render.start();
			} else {
				this.view_source_toggle.visible = false;
				this.stack.visible_child_name = "source";
			}
			
			// Add ScrolledWindow to container
			container_box.append(this.scrolled_window);

			// Wrap in Frame for visibility and styling (no label - title is in header box)
			// Match user box structure: same margins
			var frame = new Gtk.Frame(null) {
				margin_top = 0,
				margin_bottom = 0,
				hexpand = true
			};
			frame.set_child(container_box);
			
			// Style the frame: .oc-frame is the only base; theme classes (when present) override its variables
			frame.add_css_class("oc-frame");
			foreach (var c in frame_theme_classes) {
				frame.add_css_class(c);
			}

			// Add frame to box
			this.renderer.box.append(frame);
			
			frame.set_visible(true);

			// Source view will size naturally - no fixed height
			this.source_view.set_visible(true);
		}
		
		/**
		 * Maps language identifiers to GtkSource language IDs.
		 * Handles common mistakes like 'val' -> 'vala', and matches val* patterns.
		 * 
		 * @param lang_id The language identifier from markdown code block
		 * @return The mapped language ID for GtkSource, or null if not found
		 */
		private string? map_language_id(string lang_id)
		{
			// Map val* patterns to vala (handles val, vala, valac, etc.)
			if (lang_id.has_prefix("val")) {
				return "vala";
			}
			return lang_id;
		}
		
		/**
		 * Gets the maximum collapsed height (50% of window or 300px fallback).
		 * 
		 * @return Maximum height in pixels, or 300 if window height cannot be determined
		 */
		private int get_max_collapsed_height()
		{
			// Try to get height from box's parent
			if (this.renderer.box == null) {
				return 300; // Fallback
			}
			
			var parent = this.renderer.box.get_parent();
			if (parent == null) {
				return 300; // Fallback
			}
			
			int window_height = parent.get_allocated_height();
			if (window_height <= 0) {
				return 300; // Fallback
			}
			
			return window_height / 2;
		}
		
		/**
		 * Resizes a widget (SourceView) inside a ScrolledWindow based on the specified mode.
		 * 
		 * @param widget The widget to measure (e.g., SourceView)
		 * @param scrolled_window The ScrolledWindow to resize
		 * @param mode The resize mode (INITIAL, EXPAND, COLLAPSE, or FINAL)
		 * @param expand_button Optional expand button to show/hide based on content size
		 * @return A function suitable for use with GLib.Idle.add()
		 */
		private bool resize_widget_callback(Gtk.Widget widget, ResizeMode mode)
		{
			// Check if widget is realized (e.g. hidden stack page may never be realized)
			if (!widget.get_realized()) {
				// GLib.debug("widget not realized");
				return false; // Do not retry; resize will run again when visible (e.g. view-source toggle)
			}
			// Width needed for height-for-width (e.g. SourceView with word wrap); retry if not allocated yet
			int for_width = this.scrolled_window.get_width();
			if (for_width <= 0) {
				// GLib.debug("for_width=%d, retry", for_width);
				return true;
			}
			// Get preferred height of the widget for the actual width so wrap-based height is correct
			int min_natural = 0;
			int nat_natural = 0;
			widget.measure(Gtk.Orientation.VERTICAL, for_width, out min_natural, out nat_natural, null, null);
			int natural_height = nat_natural;
			// GLib.debug("for_width=%d nat=%d", for_width, natural_height);
			
			switch (mode) {
				case ResizeMode.EXPAND:
					// Remove size constraint to allow expansion to fit content
					this.scrolled_window.set_size_request(-1, -1);
					this.scrolled_window.vexpand = true; // Allow expansion to natural height
					return false;
					
				case ResizeMode.INITIAL:
				case ResizeMode.COLLAPSE:
				case ResizeMode.FINAL:
					// Get max height (50% of window)
					int max_height = this.get_max_collapsed_height();
					int target_height = (natural_height > 0 && natural_height < max_height) ? natural_height : max_height;
					// GLib.debug("nat=%d max=%d target=%d", natural_height, max_height, target_height);
					this.scrolled_window.set_size_request(-1, target_height);
					this.scrolled_window.vexpand = false; // Prevent expansion in collapsed state
					
					// Show/hide expand button based on content size (for INITIAL and FINAL modes)
					if ((mode == ResizeMode.INITIAL || mode == ResizeMode.FINAL) && this.expand_button != null) {
						if (natural_height > 0 && natural_height <= max_height) {
							this.expand_button.visible = false;
						} else {
							this.expand_button.visible = true;
						}
					}
					
					return false;
			}
			
			return false;
		}
		
		/**
		 * Adds text to the current code block.
		 * 
		 * @param text The text to add
		 */
		public void add_code_text(string text)
		{
			// Accumulate content
			this.code_content.append(text);
			
			// Add to source buffer if it exists
			if (this.source_buffer != null) {
				Gtk.TextIter end_iter;
				this.source_buffer.get_end_iter(out end_iter);
				this.source_buffer.insert(ref end_iter, text, -1);
			}
			
			// Stream to nested markdown renderer when this is a ```markdown block
			if (this.nested_markdown_render != null) {
				this.nested_markdown_render.add(text);
			}
			
			// Scroll sourceview to bottom after content is added
			// Use Idle to ensure layout is updated first
			GLib.Idle.add(() => {
				this.scroll_sourceview_to_bottom();
				return false;
			});
			
			// Emit signal to notify that content was updated (for scrolling outer container)
			this.renderer.code_block_content_updated();
			
			// Check if text contains a line break - if so, check if we need to clamp height
			if (text.contains("\n")) {
				GLib.Idle.add(() => {
					return this.resize_widget_callback(this.source_view, ResizeMode.INITIAL);
				});
			}
		}
		
		/**
		 * Ends the current code block.
		 * Calls the parent renderer's code_block_ended signal and finalizes the widget.
		 */
		public void end_code_block()
		{
			// Notify renderer with content and language
			var content = this.code_content.str;
			this.renderer.code_block_ended(content, this.code_language);

			// Remove trailing newline(s) from SourceView in place (no full buffer rewrite) to avoid extra blank line / scrollbar
			Gtk.TextIter end_iter;
			this.source_buffer.get_end_iter(out end_iter);
			var start_iter = end_iter;
			start_iter.backward_char();
			while (start_iter.get_char() == '\n' && !start_iter.is_start()) {
				start_iter.backward_char();
			}
			var del_start = start_iter;
			if (del_start.get_char() != '\n') {
				del_start.forward_char();
			}
			if (!del_start.equal(end_iter)) {
				this.source_buffer.delete(ref del_start, ref end_iter);
			}

			// Phase 2: when markdown block, flush the streamed nested renderer then resize frame to content (capped at max)
			if (this.nested_markdown_render != null) {
				this.nested_markdown_render.flush();
				this.nested_markdown_render = null;
				// GLib.debug("nested flush, 200ms resize, child=%s", this.rendered_box.get_first_child() != null ? "y" : "n");
				// Resize frame to min(rendered content height, max_height); delay so layout has settled
				GLib.Timeout.add(200, () => {
					this.resize_widget_callback((Gtk.Widget) this.rendered_box, ResizeMode.INITIAL);
					return false;
				});
			}
			
			// Finalize the sourceview - resize based on content rules
			if (this.source_view != null) {
				GLib.Idle.add(() => {
					var result = this.resize_widget_callback(this.source_view, ResizeMode.FINAL);
					// Scroll to bottom after resize completes
					this.scroll_sourceview_to_bottom();
					return result;
				});
			}
			
			// Emit signal to notify that code block ended (for scrolling after final resize)
			// Use Idle to delay until after resize callback completes
			GLib.Idle.add(() => {
				this.renderer.code_block_content_updated();
				return false;
			});
			
			// Clean up
		
			this.code_language = "";
			this.code_content = new StringBuilder();
		}
		
		/**
		 * Scrolls the sourceview's scrolled window to the bottom.
		 */
		private void scroll_sourceview_to_bottom()
		{
			// Scroll the inner source page (stack always has source_scrolled)
			var vadjustment = this.source_scrolled.vadjustment;
			if (vadjustment == null) {
				return;
			}
			
			// Check if layout is ready by verifying upper bound is reasonable
			if (vadjustment.upper < 10.0) {
				// Layout not ready yet, try again on next idle
				GLib.Idle.add(() => {
					this.scroll_sourceview_to_bottom();
					return false;
				});
				return;
			}
			
			// Scroll to bottom by setting value to maximum
			vadjustment.value = vadjustment.upper;
		}
		
		/**
		 * Copies the content of a SourceView buffer to the clipboard.
		 * 
		 * @param source_buffer The SourceView buffer to copy from
		 */
		private void copy_source_view_to_clipboard(GtkSource.Buffer? source_buffer)
		{
			if (source_buffer == null) {
				return;
			}
			
			// Get all text from the buffer
			Gtk.TextIter start_iter, end_iter;
			source_buffer.get_start_iter(out start_iter);
			source_buffer.get_end_iter(out end_iter);
			string text = source_buffer.get_text(start_iter, end_iter, false);
			
			if (text.length == 0) {
				return;
			}
			
			// Get the clipboard and set the text
			var display = Gdk.Display.get_default();
			if (display == null) {
				return;
			}
			
			var clipboard = display.get_clipboard();
			clipboard.set_text(text);
		}
	}
}
