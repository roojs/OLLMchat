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

namespace OLLMfiles.Rpc
{
	/**
	 * Typed RPC call parameters — wire key `params`, Vala property {@link param}.
	 */
	public class CallParam : GLib.Object, Json.Serializable
	{
		/** Positional string arguments when wire sends a JSON array. */
		public string[] args { get; set; default = new string[] {}; }

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
		public int cursor_line { get; set; default = 0; }
		public int cursor_offset { get; set; default = 0; }
		public int scroll_position { get; set; default = 0; }
		public bool buffer_dirty { get; set; default = false; }
		public int64 last_known_mtime { get; set; default = 0; }

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}
	}
}
