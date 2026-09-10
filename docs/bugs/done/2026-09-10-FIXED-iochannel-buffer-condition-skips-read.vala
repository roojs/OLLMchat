/**
 * Repro for docs/bugs/done/2026-09-10-FIXED-iochannel-buffer-condition-skips-read.md
 *
 * Unbuffered IOChannel.get_buffer_condition() does not reflect socket
 * readability — same early-return bug as Client.poll_drain_readable.
 *
 *   valac --pkg gio-2.0 -o /tmp/iochannel-bufcond \
 *     docs/bugs/done/2026-09-10-FIXED-iochannel-buffer-condition-skips-read.vala
 *   /tmp/iochannel-bufcond
 */
void main()
{
	/* A: kernel has data; get_buffer_condition still 0 */
	Socket sv;
	Socket cl;
	try {
		Socket.spawn_socketpair(
			SocketFamily.UNIX, SocketType.STREAM, SocketProtocol.DEFAULT,
			out sv, out cl);
	} catch (Error e) {
		stderr.printf("socketpair: %s\n", e.message);
		Process.exit(2);
	}
	try {
		sv.set_blocking(false);
		cl.set_blocking(false);
	} catch (Error e) {
		stderr.printf("set_blocking: %s\n", e.message);
		Process.exit(2);
	}

	var ch = new IOChannel.unix_new(cl.get_fd());
	try {
		ch.set_encoding(null);
	} catch (IOChannelError e) {
		stderr.printf("set_encoding: %s\n", e.message);
		Process.exit(2);
	}
	ch.set_buffered(false);

	try {
		size_t written = 0;
		sv.send_message(
			null,
			new OutputVector[] { OutputVector() { buffer = (uint8[]) "HELLO\n".data } },
			null,
			0,
			null,
			out written);
		if (written != 6) {
			stderr.printf("send wrote %zu\n", written);
			Process.exit(2);
		}
	} catch (Error e) {
		/* send() simpler */
		try {
			sv.send((uint8[]) "HELLO\n".data, null);
		} catch (Error e2) {
			stderr.printf("send: %s\n", e2.message);
			Process.exit(2);
		}
	}

	var pfd = PollFD();
	pfd.fd = cl.get_fd();
	pfd.events = (uint16) (IOCondition.IN | IOCondition.HUP | IOCondition.ERR);
	var pr = Posix.poll((Posix.pollfd[]) &pfd, 1, 0);
	/* Use GLib.poll instead */
	var gpfd = PollFD() {
		fd = cl.get_fd(),
		events = (uint16) IOCondition.IN
	};
	var gn = Poll.poll({ gpfd }, 0);
	var poll_in = (gn > 0 && (gpfd.revents & IOCondition.IN) != 0);
	var buf_cond = ch.get_buffer_condition();
	stderr.printf("A: poll_IN=%s get_buffer_condition=%u (glib_poll n=%d revents=%u)\n",
		poll_in.to_string(), (uint) buf_cond, gn, (uint) gpfd.revents);
	if (!poll_in || (buf_cond & IOCondition.IN) != 0) {
		stderr.printf("A: UNEXPECTED\n");
		Process.exit(2);
	}
	if ((ch.get_buffer_condition() & IOCondition.IN) == 0) {
		stderr.printf(
			"A: would return without parse/read (bytes left in kernel)\n");
	}

	/* B: io watch fires with IN; buffer_condition still 0 (same as on_read) */
	Socket sv2;
	Socket cl2;
	try {
		Socket.spawn_socketpair(
			SocketFamily.UNIX, SocketType.STREAM, SocketProtocol.DEFAULT,
			out sv2, out cl2);
	} catch (Error e) {
		stderr.printf("socketpair2: %s\n", e.message);
		Process.exit(2);
	}
	var ch2 = new IOChannel.unix_new(cl2.get_fd());
	try {
		ch2.set_encoding(null);
	} catch (IOChannelError e) {
		stderr.printf("set_encoding2: %s\n", e.message);
		Process.exit(2);
	}
	ch2.set_buffered(false);

	var loop = new MainLoop();
	bool watch_has_in = false;
	bool buf_has_in = false;
	uint watch_cond = 0;
	uint buf_cond_b = 0;

	ch2.add_watch(
		IOCondition.IN | IOCondition.HUP | IOCondition.ERR,
		(channel, condition) => {
			watch_cond = (uint) condition;
			buf_cond_b = (uint) channel.get_buffer_condition();
			watch_has_in = (condition & IOCondition.IN) != 0;
			buf_has_in = (channel.get_buffer_condition() & IOCondition.IN) != 0;
			loop.quit();
			return Source.REMOVE;
		});

	Idle.add(() => {
		try {
			sv2.send((uint8[]) "REPLY\n".data, null);
		} catch (Error e) {
			stderr.printf("send2: %s\n", e.message);
		}
		return Source.REMOVE;
	});
	Timeout.add(1000, () => {
		loop.quit();
		return Source.REMOVE;
	});
	loop.run();

	stderr.printf(
		"B: watch_cond=%u buf_cond=%u watch_IN=%s buf_IN=%s\n",
		watch_cond, buf_cond_b,
		watch_has_in.to_string(), buf_has_in.to_string());

	if (watch_has_in && !buf_has_in) {
		stderr.printf("PASS: reproduces bug precondition\n");
		Process.exit(0);
	}
	stderr.printf("FAIL\n");
	Process.exit(1);
}
