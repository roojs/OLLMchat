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

namespace OLLMchat.Response
{
	/**
	 * Represents a progress chunk from the create API.
	 *
	 * Contains status information and progress metrics for model creation operations.
	 */
	public class Create : Base
	{
		/**
		 * Status string (e.g., "creating model", "success")
		 */
		public string status { get; set; default = ""; }
		
		/**
		 * Whether the create operation is complete
		 */
		public bool done { get; set; default = false; }
		
		public Create(Settings.Connection? connection = null)
		{
			base(connection);
		}
	}
}
