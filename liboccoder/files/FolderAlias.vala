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

namespace OLLMcoder.Files
{
	/**
	 * Wrapper class for Folder objects that are aliases/symlinks.
	 * 
	 * Uses FolderFiles to manage children with ListModel implementation.
	 * The alias maintains its own path and parent (where the alias exists),
	 * but children come from the target folder via FolderFiles.
	 */
	public class FolderAlias : Folder
	{
		/**
		 * Constructor.
		 * 
		 * @param manager The ProjectManager instance (required)
		 * Note: points_to and points_to_id must be set after construction (by database loader or when target is known)
		 */
		public FolderAlias(OLLMcoder.ProjectManager manager)
		{
			base(manager);
			this.base_type = "da";
			// is_alias is now computed (returns true for FolderAlias)
			// points_to and points_to_id must be set after construction
		}
		
		/**
		 * Children - returns FolderFiles for the pointed-to folder.
		 * Note: This shadows the base class children property to return FolderFiles instead.
		 */
		public new FolderFiles? children {
			get {
				return ((Folder)this.points_to).children;
			}
		}
		
		/**
		 * Is project - delegates to target folder. unlikly...
		 */
		public override bool is_project {
			get { return ((Folder)this.points_to).is_project; }
			set { ((Folder)this.points_to).is_project = value; }
		}
		
		/**
		 * Project files - delegates to target folder.
		 */
		public override ProjectFiles? project_files {
			get { return ((Folder)this.points_to).project_files; }
			set { ((Folder)this.points_to).project_files = value; }
		}
		
		/**
		 * Last viewed - delegates to target folder.
		 */
		public override int64 last_viewed {
			get { return ((Folder)this.points_to).last_viewed; }
			set { ((Folder)this.points_to).last_viewed = value; }
		}
		
		// last_check_time is a real property (not delegated) - uses base class implementation
	}
}
