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

namespace OLLMchat.ChatPermission
{
	/**
	 * Dummy implementation of Provider for testing.
	 * 
	 * Logs all permission requests using GLib.debug().
	 * Always allows READ requests, denies WRITE and EXECUTE requests.
	 */
	public class Dummy : Provider
	{
		public Dummy(string directory = "")
		{
			base(directory);
		}
		
		protected override async PermissionResponse request_user(Ollama.Tool tool)
		{
			// Build operation string for logging
			var op_parts = new Gee.ArrayList<string>();
			if ((tool.permission_operation & Operation.READ) != 0) {
				op_parts.add("READ");
			}
			if ((tool.permission_operation & Operation.WRITE) != 0) {
				op_parts.add("WRITE");
			}
			if ((tool.permission_operation & Operation.EXECUTE) != 0) {
				op_parts.add("EXECUTE");
			}
			string op_str = string.joinv(" | ", op_parts.to_array());
			
			GLib.debug("Permission requested for tool '%s' on '%s' (%s): %s", tool.name, tool.permission_target_path, op_str, tool.permission_question);
			
			// Always allow READ-only requests, deny others
			if (tool.permission_operation == Operation.READ) {
				return PermissionResponse.ALLOW_ONCE;
			}
			return PermissionResponse.DENY_ONCE;
		}
	}
}

