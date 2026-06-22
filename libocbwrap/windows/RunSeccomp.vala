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
	 * Windows stub seccomp aggregator — all methods are no-ops.
	 */
	public class RunSeccomp : GLib.Object
	{
		public const int SYNC_SOCK_CHILD_FD = 3;

		public string network { get; private set; default = ""; }
		public string fs { get; private set; default = ""; }
		public string skipped {
			get; private set; default = "seccomp is not available on Windows";
		}
		public unowned Bubble bubble { get; private set; }

		public RunSeccomp (Bubble sandbox_bubble)
		{
			this.bubble = sandbox_bubble;
		}

		public void wire_launcher (GLib.SubprocessLauncher launcher)
		{
		}

		public void finish_handshake()
		{
		}

		public void detach_sources()
		{
		}

		public void finish_evidence_formatting()
		{
		}
	}
}
