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
	 * Client entry point for file deletion — delegates to {@link File.delete} RPC.
	 *
	 * V2 thin client: no local filesystem removal, {@code FileHistory}, or SQLite.
	 * The daemon {@code ollmfilesd/DeleteManager} performs backup, disk delete,
	 * and index cleanup. Call {@link cleanup} after a batch of deletes to prune
	 * {@link ProjectManager.file_cache} and emit {@link on_cleanup}.
	 */
	public class DeleteManager : Object
	{
		/**
		 * Reference to {@link ProjectManager} instance.
		 */
		private ProjectManager manager;

		/**
		 * Emitted after {@link cleanup} completes.
		 *
		 * Shipping listeners used this for bulk {@code VectorMetadata} cleanup via
		 * in-process SQLite. On V2 the daemon handles vector cleanup; keep the
		 * signal for cutover callers that refresh UI lists after deletion.
		 */
		public signal void on_cleanup();

		/**
		 * Constructor.
		 *
		 * @param manager The {@link ProjectManager} instance (required)
		 */
		public DeleteManager(ProjectManager manager)
		{
			this.manager = manager;
		}

		/**
		 * Delete a file via {@code File.delete} on the daemon.
		 *
		 * {@link Folder} and alias rows are not supported on the client yet
		 * (daemon scan / future {@code Folder.delete} RPC). {@code timestamp} is
		 * ignored — the daemon records {@code FileHistory} with its own clock.
		 *
		 * @param filebase The {@link File} to delete
		 * @param timestamp Ignored on client (API compatibility with shipping)
		 * @throws GLib.Error if the RPC fails or the type is unsupported
		 */
		public async void remove(FileBase filebase, GLib.DateTime timestamp) throws GLib.Error
		{
			switch (filebase.get_type()) {
				case typeof(File):
					var file = (File) filebase;
					if (!yield file.delete()) {
						throw new IOError.FAILED(
							"File.delete RPC failed for %s".printf(file.path)
						);
					}
					if (this.manager.active_file == file) {
						this.manager.activate_file(null);
					}
					this.manager.file_cache.unset(file.path);
					break;
				case typeof(Folder):
					throw new IOError.NOT_SUPPORTED(
						"Folder deletion is daemon-side only"
					);
				default:
					throw new IOError.NOT_SUPPORTED(
						"Unsupported type for client delete"
					);
			}
		}

		/**
		 * Prune deleted rows from {@link ProjectManager.file_cache} and notify listeners.
		 *
		 * V2 client: does not walk {@code ProjectFiles} or {@link FolderFiles}
		 * (no {@code cleanup_deleted} — callers {@link ProjectFiles.refresh} after
		 * delete). Emits {@link on_cleanup} when finished.
		 */
		public async void cleanup()
		{
			var keys = this.manager.file_cache.keys.to_array();
			foreach (var path in keys) {
				var item = this.manager.file_cache.get(path);
				if (item.delete_id > 0) {
					this.manager.file_cache.unset(path);
				}
			}

			this.on_cleanup();
		}
	}
}
