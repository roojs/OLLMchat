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
	 * Represents a progress chunk from the pull API.
	 *
	 * Contains status information, progress metrics, and digest information
	 * for model pull operations.
	 */
	public class Pull : Base
	{
		/**
		 * Status string (e.g., "pulling manifest", "pulling <digest>", "success")
		 */
		public string status { get; set; default = ""; }
		
		/**
		 * SHA256 digest of the layer being pulled
		 */
		public string digest { get; set; default = ""; }
		
		/**
		 * Number of bytes completed for the current layer
		 */
		public int64 completed { get; set; default = 0; }
		
		/**
		 * Total number of bytes for the current layer
		 */
		public int64 total { get; set; default = 0; }
		
		public Pull(Settings.Connection? connection = null)
		{
			base(connection);
		}
	}
}

