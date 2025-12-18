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
	 * Base class for git operations with default no-op implementations.
	 * 
	 * Provides a default implementation that does nothing, allowing
	 * libocfiles to work without git dependencies. Concrete implementations
	 * (e.g., in liboccoder) can override these methods to provide actual
	 * git functionality.
	 */
	public class GitProviderBase : Object
	{
		/**
		 * Initialize git library.
		 * 
		 * Called once when ProjectManager is constructed.
		 */
		public virtual void initialize() 
		{ 
		}
		
		/**
		 * Discover and open git repository for a folder.
		 * 
		 * The repository should be stored on the folder object using set_data/get_data.
		 * 
		 * @param folder The folder to discover repository for
		 */
		public virtual void discover_repository(Folder folder) 
		{ 
		}
		
		/**
		 * Check if a path is ignored by git.
		 * 
		 * @param folder The folder containing the repository
		 * @param relative_path The relative path from repository root to check
		 * @return true if the path is ignored, false otherwise
		 */
		public virtual bool path_is_ignored(Folder folder, string relative_path) 
		{ 
			return false; 
		}
		
		/**
		 * Get the working directory path of the repository.
		 * 
		 * @param folder The folder containing the repository
		 * @return The working directory path, or null if not available
		 */
		public virtual string? get_workdir_path(Folder folder) 
		{ 
			return null; 
		}
		
		/**
		 * Check if a repository exists for the folder.
		 * 
		 * @param folder The folder to check
		 * @return true if repository exists, false otherwise
		 */
		public virtual bool repository_exists(Folder folder) 
		{ 
			return false; 
		}
	}
}
