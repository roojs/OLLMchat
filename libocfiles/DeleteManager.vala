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
	 * Centralizes all file deletion logic.
	 * 
	 * Handles filesystem deletion, FileHistory backup creation, database updates,
	 * and cleanup operations. This class provides a single entry point for all
	 * file deletion operations.
	 */
	public class DeleteManager : Object
	{
		/**
		 * Reference to ProjectManager instance.
		 */
		private ProjectManager manager;
		
		/**
		 * Signal emitted when cleanup is performed (after files are deleted).
		 * 
		 * VectorMetadata (in libocvector) can listen to this signal to clean up
		 * vector metadata entries for deleted files using a bulk DELETE query.
		 * 
		 * Emitted by cleanup() after cleanup is complete.
		 * This allows tools to perform bulk cleanup operations efficiently.
		 */
		public signal void on_cleanup();
		
		/**
		* Constructor.
		* 
		* @param manager The ProjectManager instance (required)
		*/
		public DeleteManager(ProjectManager manager)
		{
			this.manager = manager;
		}
		
		/**
		* Delete a file or folder.
		* 
		* Routes to appropriate handler based on file type.
		* 
		* @param filebase The FileBase object to delete (File, Folder, or FileAlias)
		* @param timestamp Timestamp for FileHistory record (required - use GLib.DateTime.now_local() if current time is desired)
		* @throws GLib.Error if deletion fails (FileHistory creation or database update fails)
		*/
		public async void remove(FileBase filebase, GLib.DateTime timestamp) throws GLib.Error
		{
			if (filebase is Folder) {
				yield this.remove_folder((Folder)filebase, timestamp);
				return;
			}
			
			// Handle File and FileAlias the same way (both are files, just different types)
			yield this.remove_file(filebase, timestamp);
		}
		
		/**
		* Delete a file or file alias from filesystem and create FileHistory record.
		* 
		* Handles:
		* 1. Create FileHistory record with backup (must be done before deletion)
		* 2. Delete file/symlink from filesystem (actual file removal)
		* 3. Set delete_id in database
		* 
		* Note: Cleanup from lists (ProjectFiles, FolderFiles) is done separately
		* by calling ProjectFiles.cleanup_deleted() and FolderFiles.cleanup_deleted()
		* Signal emission for VectorMetadata cleanup happens during cleanup, not here.
		* 
		* @param filebase The FileBase object to delete (File or FileAlias)
		* @param timestamp Timestamp for FileHistory record (required)
		* @throws GLib.Error if FileHistory creation or database update fails
		*/
		private async void remove_file(FileBase filebase, GLib.DateTime timestamp) throws GLib.Error
		{
			// 1. Create FileHistory record with backup (must be done BEFORE deletion)
			// If this fails, we abort - file is not deleted yet, so it's safe
			var history = new FileHistory(
				this.manager.db,
				filebase,
				"deleted",
				timestamp
			);
			
			yield history.commit();
			
			// 2. Delete from filesystem (actual file/symlink removal)
			var gfile = GLib.File.new_for_path(filebase.path);
			try {
				yield gfile.delete_async();
			} catch (GLib.Error e) {
				// File might already be gone, or deletion failed
				// We still need to set delete_id so system knows it's deleted
				GLib.warning("DeleteManager.remove_file: Failed to delete file %s from filesystem: %s", 
					filebase.path, e.message);
				// Continue - we'll still set delete_id
			}
			
			// 3. Link database record to FileHistory deletion record
			// This is critical - if this fails, file is deleted but not tracked
			// Note: saveToDB() doesn't throw errors, but we've already created FileHistory
			// so the deletion is at least partially tracked
			filebase.delete_id = history.id;
			filebase.saveToDB(this.manager.db, null, false);
			
			// Note: Signal emission happens during cleanup 
			//  (in ProjectFiles.cleanup_deleted() / FolderFiles.cleanup_deleted())
		}
		
		/**
		* Delete a folder from filesystem and create FileHistory record.
		* 
		* Handles:
		* 1. Create FileHistory record with backup (must be done before deletion)
		* 2. Recursively delete folder and all contents from filesystem
		* 3. Set delete_id in database
		* 
		* Note: Cleanup from lists (ProjectFiles, FolderFiles) is done separately
		* by calling ProjectFiles.cleanup_deleted() and FolderFiles.cleanup_deleted()
		* Signal emission for VectorMetadata cleanup happens during cleanup, not here.
		* 
		* @param folder The Folder object to delete
		* @param timestamp Timestamp for FileHistory record (required)
		* @throws GLib.Error if FileHistory creation or database update fails
		*/
		private async void remove_folder(Folder folder, GLib.DateTime timestamp) throws GLib.Error
		{
			// 1. Create FileHistory record with backup (must be done BEFORE deletion)
			// If this fails, we abort - folder is not deleted yet, so it's safe
			var history = new FileHistory(
				this.manager.db,
				folder,
				"deleted",
				timestamp
			);
			
			yield history.commit();
			
			// 2. Recursively delete all children first (files and subfolders)
			// Make a copy of children list since we'll be modifying the original
			var children_copy = new Gee.ArrayList<FileBase>();
			foreach (var child in folder.children.items) {
				children_copy.add(child);
			}
			
			// Recursively delete each child (use same timestamp for all children in same operation)
			foreach (var child in children_copy) {
				if (child is Folder) {
					yield this.remove_folder((Folder)child, timestamp);
				} else {
					yield this.remove_file(child, timestamp);
				}
			}
			
			// 3. Delete the folder itself from filesystem (after all children are deleted)
			var gfile = GLib.File.new_for_path(folder.path);
			try {
				yield gfile.delete_async();
			} catch (GLib.Error e) {
				// Folder might already be gone, or deletion failed
				// We still need to set delete_id so system knows it's deleted
				GLib.warning("DeleteManager.remove_folder: Failed to delete folder %s from filesystem: %s", 
					folder.path, e.message);
				// Continue - we'll still set delete_id
			}
			
			// 4. Link database record to FileHistory deletion record
			// This is critical - if this fails, folder is deleted but not tracked
			// Note: saveToDB() doesn't throw errors, but we've already created FileHistory
			// so the deletion is at least partially tracked
			folder.delete_id = history.id;
			folder.saveToDB(this.manager.db, null, false);
			
			// Note: Signal emission happens during cleanup (in FolderFiles.cleanup_deleted())
		}
			
		/**
		* Cleanup deleted files from in-memory data structures.
		* 
		* This method iterates through all projects and cleans up deleted files
		* from ProjectFiles and FolderFiles lists. After cleanup is complete,
		* it emits the on_cleanup signal for bulk VectorMetadata cleanup.
		* 
		* This should be called after files are deleted (during cleanup phase).
		*/
		public async void cleanup()
		{
			// Iterate through all projects in manager.projects
			foreach (var project in this.manager.projects.project_map.values) {
				// Call project.project_files.cleanup_deleted() for each project
				yield project.project_files.cleanup_deleted();
				
				// Call project.children.cleanup_deleted() for each project (recursively handles subfolders)
				yield project.children.cleanup_deleted();
			}
			
			// After all cleanup is complete, emit on_cleanup signal
			this.on_cleanup();
		}
	}
}
