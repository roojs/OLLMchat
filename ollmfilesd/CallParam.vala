/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd
{
	/** ollmfilesd RPC request params (JSON-RPC {@code params}). */
	public class CallParam : OLLMrpc.CallParam
	{
		// --- shared scalars (several kinds / verbs) ---

		public string path { get; set; default = ""; }
		public bool force { get; set; default = false; }
		public int since_revision { get; set; default = 0; }
		public bool confirm { get; set; default = false; }

		// --- daemon.* ---

		public int protocol { get; set; default = 0; }
		public string client { get; set; default = ""; }

		// --- project.* ---

		public bool skip_scan { get; set; default = false; }
		public bool project_summary_only { get; set; default = false; }

		// --- vector.* ---

		public string query { get; set; default = ""; }
		public int max_results { get; set; default = 0; }
		public string language { get; set; default = ""; }
		public string element_type { get; set; default = ""; }
		public string category { get; set; default = ""; }
		public string only_file { get; set; default = ""; }
		public string format { get; set; default = ""; }
		public string file_path { get; set; default = ""; }
		public string ast_path { get; set; default = ""; }

		// --- file.* ---

		public string content { get; set; default = ""; }
		public bool buffer_dirty { get; set; default = false; }
		public int64 last_known_mtime { get; set; default = 0; }
	}
}
