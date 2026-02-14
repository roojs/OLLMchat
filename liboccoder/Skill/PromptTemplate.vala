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
	 * Prompt template that loads from the skills templates directory (filesystem).
	 * Path is hard-coded for now; constructor takes filename only (e.g. "system.template.md", "user.template.md").
	 * Use from_dir() to load from resources/skill-prompts (or another relative dir under project).
	 */
	public class PromptTemplate : OLLMchat.Prompt.Template
	{
		private const string BASE_DIR = "resources/skills";

		public PromptTemplate(string filename)
		{
			base(filename);
			this.source = "file://";
			this.base_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), "gitlive", "OLLMchat", BASE_DIR);
		}

		/**
		 * Load template from a given relative directory under the project (e.g. "resources/skill-prompts").
		 */
		public static PromptTemplate from_dir(string filename, string relative_base_dir)
		{
			var t = new PromptTemplate(filename);
			t.base_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), "gitlive", "OLLMchat", relative_base_dir);
			return t;
		}
	}
}
