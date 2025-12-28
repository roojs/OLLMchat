/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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
		 * @param renderer The Render instance (provides access to box and code_block_ended signal)
		 * @param language_id The language identifier for syntax highlighting
		 */
		public RenderSourceView(Render renderer, string language_id)
		{
			this.renderer = renderer;
			this.code_language = language_id;
			this.code_content = new StringBuilder();
			
			// Create buffer with language if specified
			GtkSource.Buffer source_buffer;
			if (language_id != null && language_id != "") {
				var mapped_id = this.map_language_id(language_id);
				var lang_manager = GtkSource.LanguageManager.get_default();
				var language = lang_manager.get_language(mapped_id);
				if (language != null) {
					source_buffer = new GtkSource.Buffer.with_language(language);
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
				show_line_numbers = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false,
				can_focus = false,
				focus_on_click = false,
				css_classes = { "code-editor" }
			};
			this.source_view.set_buffer(source_buffer);
			this.source_buffer = source_buffer;

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
			
			// Add title label on the left (language name)
			string language_label_text = (this.code_language != null && this.code_language != "") ? this.code_language : "code";
			var title_label = new Gtk.Label(language_label_text) {
				hexpand = false,
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER,
				margin_start = 5
			};
			title_label.add_css_class("oc-code-frame-title");
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
			var source_buffer_for_button = this.source_buffer;
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
			
			// Connect button click handler
			copy_button.clicked.connect(() => {
				this.copy_source_view_to_clipboard(source_buffer_for_button);
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
			
			// Add buttons to button box
			button_box.append(copy_button);
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
			
			// Add SourceView to ScrolledWindow
			this.scrolled_window.set_child(this.source_view);
			
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
			
			// Style the frame with blockcode-frame CSS class
			frame.add_css_class("oc-blockcode-frame");

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
			// Check if widget is realized
			if (!widget.get_realized()) {
				return true; // Try again next time
			}
			
			// Get preferred height of the widget
			int min_natural = 0;
			int nat_natural = 0;
			widget.measure(Gtk.Orientation.VERTICAL, -1, out min_natural, out nat_natural, null, null);
			int natural_height = nat_natural;
			
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
					
					// Use the smaller of max_height (50% window) or natural height for collapsed state
					int target_height = (natural_height > 0 && natural_height < max_height) ? natural_height : max_height;
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
			// Disconnect signal handler if it exists
			
			// Notify renderer with content and language
			var content = this.code_content.str;
			this.renderer.code_block_ended(content, this.code_language);
			
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
			if (this.scrolled_window == null) {
				return;
			}
			
			var vadjustment = this.scrolled_window.vadjustment;
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
