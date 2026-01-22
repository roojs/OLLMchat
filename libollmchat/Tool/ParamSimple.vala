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

namespace OLLMchat.Tool
{
	/**
	 * Represents a simple parameter type (string, integer, boolean).
	 *
	 * Used for parameters that don't have nested structures.
	 */
	public class ParamSimple : Param
	{
		/**
		 * The name of the parameter.
		 */
		public override string name { get; set; }
		
		/**
		 * The JSON schema type (e.g., "string", "integer", "boolean").
		 */
		public override string x_type { get; set; }
		
		/**
		 * A description of what the parameter does.
		 */
		public string description { get; set; default = ""; }
		
		/**
		 * Whether this parameter is required.
		 */
		public override bool required { get; set; default = false; }

		public ParamSimple()
		{
		}

		public ParamSimple.with_values(string name, string type, string description = "", bool required = false)
		{
			this.name = name;
			this.x_type = type;
			this.description = description;
			this.required = required;
		}
	}
}
