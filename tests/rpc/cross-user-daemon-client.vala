/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Client for the cross-user ollmfilesd socket regression. Speaks the
 * same bin RPC the desktop uses. Prints one status line per step so
 * the shell harness can tell a refused caller from a completed call.
 */

int main(string[] args)
{
	if (args.length < 3) {
		stdout.printf("usage: %s SOCKET COMMAND ...\n", args[0]);
		return 2;
	}
	OLLMrpc.rpc_register();
	GLib.SocketConnection conn;
	try {
		conn = new GLib.SocketClient().connect(
			new GLib.UnixSocketAddress(args[1]), null);
	} catch (GLib.Error e) {
		stdout.printf("connect=denied %s\n", e.message);
		return 0;
	}
	stdout.printf("connect=ok\n");

	switch (args[2]) {
		case "fd":
			var held = true;
			var sock = conn.get_socket();
			try {
				sock.set_blocking(false);
			} catch (GLib.Error e) {
				stdout.printf("held=no\n");
				return 0;
			}
			var pollfd = GLib.PollFD();
			pollfd.fd = sock.get_fd();
			pollfd.events = GLib.IOCondition.IN | GLib.IOCondition.HUP |
				GLib.IOCondition.ERR;
			var poll_fds = new GLib.PollFD[1];
			poll_fds[0] = pollfd;
			if (GLib.poll(poll_fds, 1000) > 0) {
				var chunk = new uint8[32];
				var n = (ssize_t) 0;
				try {
					n = sock.receive(chunk);
				} catch (GLib.Error e) {
					held = false;
				}
				if ((poll_fds[0].revents & GLib.IOCondition.HUP) != 0
					|| (poll_fds[0].revents & GLib.IOCondition.ERR) != 0
					|| n == 0) {
					held = false;
				}
			}
			if (held) {
				stdout.printf("held=yes\n");
				return 0;
			}
			stdout.printf("held=no\n");
			return 0;

		case "read":
			if (args.length < 5) {
				stdout.printf("usage: read SOCKET PATH NEEDLE...\n");
				return 2;
			}
			var read_out = new GLib.DataOutputStream(conn.get_output_stream());
			var read_bin = new OLLMrpc.Bin.Stream(null, read_out);
			var read_req = new OLLMrpc.Request() {
				id = 1,
				method = "File.read",
				args = OLLMrpc.args("s", args[3])
			};
			try {
				read_bin.write(read_req);
				read_out.flush();
			} catch (GLib.Error e) {
				stdout.printf("reply=error %s\n", e.message);
				return 0;
			}
			var read_sock = conn.get_socket();
			try {
				read_sock.set_blocking(false);
			} catch (GLib.Error e) {
				stdout.printf("reply=error %s\n", e.message);
				return 0;
			}
			var body = new GLib.ByteArray();
			var idle = false;
			while (!idle && body.len < 1024 * 1024) {
				var read_poll = GLib.PollFD();
				read_poll.fd = read_sock.get_fd();
				read_poll.events = GLib.IOCondition.IN | GLib.IOCondition.HUP;
				var read_fds = new GLib.PollFD[1];
				read_fds[0] = read_poll;
				if (GLib.poll(read_fds, 1500) <= 0) {
					idle = true;
					continue;
				}
				if ((read_fds[0].revents & GLib.IOCondition.IN) == 0) {
					idle = true;
					continue;
				}
				var chunk = new uint8[4096];
				var n = (ssize_t) 0;
				try {
					n = read_sock.receive(chunk);
				} catch (GLib.Error e) {
					idle = true;
					continue;
				}
				if (n == 0) {
					idle = true;
					continue;
				}
				body.append(chunk[0:n]);
			}
			var hit = false;
			var needle_i = 4;
			while (!hit && needle_i < args.length) {
				var needle = args[needle_i];
				needle_i++;
				if (needle.length == 0 || needle.length > body.len) {
					continue;
				}
				var start = 0;
				while (start + needle.length <= (int) body.len) {
					var same = true;
					var j = 0;
					while (j < needle.length) {
						if (body.data[start + j] != needle.data[j]) {
							same = false;
							break;
						}
						j++;
					}
					if (same) {
						hit = true;
						break;
					}
					start++;
				}
			}
			if (hit) {
				stdout.printf("hit=yes bytes=%u\n", body.len);
				return 0;
			}
			stdout.printf("hit=no bytes=%u\n", body.len);
			return 0;

		case "write":
			if (args.length < 5) {
				stdout.printf("usage: write SOCKET PATH CONTENT\n");
				return 2;
			}
			var write_in = new GLib.DataInputStream(conn.get_input_stream());
			var write_out = new GLib.DataOutputStream(conn.get_output_stream());
			var write_bin = new OLLMrpc.Bin.Stream(write_in, write_out);
			var write_req = new OLLMrpc.Request() {
				id = 1,
				method = "File.rpc_write",
				args = OLLMrpc.args(
					"ssssu", args[3], args[4], "f", "", (uint) 0644)
			};
			try {
				write_bin.write(write_req);
				write_out.flush();
				var write_res = write_bin.parse() as OLLMrpc.Response;
				if (write_res == null) {
					stdout.printf("reply=none\n");
					return 0;
				}
				if (write_res.error != null) {
					stdout.printf("reply=error %s\n", write_res.error.message);
					return 0;
				}
				stdout.printf("reply=%s\n", write_res.msg);
			} catch (GLib.Error e) {
				stdout.printf("reply=error %s\n", e.message);
			}
			return 0;

		case "bubble":
			if (args.length < 6) {
				stdout.printf("usage: bubble SOCKET OUTFILE WRITEROOT MARKER\n");
				return 2;
			}
			var bubble_in = new GLib.DataInputStream(conn.get_input_stream());
			var bubble_out = new GLib.DataOutputStream(conn.get_output_stream());
			var bubble_bin = new OLLMrpc.Bin.Stream(bubble_in, bubble_out);
			var roots = new string[1];
			roots[0] = args[4];
			var command = "printf '%s' '" + args[5] + "' > '" + args[3] + "'";
			var create_req = new OLLMrpc.Request() {
				id = 1,
				method = "Sandbox-Bubble.rpc_create",
				args = OLLMrpc.args(
					"sssbSbx", "", command, args[4], true, roots, false,
					(int64) 1)
			};
			try {
				bubble_bin.write(create_req);
				bubble_out.flush();
				var created = bubble_bin.parse() as OLLMrpc.Response;
				if (created == null) {
					stdout.printf("create=none\n");
					return 0;
				}
				if (created.error != null) {
					stdout.printf("create=error %s\n", created.error.message);
					return 0;
				}
				var handle = created.retval.get_uint64();
				stdout.printf("handle=%s\n", handle.to_string());
				var run_req = new OLLMrpc.Request() {
					id = 2,
					method = "Sandbox-Bubble.rpc_run",
					args = OLLMrpc.args("t", handle)
				};
				bubble_bin.write(run_req);
				bubble_out.flush();
				var ran = bubble_bin.parse() as OLLMrpc.Response;
				if (ran == null) {
					stdout.printf("run=none\n");
					return 0;
				}
				if (ran.error != null) {
					stdout.printf("run=error %s\n", ran.error.message);
					return 0;
				}
				stdout.printf("run=ok\n");
			} catch (GLib.Error e) {
				stdout.printf("create=error %s\n", e.message);
			}
			return 0;

		case "pair":
			if (args.length < 4) {
				stdout.printf("usage: pair SOCKET PIN\n");
				return 2;
			}
			var pair_in = new GLib.DataInputStream(conn.get_input_stream());
			var pair_out = new GLib.DataOutputStream(conn.get_output_stream());
			var pair_bin = new OLLMrpc.Bin.Stream(pair_in, pair_out);
			var pair_req = new OLLMrpc.Request() {
				id = 1,
				method = "ClientCert.pair",
				args = OLLMrpc.args("s", args[3])
			};
			try {
				pair_bin.write(pair_req);
				pair_out.flush();
				var paired = pair_bin.parse() as OLLMrpc.Response;
				if (paired == null) {
					stdout.printf("reply=none\n");
					return 0;
				}
				if (paired.error != null) {
					stdout.printf("reply=error %s\n", paired.error.message);
					return 0;
				}
				stdout.printf("reply=%s\n", paired.msg);
			} catch (GLib.Error e) {
				stdout.printf("reply=error %s\n", e.message);
			}
			return 0;

		default:
			stdout.printf("unknown command\n");
			return 2;
	}
}
