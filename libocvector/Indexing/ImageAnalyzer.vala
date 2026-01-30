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

namespace OLLMvector.Indexing
{
	public class ImageAnalyzer : VectorBase
	{
		private static PromptTemplate? cached_image_template = null;

		static construct
		{
			cached_image_template = new PromptTemplate("analysis-prompt-image.txt");
			cached_image_template.load();
		}

		public ImageAnalyzer(OLLMchat.Settings.Config2 config) {
			base(config);
		}

		public async string describe_image(OLLMfiles.File file) throws GLib.Error
		{
			var tool_config = this.config.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchToolConfig;
			if (!tool_config.vision.is_valid) {
				return "";
			}
			var gfile = GLib.File.new_for_path(file.path);
			if (!gfile.query_exists()) {
				return "";
			}
			var content_type = gfile.query_info(
				GLib.FileAttribute.STANDARD_CONTENT_TYPE,
				GLib.FileQueryInfoFlags.NONE,
				null
			).get_content_type();
			if (content_type == null || !content_type.has_prefix("image/")) {
				return "";
			}
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", cached_image_template.system_message));
			var user_msg = new OLLMchat.Message("user", cached_image_template.fill());
			user_msg.images.add(file.path);
			messages.add(user_msg);
			return yield this.request_analysis(messages, tool_config.vision);
		}
	}
}
