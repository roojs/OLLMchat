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
	 * V2 approve/revert RPC handle ({@code file_history.id} + path).
	 */
	public class FileHistory : Object
	{
		public weak ProjectManager manager { get; set; }
		public int64 id { get; set; default = 0; }
		public string path { get; set; default = ""; }

		public async void approve()
		{
			yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "FileHistory.approve",
				param = new OLLMfilesd.FileParams() {
					path = this.path,
					id = this.id
				}
			});
		}

		/**
		 * Revert on daemon, then refresh buffer via {@link File.read} (**G-2**).
		 */
		public async void revert()
		{
			var response = yield this.manager.rpc.call(
				new OLLMrpc.Request() {
					method = "FileHistory.revert",
					param = new OLLMfilesd.FileParams() {
						path = this.path,
						id = this.id
					}
				}
			);
			if (response.error != null) {
				return;
			}
			var cached = this.manager.file_cache.get(this.path) as File;
			if (cached == null && response.result is File) {
				this.manager.file_cache.set(
					this.path,
					(File) response.result
				);
				cached = this.manager.file_cache.get(this.path) as File;
			}
			if (cached == null && this.manager.active_project != null) {
				cached = yield this.manager.active_project.fetch_file(
					this.path
				);
			}
			if (cached == null) {
				return;
			}
			cached.manager = this.manager;
			if (response.result is File) {
				cached.copy_from((File) response.result, {
					"manager",
					"buffer",
					"parent"
				});
			}
			yield cached.read();
		}
	}
}
