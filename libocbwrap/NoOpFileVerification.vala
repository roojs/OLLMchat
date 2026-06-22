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
	 * No-op {@link FileVerification} for callers that never run overlay scan.
	 *
	 * Use when {@link Bubble} or {@link Overlay} must construct but overlay
	 * upper-layer changes are not merged (e.g. long-lived MCP stdio spawn).
	 * Real apply hooks live in {@code ollmfilesd} or {@code liboctools}.
	 */
	public class NoOpFileVerification : GLib.Object, FileVerification
	{
		public async void created(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
		}

		public async void modified(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
		}

		public async void removed(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
		}

		public async void finish()
		{
		}
	}
}
