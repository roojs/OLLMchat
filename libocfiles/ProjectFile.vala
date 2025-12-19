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

namespace OLLMfiles
{
	/**
	 * Wrapper around a File object for use in project file lists.
	 * 
	 * Used for searching on open files and files that need updating.
	 * Provides all interfaces of FileBase but overrides display name properties.
	 */
	public class ProjectFile : FileBase
	{
		/**
		 * The wrapped File object.
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
			set {   }
		}
		
		
		/**
		 * Whether the wrapped file needs approval.
		 */
		public bool needs_approval {
			get { return this.file.needs_approval; }
			set {   }
		}
		
		/**
		 * Whether the wrapped file has unsaved changes.
		 */
		public bool is_unsaved {
			get { return this.file.is_unsaved; }
			set {   }
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
		 * CSS classes array for styling (e.g., ["oc-file-item", "oc-recent"] for recent files).
		 * Notifies when is_recent changes (via file.last_viewed changes).
		 */
		public string[] display_css {
			owned get {
				return this.is_recent ? new string[] { "oc-file-item", "oc-recent" } : new string[] { "oc-file-item" };
			}
		}
		
		/**
		 * Icon name for binding in lists - delegates to wrapped file.
		 */
		public new string icon_name {
			get { return this.file.icon_name; }
			set {    }
		}
		
		/**
		 * Relative path from project root when file is accessed through a symlink.
		 * If empty (default), the file is not inside a symlink and display_relpath
		 * will calculate the path normally.
		 */
		public string relpath { get; set; default = ""; }
		
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 * @param file The File object to wrap
		 * @param project The project folder this file belongs to
		 * @param path Optional path (defaults to "" which will use file.path)
		 * @param relpath Optional relative path when file is accessed through a symlink (defaults to "")
		 */
		public ProjectFile(ProjectManager manager, File file, Folder project, string path = "", string relpath = "")
		{
			base(manager);
			this.file = file;
			this.project= project;
			this.base_type = "pf";
			this.relpath = relpath;
			if (path == "") {
				this.path = file.path;
			} else {
				this.path = path;
			}
			
			// Watch file.last_viewed to notify display_css when is_recent changes
			this.file.notify["last-viewed"].connect(() => {
				this.notify_property("display-css");
			});
			
			// Watch file properties to notify display_with_indicators when they change
			this.file.notify["is-active"].connect(() => {
				this.notify_property("is-active");
				this.notify_property("display-with-indicators");
			});
			this.file.notify["needs-approval"].connect(() => {
				this.notify_property("display-with-indicators");
			});
			this.file.notify["is-unsaved"].connect(() => {
				this.notify_property("display-with-indicators");
			});
		}
		
		/**
		 * Display name with path - shows relative path from project root.
		 */
		public string display_with_path {
			owned get {
				
				// Calculate relative path by removing project path prefix
				
				return GLib.Path.get_basename(this.path) +
					"\n<span foreground=\"grey\" size=\"small\">" +
					GLib.Markup.escape_text(this.path.substring(this.project.path.length)) +
					"</span>";
			}
		}
		
		/**
		 * Display relative path from project root.
		 * If relpath is set (file accessed through symlink), use that.
		 * Otherwise, calculate from this.path by removing project path prefix.
		 */
		public string display_relpath {
			owned get {
				if (this.relpath != "") {
					return this.relpath;
				}
				// Calculate relative path by removing project path prefix
				return this.path.substring(this.project.path.length);
				
			}
		}
		
		/**
		 * Display name with basename only - overridden for ProjectFile.
		 */
		public string display_basename {
			owned get {
				return this.file.display_basename;
			}
		}
		
		/**
		 * Display text with status indicators - shows basename + indicators on first line,
		 * relative directory path in grey small text on second line.
		 */
		public   string display_with_indicators {
			owned get {
				// Get relative path and extract directory part
 				// Remove leading slash from relpath if present
				var relpath = this.display_relpath.has_prefix("/") ? this.display_relpath.substring(1) : relpath;
				
				// Build display text with basename and status indicators
				var dir_suffix = relpath == "" ? "" : GLib.Markup.escape_text( GLib.Path.get_dirname(relpath) );
					
				return this.display_basename +
					(!this.needs_approval ? " ✓" : "") +
					(this.is_unsaved ? " ●" : "") +
					"\n<span foreground=\"grey\" size=\"small\">"  + dir_suffix + "</span>";
			}
		}
	}
}
