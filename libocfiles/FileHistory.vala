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
	 * V2 approve/revert RPC handle (''file_history.id'' + path).
	 */
	public class FileHistory : Object
	{
		public weak ProjectManager manager { get; set; }
		public int64 id { get; set; default = 0; }
		public string path { get; set; default = ""; }

		public async void rpc_approve() throws GLib.Error
		{
			yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-FileHistory.rpc_approve",
				args = OLLMrpc.args("sx", this.path, this.id)
			});
		}

		/**
		 * Revert on daemon, then refresh buffer via {@link File.read} (**G-2**).
		 *
		 * @throws GLib.Error if the RPC fails
		 */
		public async void rpc_revert() throws GLib.Error
		{
			var response = yield this.manager.rpc.call(
				new OLLMrpc.Request() {
					method = "RPC-FileHistory.rpc_revert",
					args = OLLMrpc.args("sx", this.path, this.id)
				}
			);
			var cached = this.manager.file_cache.get(this.path) as File;
			if (cached == null && response.retval.type() != GLib.Type.INVALID) {
				this.manager.file_cache.set(
					this.path,
					(File) response.retval.get_object()
				);
				cached = this.manager.file_cache.get(this.path) as File;
			}
			if (cached == null && this.manager.active_project != null) {
				try {
					cached = yield this.manager.active_project.fetch_file(
						this.path
					);
				} catch (GLib.Error e) {
					GLib.critical("revert reload lookup failed %s: %s", this.path, e.message);
					this.manager.rpc.notification(new OLLMrpc.Notification() {
						method = "Alert.show",
						message = "Reverted, but could not reload the editor: "
							+ e.message
					});
					return;
				}
			}
			if (cached == null) {
				this.manager.rpc.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "Reverted, but could not reload the editor: "
						+ this.path
				});
				return;
			}
			cached.manager = this.manager;
			if (response.retval.type() != GLib.Type.INVALID) {
				cached.copy_from((File) response.retval.get_object(), {
					"manager",
					"buffer",
					"parent"
				});
			}
			yield cached.read();
		}
	}
}
