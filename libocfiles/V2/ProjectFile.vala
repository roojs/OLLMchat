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
	 * Display wrapper for one {@link File} row in {@link ProjectFiles}.
	 *
	 * V2 client: {@link ProjectFiles.refresh} builds rows from
	 * {@link Folder.fetch_files} RPC. This class is for list binding only
	 * (open-file dropdown, search UI). File operations use {@link File} RPC
	 * methods, not this wrapper.
	 */
	public class ProjectFile : FileBase
	{
		/**
		 * The wrapped {@link File} object.
		 */
		public File file { get; private set; }

		/**
		 * The project folder this file belongs to.
		 */
		public Folder project { get; private set; }

		/**
		 * Whether the wrapped file is active.
		 */
		public bool is_active {
			get { return this.file.is_active; }
			set { }
		}

		/**
		 * Whether the wrapped file is open.
		 */
		public bool is_open {
			get { return this.file.is_open; }
			set { }
		}

		/**
		 * Whether the wrapped file needs approval.
		 */
		public bool is_need_approval {
			get { return this.file.is_need_approval; }
			set { }
		}

		/**
		 * Whether the wrapped file has unsaved changes.
		 */
		public bool is_unsaved {
			get { return this.file.is_unsaved; }
			set { }
		}

		/**
		 * Whether the file was opened in the last 24 hours (recent).
		 */
		public bool is_recent {
			get {
				var last_viewed = this.file.last_viewed;
				if (last_viewed == 0) {
					return false;
				}
				var now = new GLib.DateTime.now_utc().to_unix();
				var one_day_ago = now - (24 * 60 * 60);
				return last_viewed >= one_day_ago;
			}
		}

		/**
		 * Vector summary line for agent context ({@link File.to_summary}).
		 *
		 * @param keymap Vector metadata keyed by file id
		 * @param indent Line prefix for nested lists
		 * @return Summary text for this row
		 */
		public override string to_summary(
			Gee.HashMap<int, OLLMfiles.SQT.VectorMetadata> keymap,
			string indent)
		{
			return this.file.to_summary(keymap, indent);
		}

		/**
		 * Constructor.
		 *
		 * @param manager The {@link ProjectManager} instance (required)
		 * @param file The {@link File} to wrap
		 * @param project The project folder this file belongs to
		 */
		public ProjectFile(ProjectManager manager, File file, Folder project)
		{
			base(manager);
			this.file = file;
			this.project = project;
			this.base_type = "pf";
			this.path = file.path;

			this.file.notify["last-viewed"].connect(() => {
				this.notify_property("display-css");
			});
		}

		/**
		 * Display name with path — basename plus grey relative path from project root.
		 */
		public string display_with_path {
			owned get {
				return GLib.Path.get_basename(this.path) +
					"\n<span foreground=\"grey\" size=\"small\">" +
					GLib.Markup.escape_text(this.path.substring(this.project.path.length)) +
					"</span>";
			}
		}

		/**
		 * Display relative path from project root (from {@link File.path}).
		 */
		public string display_relpath {
			owned get {
				return this.path.substring(this.project.path.length);
			}
		}

		/**
		 * Display name with basename only — overridden for {@link ProjectFile}.
		 */
		public string display_basename {
			owned get {
				return this.file.display_basename;
			}
		}

		/**
		 * Display text with status indicators — overridden for {@link ProjectFile}.
		 */
		public override string display_with_indicators {
			get {
				return this.file.display_with_indicators;
			}
		}

		/**
		 * CSS classes array for styling (e.g. {{{oc-recent}}} for recent files).
		 * Notifies when {@link is_recent} changes (via {@link File.last_viewed}).
		 */
		public string[] display_css {
			owned get {
				if (this.is_recent) {
					return { "oc-file-item", "oc-recent" };
				}
				return { "oc-file-item" };
			}
		}

		/**
		 * Icon name for binding in lists — delegates to wrapped {@link File}.
		 */
		public new string icon_name {
			get { return this.file.icon_name; }
			set { }
		}
	}
}
