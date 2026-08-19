/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc.Live
{
	/**
	 * One fd passed over ''SCM_RIGHTS'' on a Unix stream socket.
	 *
	 * Caller sets {@link fd} and passes this to
	 * {@link OLLMrpc.Transport.Connection.write}. {@link BufferStream} calls
	 * {@link send} / {@link receive} on the fd channel socket only.
	 */
	public class Buffer : GLib.Object
	{
		public int fd { get; set; default = -1; }

		public Buffer(int fd = -1)
		{
			this.fd = fd;
		}

		public void send(GLib.Socket socket) throws GLib.Error
		{
			uint8 tag = 0;
			GLib.OutputVector[] vectors = {
				GLib.OutputVector() {
					buffer = &tag,
					size = 1
				}
			};
			var fd_list = new GLib.UnixFDList();
			fd_list.append(this.fd);
			GLib.SocketControlMessage[] messages = {
				new GLib.UnixFDMessage.with_fd_list(fd_list)
			};
			socket.send_message(null, vectors, messages, 0, null);
		}

		public void receive(GLib.Socket socket) throws GLib.Error
		{
			uint8 tag = 0;
			GLib.InputVector[] vectors = {
				GLib.InputVector() {
					buffer = &tag,
					size = 1
				}
			};
			GLib.SocketControlMessage[]? messages = null;
			int flags = 0;
			ssize_t n = socket.receive_message(
				null,
				vectors,
				out messages,
				ref flags,
				null
			);
			if (n <= 0) {
				throw new GLib.IOError.FAILED("Buffer receive failed");
			}
			this.fd = -1;
			if (messages == null) {
				return;
			}
			foreach (var cm in messages) {
				var fd_msg = cm as GLib.UnixFDMessage;
				if (fd_msg == null) {
					continue;
				}
				var stolen = fd_msg.steal_fds();
				if (stolen.length > 0) {
					this.fd = stolen[0];
					return;
				}
			}
		}
	}
}
