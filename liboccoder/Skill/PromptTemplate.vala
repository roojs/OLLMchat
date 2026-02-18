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
	 * ''task_creation_initial.md'', ''task_refinement.md'', ''task_post_completion.md'',
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

		/**
		 * Returns a markdown heading line plus body, optionally in a fenced code block.
		 *
		 * When code_block is true (default): uses tildes when body contains a line-start backtick
		 * fence so the outer fence is not broken; otherwise uses a backtick fence.
		 * When code_block is false: body is appended after the heading with no fence.
		 *
		 * @param heading heading text (e.g. GFM anchor)
		 * @param body body text to wrap
		 * @param code_block if true (default), wrap body in a fenced code block; if false, plain text
		 * @return the concatenated string
		 */
		public string header(string heading, string body, bool code_block = true)
		{
			if (!code_block) {
				return "## " + heading.strip() + "\n\n" + body + "\n\n";
			}
			var fence = body.index_of("\n```") >= 0 ? "~~~~" : "```";
			return "## " + heading.strip() + "\n\n" + fence + "\n" + body + "\n" + fence + "\n\n";
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
		 * Call with alternating key and value strings, e.g. fill("key1", value1, "key2", value2).
		 * The caller does not need to pass null at the end; Vala terminates varargs with null automatically.
		 *
		 * For each key/value pair in order:
		 * * If the template contains simple {key}, replace every occurrence with value and continue.
		 * * If value is the literal string "DEFAULT", remove the markers {key/start} and {key/end} from the result (content between them is kept); then continue.
		 * * Otherwise, if the template contains {key/start} and {key/end}, replace the whole span (markers and content) with value.
		 * * If none of the above apply, do nothing for this pair.
		 *
		 * @return the filled template string
		 */
		public new string fill(...)
		{
			var result = this.user_template;
			var args = va_list();
			while (true) {
				unowned string? key = args.arg<string?>();
				if (key == null) {
					break;
				}
				unowned string? value = args.arg<string?>();
				if (value == null) {
					break;
				}

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
				if (idx < 0 || end_idx < 0) {
					continue;
				}
				var section_end = end_idx + ("{" + key + "/end}").length;
				result = result.substring(0, idx) + value + result.substring(section_end);
			}
			this.filled_user = result;
			return result;
		}

		/**
		 * Same as {@link fill} but operates on the system message and stores the result in {@link filled_system}.
		 *
		 * @return the filled system message string
		 */
		public new string system_fill(...)
		{
			var result = this.system_message;
			var args = va_list();
			while (true) {
				unowned string? key = args.arg<string?>();
				if (key == null) {
					break;
				}
				unowned string? value = args.arg<string?>();
				if (value == null) {
					break;
				}

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
				if (idx < 0 || end_idx < 0) {
					continue;
				}
				var section_end = end_idx + ("{" + key + "/end}").length;
				result = result.substring(0, idx) + value + result.substring(section_end);
			}
			this.filled_system = result;
			return result;
		}
	}
}
