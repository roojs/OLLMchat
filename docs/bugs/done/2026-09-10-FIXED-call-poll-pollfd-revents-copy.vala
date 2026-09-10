/**
 * Repro: GLib.poll writes revents into the array element, not a
 * stack PollFD that was copied into the array.
 *
 *   valac --pkg gio-2.0 --pkg posix -o /tmp/pollfd-revents \
 *     docs/bugs/done/2026-09-10-FIXED-call-poll-pollfd-revents-copy.vala
 *   /tmp/pollfd-revents
 * Expect: PASS (src.revents==0, arr[0].revents has IN)
 */
void main()
{
	int sv[2];
	if (Posix.socketpair(Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
		stderr.printf("socketpair failed\n");
		Process.exit(2);
	}
	Posix.write(sv[0], "x", 1);

	/* Same shape as Client.call_poll */
	var poll_source = GLib.PollFD();
	poll_source.fd = sv[1];
	poll_source.events = GLib.IOCondition.IN
		| GLib.IOCondition.ERR
		| GLib.IOCondition.HUP;
	var poll_fds = new GLib.PollFD[] { poll_source };
	var n = GLib.poll(poll_fds, 100);

	var src_in = (poll_source.revents & GLib.IOCondition.IN) != 0;
	var arr_in = (poll_fds[0].revents & GLib.IOCondition.IN) != 0;
	stderr.printf(
		"n=%d poll_source.revents=%u poll_fds[0].revents=%u src_IN=%s arr_IN=%s\n",
		n,
		(uint) poll_source.revents,
		(uint) poll_fds[0].revents,
		src_in.to_string(),
		arr_in.to_string());

	Posix.close(sv[0]);
	Posix.close(sv[1]);

	if (n > 0 && !src_in && arr_in) {
		stderr.printf(
			"PASS: call_poll checking poll_source.revents would miss IN\n");
		Process.exit(0);
	}
	stderr.printf("FAIL: unexpected poll/revents shape\n");
	Process.exit(1);
}
