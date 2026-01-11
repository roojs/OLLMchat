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

namespace OLLMchat.Response
{
	/**
	 * Represents the response from the generate API.
	 *
	 * Contains the model name, generated response text, thinking output,
	 * and timing information.
	 */
	public class Generate : Base
	{
		public string model { get; set; default = ""; }
		public string created_at { get; set; default = ""; }
		public string response { get; set; default = ""; }
		public string thinking { get; set; default = ""; }
		public bool done { get; set; default = false; }
		public string? done_reason { get; set; default = ""; }
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }
		public int64 prompt_eval_duration { get; set; default = 0; }
		public int eval_count { get; set; default = 0; }
		public int64 eval_duration { get; set; default = 0; }

		public Generate(Settings.Connection? connection = null)
		{
			base(connection);
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "client":
					return null;
				case "done-reason":
					// Only serialize if set
					if (this.done_reason == null || this.done_reason == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}
	}
}

