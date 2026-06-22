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

namespace OLLMbwrap
{
	/**
	 * Windows stub for {@link Bubble} — {@link can_wrap} is always false.
	 *
	 * Callers use {@link can_wrap} and fall back to unsandboxed
	 * {@link GLib.Subprocess} spawn when bubblewrap is unavailable.
	 */
	public class Bubble : GLib.Object
	{
		public static bool can_wrap()
		{
			return false;
		}

		public string project_path { get; set; default = ""; }
		public bool allow_network { get; set; default = false; }
		public string[] write_tokens { get; set; default = {}; }
		public Gee.HashMap<string, string> write_roots {
			get; set; default = new Gee.HashMap<string, string> ();
		}
		public FileVerification verification { get; construct; }
		public Overlay overlay { get; private set; }
		public string bwrap_exe { get; private set; default = ""; }
		public string ret_str { get; private set; default = ""; }
		public string fail_str { get; private set; default = ""; }

		public Bubble (FileVerification verification)
		{
			Object (verification: verification);
			this.overlay = new Overlay (verification);
		}

		public async string exec (string command, string working_dir = "") throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED (
				"Bubble sandboxing is not available on Windows"
			);
		}

		public string[] build_bubble_args (
			string command,
			string working_dir = "") throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED (
				"Bubble sandboxing is not available on Windows"
			);
		}

		public bool can_write (string raw_path)
		{
			return false;
		}
	}
}
