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
		private Gtk.Button copy_button;
		private Gtk.Button new_chat_button;
		private Gtk.Revealer body_revealer;  // wraps body; when .collapsed style, toggles visibility
		private Gtk.Button collapse_toggle_button;  // before title: expand/collapse body when .collapsed
		
		// Phase 2: nested markdown (stack + view-source toggle)
		private Gtk.Stack stack;
		private Gtk.Box rendered_box;
		private Gtk.Button view_source_toggle;
		private bool showing_source = false;
		private Gtk.ScrolledWindow source_scrolled;  // inner scrolled for source page; used for scroll-to-bottom
		private MarkdownGtk.Render? nested_markdown_render = null;  // streamed nested renderer for ```markdown blocks
		private ulong source_view_realize_handler = 0;
		private ulong rendered_box_realize_handler = 0;
		
		private enum ResizeMode
		{
			INITIAL,     // Initial sizing: min(natural, max_height), hide button if fits
			EXPAND,      // Expanded state: natural height
			COLLAPSE,    // Collapsed state: min(natural, max_height)
			FINAL,       // Final sizing when code block ends: min(natural, max_height), hide button if fits
			REVEAL_BODY  // Same capped size as INITIAL but use body_revealer for width, set vexpand true (for .collapsed expand)
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
			
			// Info string format: "type.oc-frame-theme" or "type.oc-frame-theme title" (e.g. markdown.oc-frame-info, text.oc-frame-primary You said:).
			// Parse as type + optional title when we have that format (dot or space) or empty; else treat as language-free (single word = title only).
			var leading = language_id.has_prefix(" ");
			var info = language_id.strip();
			var language = "";
			var description = info;
			if (info.contains(".") || info.contains(" ") || info == "" || !leading) {
				var tokens = info.split(" ", 2);
				language = tokens.length > 0 ? tokens[0] : "";
				description = tokens.length > 1 ? tokens[1].strip() : "";
			}
			// Post-process language: split on ".", first part = language for highlighting, rest = frame theme classes
			var lang_parts = language.split(".");
			language = lang_parts.length > 0 ? lang_parts[0] : language;
			this.code_language = language.down();
			string[] frame_theme_classes = lang_parts.length > 1 ?
				 lang_parts[1:lang_parts.length] : new string[0];
			bool is_user_frame = "oc-frame-user" in frame_theme_classes;
			bool has_collapsed_style = "collapsed" in frame_theme_classes;
			// Title: use description when present; for oc-frame blocks without description use fallback (never show raw "text.oc-frame-...")
			var header_text = (description != "") ? description :
				(frame_theme_classes.length > 0 ? "Content" : ((language != "") ? language : "code"));




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
			
			// When .collapsed: button before title toggles body (list-add = expand, go-up = collapse)
			this.collapse_toggle_button = new Gtk.Button() {
				icon_name = "go-next-symbolic",
				tooltip_text = "Expand",
				hexpand = false,
				margin_end = 4,
				can_focus = false,
				focus_on_click = false,
				visible = has_collapsed_style
			};
			this.collapse_toggle_button.clicked.connect(() => {
				if (this.body_revealer.reveal_child) {
					this.body_revealer.reveal_child = false;
					this.collapse_toggle_button.icon_name = "go-next-symbolic";
					this.collapse_toggle_button.tooltip_text = "Expand";
					// Hide view source and copy when collapsed
					this.view_source_toggle.visible = false;
					this.copy_button.visible = false;
					return;
				}
				// Reveal first so body is visible; then idle-add resize so widget can be realized
				this.body_revealer.reveal_child = true;
				this.collapse_toggle_button.icon_name = "go-up-symbolic";
				this.collapse_toggle_button.tooltip_text = "Collapse";
				this.view_source_toggle.visible = (this.code_language == "markdown");
				this.copy_button.visible = true;
				GLib.Idle.add(() => {
					// Use the stack's visible child so we measure the widget that will be shown (and realized)
					Gtk.Widget widget = this.stack.visible_child;
					if (widget == null) {
						widget = (this.code_language == "markdown") ?
							 (Gtk.Widget) this.rendered_box : (Gtk.Widget) this.source_view;
					}
					return this.resize_widget_callback(widget, ResizeMode.REVEAL_BODY);
				});
			});
			header_box.append(this.collapse_toggle_button);
			
			var title_label = new Gtk.Label("<b>%s</b>".printf(GLib.Markup.escape_text(header_text, -1))) {
				hexpand = false,
				halign = Gtk.Align.START,
				valign = Gtk.Align.END,
				margin_start = has_collapsed_style ?  0  : 4,
				margin_top = 4,
				margin_bottom = 10,
				ellipsize = Pango.EllipsizeMode.END,
				tooltip_text = header_text,
				use_markup = true
			};
			title_label.add_css_class("oc-code-frame-title");
			title_label.max_width_chars = -1;  // no character limit
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
			this.copy_button = new Gtk.Button() {
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
			this.copy_button.clicked.connect(() => {
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
				margin_end = 0, // the text has a margin so this doesnt need it
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
				focus_on_click = false,
				margin_end = 0, // the text has a margin so this doesnt need it
				margin_top = 0,
				margin_bottom = 0
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
			
			// Show view-source toggle for markdown: only when expanded (or when frame is not collapsible)
			// Copy button: only when expanded when frame is collapsible
			this.copy_button.visible = !has_collapsed_style;
			if (this.code_language == "markdown") {
				this.view_source_toggle.visible = !has_collapsed_style;
				this.stack.visible_child_name = "rendered";
				this.nested_markdown_render = new MarkdownGtk.Render(this.rendered_box);
				this.nested_markdown_render.start();
			} else {
				this.view_source_toggle.visible = false;
				this.stack.visible_child_name = "source";
			}
			
			// Wrap body in Revealer so .collapsed style can hide/show it with animation
			this.body_revealer = new Gtk.Revealer() {
				reveal_child = !has_collapsed_style,
				hexpand = true,
				vexpand = false,
				transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
				transition_duration = 250
			};
			this.body_revealer.set_child(this.scrolled_window);
			container_box.append(this.body_revealer);

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
			
			// Connect before set_visible: realize may run during show; a handler connected afterward would miss it.
			this.source_view_realize_handler = this.source_view.realize.connect(() => {
				this.source_view.disconnect(this.source_view_realize_handler);
				this.source_view_realize_handler = 0;
				GLib.Idle.add(() => {
					if (this.body_revealer.reveal_child) {
						this.resize_widget_callback((Gtk.Widget) this.source_view, ResizeMode.INITIAL);
					}
					return false;
				});
			});
			this.rendered_box_realize_handler = this.rendered_box.realize.connect(() => {
				this.rendered_box.disconnect(this.rendered_box_realize_handler);
				this.rendered_box_realize_handler = 0;
				GLib.Idle.add(() => {
					if (this.body_revealer.reveal_child) {
						this.resize_widget_callback((Gtk.Widget) this.rendered_box, ResizeMode.INITIAL);
					}
					return false;
				});
			});
			
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
				// REVEAL_BODY may run before layout; retry on idle. SourceView FINAL when unrealized is handled by ctor realize one-shot + INITIAL.
				return mode == ResizeMode.REVEAL_BODY;
			}
			// Width for height-for-width; REVEAL_BODY uses body_revealer (child may have no allocation when collapsed)
			var  for_width = this.scrolled_window.get_width();
			if (mode == ResizeMode.REVEAL_BODY) {
				for_width = this.body_revealer.get_allocated_width();
				if (for_width <= 0) {
					for_width = this.body_revealer.get_width();
				}
				if (for_width <= 0 && this.renderer.box != null) {
					for_width = this.renderer.box.get_allocated_width();
				}
			}
			if (for_width <= 0) {
				GLib.debug("resize_widget_callback mode=%d bail for_width<=0", (int) mode);
				return true;
			}
			// Get preferred height of the widget for the actual width so wrap-based height is correct
			int min_natural = 0;
			int nat_natural = 0;
			widget.measure(Gtk.Orientation.VERTICAL, for_width, out min_natural, out nat_natural, null, null);
			int natural_height = nat_natural;
			GLib.debug(
				"mode=%d for_width=%d min_natural=%d natural_height=%d max_collapsed=%d",
				(int) mode,
				for_width,
				min_natural,
				natural_height,
				this.get_max_collapsed_height()
			);

			switch (mode) {
				case ResizeMode.EXPAND:
					// Remove size constraint to allow expansion to fit content
					this.scrolled_window.set_size_request(-1, -1);
					this.scrolled_window.vexpand = true; // Allow expansion to natural height
					return false;
				
				case ResizeMode.REVEAL_BODY:
					// Same capped size as INITIAL but vexpand true so revealer animates to correct height
					int max_ht = this.get_max_collapsed_height();
					int target_ht = (natural_height > 0 && natural_height < max_ht) ? natural_height : max_ht;
					if (target_ht <= 0) {
						target_ht = 200;
					}
					this.scrolled_window.set_size_request(-1, target_ht);
					this.scrolled_window.vexpand = true;
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
			
			// When collapsed, skip resize and scroll (body is hidden)
			if (!this.body_revealer.reveal_child) {
				this.renderer.code_block_content_updated();
				return;
			}
			// Scroll visible content (rendered or source) to bottom after content is added
			GLib.Idle.add(() => {
				this.scroll_bottom();
				return false;
			});
			this.renderer.code_block_content_updated();
			// When content grows (e.g. newline), resize the frame so it expands with streamed content
			if (text.contains("\n")) {
				GLib.Idle.add(() => {
					if (!this.body_revealer.reveal_child) {
						return false;
					}
					var widget_to_resize = (this.nested_markdown_render != null)
						? (Gtk.Widget) this.rendered_box
						: (Gtk.Widget) this.source_view;
					return this.resize_widget_callback(widget_to_resize, ResizeMode.INITIAL);
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

			// Phase 2: when markdown block, flush the streamed nested renderer then resize and scroll to bottom
			if (this.nested_markdown_render != null) {
				this.nested_markdown_render.flush();
				this.nested_markdown_render = null;
				GLib.Timeout.add(200, () => {
					if (this.body_revealer.reveal_child) {
						this.resize_widget_callback((Gtk.Widget) this.rendered_box, ResizeMode.INITIAL);
						this.scroll_bottom(this.scrolled_window);
					}
					return false;
				});
			}
			// Finalize the sourceview - resize based on content rules
			if (this.source_view != null) {
				GLib.Idle.add(() => {
					if (!this.body_revealer.reveal_child) {
						return false;
					}
					var result = this.resize_widget_callback(this.source_view, ResizeMode.FINAL);
					this.scroll_bottom(this.source_scrolled);
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
		 * Scrolls to the bottom. If sw is null, scrolls the visible content (outer for markdown, source for others).
		 */
		private void scroll_bottom(Gtk.ScrolledWindow? sw = null)
		{
			if (!this.body_revealer.reveal_child) {
				return;
			}
			var target = sw;
			if (target == null) {
				target = (this.nested_markdown_render != null)
					? this.scrolled_window
					: this.source_scrolled;
			}
			var vadjustment = target.vadjustment;
			if (vadjustment == null) {
				return;
			}
			if (vadjustment.upper < 10.0) {
				GLib.Idle.add(() => {
					this.scroll_bottom(target);
					return false;
				});
				return;
			}
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
