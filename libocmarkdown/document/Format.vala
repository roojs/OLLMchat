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

	public class Format : Node
	{
		public override FormatType node_type { get; set; default = FormatType.FORMAT; }
		public string text { get; set; default = ""; }
		public string href { get; set; default = ""; }
		public string title { get; set; default = ""; }
		public bool is_reference { get; set; }
		public string scheme { get; set; default = "file"; }
		public string path { get; set; default = ""; }
		public string hash { get; set; default = ""; }
		public bool is_relative { get; set; default = false; }
		public string src { get; set; default = ""; }
		public string tag { get; set; default = ""; }
		public string tag_attributes { get; set; default = ""; }
		public string tag_name { get; set; default = ""; }

		public Format(FormatType k)
		{
			this.kind = k;
		}

		/** Secondary constructor: text run (FormatType.TEXT). */
		public Format.from_text(string s)
		{
			this.kind = FormatType.TEXT;
			this.text = s;
		}

		/**
		 * Absolute path for this link when it is a file reference (scheme "file").
		 * Returns path if already absolute, otherwise resolves path relative to to_path.
		 * When scheme is not "file" or path is empty, returns this.path as-is.
		 */
		public string abspath(string to_path)
		{
			if (this.scheme != "file" || this.path == "" || GLib.Path.is_absolute(this.path)) {
				return this.path;
			}
			var base_file = GLib.File.new_for_path(to_path);
			var resolved = base_file.resolve_relative_path(this.path);
			var result = resolved.get_path();
			return result != null ? result : "";
		}

		/**
		 * Correct a file link path when the model used a leading slash so it was parsed
		 * as absolute from the filesystem root. Only mutates {{{path}}} and {{{href}}} when
		 * a file or directory exists at the corrected path under {{{project_root}}}.
		 *
		 * @param project_root active project root directory
		 */
		public void resolve (string project_root)
		{
			if (this.scheme != "file" || this.path == "" || project_root == "") {
				return;
			}
			var raw = this.path;
			var gf = GLib.File.new_for_path (raw);
			// Target already exists as written (no rewrite).
			if (gf.query_exists ()) {
				return;
			}
			// Absolute path already under project; joining again would be wrong.
			if (GLib.Path.is_absolute (raw) && (raw == project_root || raw.has_prefix (project_root + "/"))) {
				return;
			}
			// Strip-from-root heuristic only for paths that look like /foo (not relative).
			if (!raw.has_prefix ("/")) {
				return;
			}
			var candidate = GLib.Path.build_filename (project_root, raw.substring (1));
			// Keep fix inside project: allow project_root itself, else require
			// project_root + "/" so "/tmp" does not prefix-match "/tmp2/...".
			if (candidate != project_root && !candidate.has_prefix (project_root + "/")) {
				return;
			}
			var cf = GLib.File.new_for_path (candidate);
			// Corrected path must exist before we rewrite link fields.
			if (!cf.query_exists ()) {
				return;
			}
			this.path = candidate;
			this.href = this.path + (this.hash != "" ? "#" + this.hash : "");
			this.is_relative = false;
		}

		/**
		 * True if this `file:` link resolves to an existing directory on disk
		 * (path resolved from [[project_root]] for relative links). If the path looks
		 * like a mistaken absolute-from-root project path, checks the same path under
		 * [[project_root]].
		 */
		public bool is_dir (string project_root)
		{
			if (this.scheme != "file") {
				return false;
			}
			var rp = this.is_relative ? this.abspath (project_root) : this.path;
			if (rp == "") {
				return false;
			}
			var gf = GLib.File.new_for_path (rp);
			// First probe: directory exactly at rp (as given or relative-resolved).
			if (gf.query_exists ()
				&& gf.query_file_type (GLib.FileQueryInfoFlags.NONE) == GLib.FileType.DIRECTORY) {
				return true;
			}
			// Second probe: mistaken absolute-from-root (/lib/...) → under project_root.
			if (!GLib.Path.is_absolute (rp)) {
				return false;
			}
			if (!rp.has_prefix ("/")) {
				return false;
			}
			if (project_root == "") {
				return false;
			}
			// Already under project: strip fix does not apply (first probe said not a dir).
			if (rp == project_root || rp.has_prefix (project_root + "/")) {
				return false;
			}
			var candidate = GLib.Path.build_filename (project_root, rp.substring (1));
			// Same under-project guard as resolve(); see resolve() for why.
			if (candidate != project_root && !candidate.has_prefix (project_root + "/")) {
				return false;
			}
			var cf = GLib.File.new_for_path (candidate);
			if (!cf.query_exists ()) {
				return false;
			}
			// Exists but is a file: not a directory target.
			if (cf.query_file_type (GLib.FileQueryInfoFlags.NONE) != GLib.FileType.DIRECTORY) {
				return false;
			}
			return true;
		}

		/**
		 * File link as a relative target: [[scheme]] `file`, [[path]], [[href]] = path + `#` + [[hash]],
		 * and [[is_relative]] true (caller passes a path suitable for markdown-relative links).
		 */
		public void up_relpath(string path)
		{
			this.scheme = "file";
			this.path = path;
			this.href = path + (this.hash != "" ? "#" + this.hash : "");
			this.is_relative = true;
		}

		public override string to_markdown()
		{
			string inner = "";
			foreach (var child in this.children) {
				inner += child.to_markdown();
			}
			switch (this.kind) {
				case FormatType.TEXT:
					return this.text;
				case FormatType.ITALIC:
				case FormatType.ITALIC_ASTERISK:
					return "*" + inner + "*";
				case FormatType.ITALIC_UNDERSCORE:
					return "_" + inner + "_";
				case FormatType.BOLD:
				case FormatType.BOLD_ASTERISK:
					return "**" + inner + "**";
				case FormatType.BOLD_UNDERSCORE:
					return "__" + inner + "__";
				case FormatType.BOLD_ITALIC_ASTERISK:
					return "***" + inner + "***";
				case FormatType.BOLD_ITALIC_UNDERSCORE:
					return "___" + inner + "___";
				case FormatType.CODE:
					return "`" + (this.text != "" ? this.text : inner) + "`";
				case FormatType.STRIKETHROUGH:
					return "~~" + inner + "~~";
				case FormatType.U:
					return "<u>" + inner + "</u>";
				case FormatType.LINK:
					if (this.is_reference) {
						// Implicit ref [text][]: ref key equals link text → emit []; else [ref]
						bool implicit_ref = (this.href != "" && this.href == inner);
						return "[" + inner + "]" + (implicit_ref ? "[]" : "[" + this.href + "]");
					}
					return "[" + inner + "](" + this.href
						+ (this.title != "" ? " \"" + this.title + "\"" : "") + ")";
				case FormatType.TASK_LIST:
					return "[ ]";
				case FormatType.TASK_LIST_DONE:
					return "[x]";
				case FormatType.IMAGE:
					return "![" + (this.title != "" ? this.title : "image") + "](" + this.src
						+ (this.title != "" ? " \"" + this.title + "\"" : "") + ")";
				case FormatType.BR:
					return "\n";
				case FormatType.HTML:
					return "<" + this.tag
						+ (this.tag_attributes != "" ? " " + this.tag_attributes : "") + ">"
						+ inner + "</" + this.tag + ">";
				case FormatType.OTHER:
					return "<" + this.tag_name + ">" + inner + "</" + this.tag_name + ">";
				default:
					return inner;
			}
		}
	}
}
