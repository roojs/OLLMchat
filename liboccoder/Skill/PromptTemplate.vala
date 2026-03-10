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
	 * Prompt template that loads from the skill-prompts resource only (no filesystem).
	 *
	 * Constructor takes filename only. Call sites use filenames such as
	 * ''task_creation_initial.md'', ''task_refinement.md'', ''task_list_iteration.md'',
	 * ''task_execution.md''.
	 */
	public class PromptTemplate : OLLMchat.Prompt.Template
	{
		private const string SKILL_PROMPTS_PREFIX = "skill-prompts";

		private static Gee.HashMap<string, PromptTemplate> 
			cache = new Gee.HashMap<string, PromptTemplate>();

		/** Last rendered user message; set after {@link fill}. */
		public string filled_user { get; private set; default = ""; }
		/** Last rendered system message; set after {@link system_fill}. */
		public string filled_system { get; private set; default = ""; }

		public PromptTemplate(string filename)
		{
			base(filename);
			this.source = "resource:///";
			this.base_dir = SKILL_PROMPTS_PREFIX;
		}

		/** ## heading + body, no fence. Unfenced markdown. No output when body is empty. */
		public string header_raw(string heading, string body)
		{
			if (body == "") {
				return "";
			}
			return "## " + heading.strip() + "\n\n" + body + "\n\n";
		}

		/** ## heading + fenced code block. Uses file.language (FileBase; set by detect_language()). Exception: we do output the header (and empty block if needed) when file content is empty. Caller must not pass null file. */
		public string header_file(string heading, OLLMfiles.File file)
		{
			var body = file.get_contents(200);
			var fence = (body.index_of("\n```") >= 0 || body.has_prefix("```")) ? "~~~~" : "```";
			return "## " + heading.strip() + "\n\n"
				+ fence
				+ (file.language != "" ? file.language + "\n" : "\n")
				+ body + "\n"
				+ fence + "\n\n";
		}

		/** ## heading + fenced block with type (e.g. "text", "json", "vala"). No output when body is empty. */
		public string header_fenced(string heading, string body, string type = "")
		{
			if (body == "") {
				return "";
			}
			var fence = (body.index_of("\n```") >= 0 || body.has_prefix("```")) ? "~~~~" : "```";
			return "## " + heading.strip() + "\n\n"
				+ fence
				+ (type != "" ? type + "\n" : "\n")
				+ body + "\n"
				+ fence + "\n\n";
		}

		/**
		 * Returns the markdown-parsed version of filled_system. Call after system_fill().
		 */
		public Markdown.Document.Document system_to_document()
		{
			var render = new Markdown.Document.Render();
			render.parse(this.filled_system);
			return render.document;
		}

		/**
		 * Returns the markdown-parsed version of {@link filled_user}.
		 *
		 * Call after {@link fill} so the returned document reflects the filled message.
		 *
		 * @return parsed document
		 */
		public Markdown.Document.Document user_to_document()
		{
			var render = new Markdown.Document.Render();
			render.parse(this.filled_user);
			return render.document;
		}

		/**
		 * Returns cached template for filename; creates and loads if not cached.
		 *
		 * Always calls {@link load} on the template before returning, then clears
		 * {@link filled_user} and {@link filled_system}.
		 *
		 * @param filename template filename (e.g. ''task_refinement.md'')
		 * @return the cached, reloaded template instance
		 * @throws GLib.Error when load fails
		 */
		public static PromptTemplate template(string filename) throws GLib.Error
		{
			if (cache == null) {
				cache = new Gee.HashMap<string, PromptTemplate>();
			}
			if (!cache.has_key(filename)) {
				var t = new PromptTemplate(filename);
				cache.set(filename, t);
			}
			var t = cache.get(filename);
			t.load();
			t.filled_user = "";
			t.filled_system = "";
			return t;
		}

		/**
		 * Fills the user template with varargs key-value pairs.
		 * First argument is the number of pairs. Call e.g. fill(6, "key1", value1, "key2", value2, …).
		 * Vala appends null after the last argument; we critical if we get null too early or extra args.
		 *
		 * For each key/value pair: if template has {key}, replace with value; or handle DEFAULT / {key/start}..{key/end}.
		 *
		 * @param n_pairs number of key-value pairs
		 * @return the filled template string
		 */
		public new string fill(int n_pairs, ...)
		{
			var result = this.user_template;
			var l = va_list();
			var n_args = n_pairs * 2;
			var count = 0;
			while (count < n_args) {
				string? key = l.arg<string?>();
				if (key == null) {
					GLib.critical("fill: null too early, expected %d pairs, got null at position %d", n_pairs, count + 1);
					break;
				}
				count++;
				if (count >= n_args) {
					GLib.critical("fill: expected %d pairs, got key '%s' without value", n_pairs, key);
					break;
				}
				string? value = l.arg<string?>();
				if (value == null) {
					GLib.critical("fill: null value for key '%s' (argument %d)", key, count + 1);
					count++;
					continue;
				}
				count++;

				if (result.index_of("{" + key + "}") >= 0) {
					result = result.replace("{" + key + "}", value);
					continue;
				}
				if (value == "DEFAULT") {
					result = result.replace("{" + key + "/start}", "").replace("{" + key + "/end}", "");
					continue;
				}
				var idx = result.index_of("{" + key + "/start}");
				var end_idx = (idx >= 0) ? result.index_of("{" + key + "/end}", idx) : -1;
				if (idx >= 0 && end_idx >= 0) {
					var section_end = end_idx + ("{" + key + "/end}").length;
					result = result.substring(0, idx) + value + result.substring(section_end);
				}
			}
			string? extra = l.arg<string?>();
			if (extra != null) {
				GLib.critical("fill: expected %d pairs, got extra (key '%s')", n_pairs, extra);
			}
			this.filled_user = result;
			return result;
		}

		/**
		 * Same as {@link fill} but operates on the system message and stores the result in {@link filled_system}.
		 * First argument is the number of key-value pairs.
		 *
		 * @param n_pairs number of key-value pairs
		 * @return the filled system message string
		 */
		public new string system_fill(int n_pairs, ...)
		{
			var result = this.system_message;
			var l = va_list();
			var n_args = n_pairs * 2;
			var count = 0;
			while (count < n_args) {
				string? key = l.arg<string?>();
				if (key == null) {
					GLib.critical("system_fill: null too early, expected %d pairs, got null at position %d", n_pairs, count + 1);
					break;
				}
				count++;
				if (count >= n_args) {
					GLib.critical("system_fill: expected %d pairs, got key '%s' without value", n_pairs, key);
					break;
				}
				string? value = l.arg<string?>();
				if (value == null) {
					GLib.critical("system_fill: null value for key '%s' (argument %d)", key, count + 1);
					count++;
					continue;
				}
				count++;

				if (result.index_of("{" + key + "}") >= 0) {
					result = result.replace("{" + key + "}", value);
					continue;
				}
				if (value == "DEFAULT") {
					result = result.replace("{" + key + "/start}", "").replace("{" + key + "/end}", "");
					continue;
				}
				var idx = result.index_of("{" + key + "/start}");
				var end_idx = (idx >= 0) ? result.index_of("{" + key + "/end}", idx) : -1;
				if (idx >= 0 && end_idx >= 0) {
					var section_end = end_idx + ("{" + key + "/end}").length;
					result = result.substring(0, idx) + value + result.substring(section_end);
				}
			}
			string? extra = l.arg<string?>();
			if (extra != null) {
				GLib.critical("system_fill: expected %d pairs, got extra (key '%s')", n_pairs, extra);
			}
			this.filled_system = result;
			return result;
		}
	}
}
