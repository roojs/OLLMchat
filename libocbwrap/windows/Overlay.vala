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
	 * Windows stub overlay — {@link create} and {@link cleanup} are no-ops.
	 */
	public class Overlay : GLib.Object
	{
		public string project_path { get; set; default = ""; }
		public Gee.HashMap<string, string> write_roots {
			get; set; default = new Gee.HashMap<string, string> ();
		}
		public FileVerification verification { get; construct; }
		public string overlay_dir { get; private set; default = ""; }
		public Gee.HashMap<string, string> overlay_map {
			get; private set; default = new Gee.HashMap<string, string> ();
		}

		public Overlay (FileVerification verification)
		{
			Object (verification: verification);
		}

		public void create() throws Error
		{
		}

		public void cleanup()
		{
		}
	}
}
