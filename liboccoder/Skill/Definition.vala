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

namespace OLLMcoder.Skill
{
	/**
	 * One skill file: YAML header (key-value map) and markdown body.
	 * Constructor only stores path; call load() to read and parse.
	 * Header is stored in a hash map; "name" etc. are read from the map after load.
	 */
	public class Definition : Object
	{
		public string path { get; private set; default = ""; }
		public string body { get; private set; default = ""; }
		public string full_content { get; private set; default = ""; }
		public Gee.HashMap<string, string> header { 
			get; private set; default = new Gee.HashMap<string, string>(); }
		/** File modification time; set in load(). */
		public int64 mtime { get; private set; default = 0; }
		/** Parsed body as a markdown document (libocmarkdown). */
		public Markdown.Document.Document document { get; private set; }

		public Definition(string path)
		{
			this.path = path;
		}

		/**
		 * Load and parse the skill file. Validates content; throws on read or validation failure.
		 */
		public void load() throws GLib.Error
		{
			string contents = "";
			if (!GLib.FileUtils.get_contents(this.path, out contents)) {
				throw new GLib.FileError.FAILED("Skill: could not read %s".printf(this.path));
			}

			this.full_content = contents;

			if (!contents.has_prefix("---")) {
				throw new GLib.FileError.INVAL("Skill: %s does not start with YAML header (---)".printf(this.path));
			}
			var parts = contents.split("\n---", 2);
			if (parts.length < 2) {
				throw new GLib.FileError.INVAL("Skill: %s has no closing header delimiter (---)".printf(this.path));
			}
			string header_text = parts[0].substring(3).strip();
			this.body = parts[1].strip();

			this.header.clear();
			foreach (var line in header_text.split("\n")) {
				var stripped = line.strip();
				var colon = stripped.index_of(":");
				if (colon > 0) {
					var key = stripped.substring(0, colon).strip();
					var value = stripped.substring(colon + 1).strip();
					if (value != "") {
						this.header.set(key, value);
					}
				}
			}

			if (!this.header.has_key("name") || this.header.get("name") == "") {
				throw new GLib.FileError.INVAL("Skill: %s has no valid 'name' in header".printf(this.path));
			}
			if (!this.header.has_key("description") || this.header.get("description") == "") {
				throw new GLib.FileError.INVAL("Skill: %s has no valid 'description' in header".printf(this.path));
			}

			this.mtime = (int64) GLib.File.new_for_path(this.path).query_info(
				GLib.FileAttribute.TIME_MODIFIED,
				GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
				null
			).get_modification_time().tv_sec;

			var doc_render = new Markdown.Document.Render();
			doc_render.parse(this.body);
			this.document = doc_render.document;
		}

		/**
		 * Validates that skills referenced in this document are in the available map (key = skill name).
		 * Returns list of skill names that are referenced but not in available.
		 * If the list is non-empty, caller must not run the skill (error condition).
		 */
		public Gee.ArrayList<string> validate_skills(Gee.HashMap<string, Definition> available)
		{
			var list = this.skills_list();
			if (list == null) {
				return new Gee.ArrayList<string>();
			}
			var missing = new Gee.ArrayList<string>();
			foreach (var child in list.children) {
				if (!(child is Markdown.Document.ListItem)) {
					continue;
				}
				var name = ((Markdown.Document.ListItem) child).text_content().strip();
				if (name != "" && !available.has_key(name)) {
					missing.add(name);
				}
			}
			return missing;
		}

		/**
		 * First re-parses the document from this.body; then finds the list
		 * under "Available skills" and appends a nested list item with "***When to use*** " + description
		 * for each list item. Original item label unchanged.
		 */
		public void apply_skills(Gee.HashMap<string, Definition> available)
		{
			var doc_render = new Markdown.Document.Render();
			doc_render.parse(this.body);
			this.document = doc_render.document;
			var target_list = this.skills_list();
			if (target_list == null) {
				return;
			}
			foreach (var child in target_list.children) {
				if (!(child is Markdown.Document.ListItem)) {
					continue;
				}
				var item = (Markdown.Document.ListItem) child;
				var skill_name = item.text_content().strip();
				if (skill_name == "" || !available.has_key(skill_name)) {
					continue;
				}
				var def = available.get(skill_name);
				var desc = def.header.has_key("description") ? def.header.get("description") : "";
				var new_li = item.append_li();
				if (new_li != null) {
					new_li.append_raw("***When to use*** " + desc);
				}
			}
		}

		private Markdown.Document.List? skills_list()
		{
			if (this.document == null) {
				return null;
			}
			var heading = this.document.headings.get("available-skills");
			if (heading == null) {
				return null;
			}
			var next_block = heading.next();
			if (next_block is Markdown.Document.List) {
				return (Markdown.Document.List) next_block;
			}
			return null;
		}

		/**
		 * Returns this.document rendered to markdown.
		 * Call after apply_skills() so the document includes appended descriptions.
		 */
		public string to_markdown()
		{
			return this.document.to_markdown();
		}
	}
}
