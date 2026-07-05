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

namespace OLLMfiles
{
	/**
	 * Pending-approval list row ({{{FileWithHistory}}} wire).
	 * Popover display fields copied from {@link FileBase} — not a tree node.
	 */
	public class FileWithHistory : Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("FileWithHistory", typeof(FileWithHistory));
		}

		public int64 id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public string last_change_type { get; set; default = ""; }
		public int64 last_modified { get; set; default = 0; }
		public int64 approve_id { get; set; default = 0; }
		public int64 reject_id { get; set; default = 0; }

		public string path_basename {
			owned get { return GLib.Path.get_basename(this.path); }
		}

		public string display_approval_text {
			owned get {
				switch (this.last_change_type) {
					case "added":
						return "+ " + this.path_basename;
					case "deleted":
						return "<s>" + this.path_basename + "</s>";
					default:
						return this.path_basename;
				}
			}
		}

		public string display_approval_tooltip {
			owned get {
				switch (this.last_change_type) {
					case "added":
						return "Added " + this.path;
					case "deleted":
						return "Deleted " + this.path;
					case "modified":
						return "Modified " + this.path;
					default:
						return this.path;
				}
			}
		}
	}
}
