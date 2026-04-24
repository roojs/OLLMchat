/*
 * Proof-of-concept: seccomp user-notify (record + continue) + bubblewrap.
 *
 * Goal (plan 2.22.1): demonstrate parent-visible reporting of what the
 * sandboxed command tried — network syscalls and/or filesystem syscalls —
 * while bubblewrap still enforces isolation (ro root, tmpfs /tmp, optional
 * --unshare-net). Seccomp does not TRAP-kill here; the supervisor responds
 * SECCOMP_USER_NOTIF_FLAG_CONTINUE so the kernel/bwrap policy applies.
 *
 * Mechanism: child installs NOTIFY filter, passes notify fd to parent over
 * a UNIX stream socket (`Seccomp.pass_unix_fd` / `Seccomp.receive_unix_fd`, implemented
 * in vapi/seccomp-fd-pass.c — no Gio in the child after fork/exec), syncs, then execvp("bwrap", ...).
 * The filter is inherited by bwrap and the final shell; the parent reads
 * events on the notify fd (product code would aggregate into tool output).
 *
 * Usage:
 *   oc-test-seccomp-spike network — NOTIFY socket + connect; inner: python3
 *       creates AF_INET SOCK_STREAM (--unshare-net on).
 *   oc-test-seccomp-spike file   — NOTIFY openat + decode pathname (process_vm_readv);
 *       inner: echo to /root/silly.txt under ro root; OK requires that path in a REPORT line.
 *
 * Requires: bwrap on PATH, libseccomp, Linux 5.0+ user-notify; python3 for network inner.
 *
 * `UserNotifExchange` (libseccomp notify buffer pair) lives in `oc-user-notif-exchange.vala`.
 */

const int MAX_NR = 600;
/** Enough for decoded openat paths (matches C spike `PATH_MAX` usage). */
const int SPIKE_PATH_MAX = 4096;

static uint64[] nr_counts;
static int nr_openat = -1;
static bool supervisor_decode_openat_paths;
static bool file_saw_inner_target_path;

/** Read a NUL-terminated string from another process (`process_vm_readv`). */
class TraceeReader {
	public static string? try_dup_string (Posix.pid_t tracee_pid, uint64 remote_address, int max_length = SPIKE_PATH_MAX) {
		if (remote_address == 0 || max_length < 2) {
			return null;
		}
		var local = new uint8[max_length];
		size_t copy_len = local.length - 1;
		var local_iov = Posix.iovector () { iov_base = local, iov_len = copy_len };
		/* `struct iovec.iov_base` is `void*` in C; remote kernel address is not a local pointer type. */
		var remote_iov = Posix.iovector () {
			iov_base = (void*) (uintptr) remote_address,
			iov_len = copy_len
		};
		ssize_t n = Seccomp.vm_readv ((int) tracee_pid, &local_iov, 1, &remote_iov, 1, 0);
		if (n < 0) {
			return null;
		}
		if (n == 0) {
			return null;
		}
		local[n] = 0;
		size_t run = 0;
		for (; run < (size_t) n && local[run] != 0; run++) {
		}
		return ((string) local).substring (0, (long) run);
	}
}

static void append_openat_details_to_report (int notify_fd, Seccomp.Notif ev) {
	if (!supervisor_decode_openat_paths || nr_openat < 0) {
		return;
	}
	if (ev.sc_data.nr != nr_openat || Seccomp.notify_id_valid (notify_fd, ev.id) != 0) {
		return;
	}
	uint64 path_address = ev.sc_data.args[1];
	uint64 open_flags = ev.sc_data.args[2];
	string? path = TraceeReader.try_dup_string ((Posix.pid_t) ev.pid, path_address);
	if (path != null) {
		stdout.printf (" dirfd=%d flags=0x%lx path=\"%s\"",
		               (int) ev.sc_data.args[0], (ulong) open_flags, path);
		if (path == "/root/silly.txt") {
			file_saw_inner_target_path = true;
		}
	} else {
		stdout.printf (" path=(unreadable errno=%d)", Posix.errno);
	}
}

static void print_report_line (Seccomp.Notif ev) {
	string? syscall_name = Seccomp.syscall_resolve_num_arch (ev.sc_data.arch, ev.sc_data.nr);
	stdout.printf ("REPORT: syscall=%s nr=%d tracee_pid=%u",
	               syscall_name ?? "?", ev.sc_data.nr, ev.pid);
}

static void bump_nr_count (Seccomp.Notif ev) {
	if (ev.sc_data.nr >= 0 && ev.sc_data.nr < MAX_NR) {
		nr_counts[ev.sc_data.nr]++;
	}
}

static void run_notify_supervisor (int notify_fd) {
	for (;;) {
		UserNotifExchange? ex = UserNotifExchange.try_begin ();
		if (ex == null) {
			GLib.stderr.printf ("seccomp_notify_alloc failed\n");
			return;
		}
		switch (ex.wait_for_kernel (notify_fd)) {
		case UserNotifExchange.WaitResult.INTERRUPTED:
			continue;
		case UserNotifExchange.WaitResult.CLOSED:
			return;
		case UserNotifExchange.WaitResult.READY:
			break;
		}
		Seccomp.Notif ev = ex.snapshot_request ();
		print_report_line (ev);
		append_openat_details_to_report (notify_fd, ev);
		stdout.putc ('\n');
		stdout.flush ();
		bump_nr_count (ev);
		ex.prepare_continue_reply (ev);
		if (!ex.submit_reply (notify_fd)) {
			GLib.stderr.printf ("seccomp_notify_respond failed\n");
		}
	}
}

static int add_notify_rules (Seccomp.Filter ctx, bool network_mode) {
	int r;
	if (network_mode) {
		r = ctx.rule_add_array (Seccomp.SCMP_ACT_NOTIFY, Seccomp.syscall_resolve_name ("socket"), 0, null);
		if (r < 0) {
			return r;
		}
		r = ctx.rule_add_array (Seccomp.SCMP_ACT_NOTIFY, Seccomp.syscall_resolve_name ("connect"), 0, null);
		if (r < 0) {
			return r;
		}
	} else {
		r = ctx.rule_add_array (Seccomp.SCMP_ACT_NOTIFY, Seccomp.syscall_resolve_name ("openat"), 0, null);
		if (r < 0) {
			return r;
		}
	}
	return 0;
}

static void print_nonzero_counts () {
	stdout.puts ("--- summary (syscall nr -> count) ---\n");
	for (int i = 0; i < MAX_NR; i++) {
		if (nr_counts[i] == 0) {
			continue;
		}
		string? n = Seccomp.syscall_resolve_num_arch (Seccomp.arch_native (), i);
		stdout.printf ("  %s (nr %d): %" + uint64.FORMAT + "u\n",
		               n != null ? n : "?", i, nr_counts[i]);
	}
	stdout.flush ();
}

static int child_run (int sync_sock_fd, bool network_mode) {
	var ctx = new Seccomp.Filter (Seccomp.SCMP_ACT_ALLOW);
	int ar = add_notify_rules (ctx, network_mode);
	if (ar < 0) {
		GLib.stderr.printf ("seccomp_rule_add failed: %d\n", ar);
		return 1;
	}
	if (SeccompLinux.prctl (SeccompLinux.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
		GLib.stderr.printf ("prctl NO_NEW_PRIVS failed\n");
		return 1;
	}
	if (ctx.load () < 0) {
		GLib.stderr.printf ("seccomp_load failed\n");
		return 1;
	}
	int nfd = ctx.notify_fd ();
	if (nfd < 0) {
		GLib.stderr.printf ("seccomp_notify_fd failed (kernel too old?)\n");
		return 1;
	}
	if (Seccomp.pass_unix_fd (sync_sock_fd, nfd) != 0) {
		GLib.stderr.printf ("send notify fd failed\n");
		Posix.close (nfd);
		return 1;
	}
	Posix.close (nfd);
	var sync = new uint8[1];
	if (Posix.read (sync_sock_fd, sync, 1) != 1 || sync[0] != 'S') {
		GLib.stderr.printf ("child: sync read failed\n");
		return 1;
	}
	Posix.close (sync_sock_fd);

	string inner_net = "python3 -c \"import socket; socket.socket(socket.AF_INET, socket.SOCK_STREAM)\"";
	string inner_file = "echo test > /root/silly.txt";
	string inner = network_mode ? inner_net : inner_file;

	string[] argv_net = {
		"bwrap",
		"--unshare-user",
		"--ro-bind", "/", "/",
		"--tmpfs", "/tmp",
		"--ro-bind", "/dev", "/dev",
		"--dev-bind", "/dev/null", "/dev/null",
		"--proc", "/proc",
		"--unshare-net",
		"--",
		"/bin/sh", "-c", inner,
		null
	};
	string[] argv_file = {
		"bwrap",
		"--unshare-user",
		"--ro-bind", "/", "/",
		"--tmpfs", "/tmp",
		"--ro-bind", "/dev", "/dev",
		"--dev-bind", "/dev/null", "/dev/null",
		"--proc", "/proc",
		"--",
		"/bin/sh", "-c", inner,
		null
	};
	string[] argv = network_mode ? argv_net : argv_file;
	Posix.execvp ("bwrap", argv);
	GLib.stderr.printf ("execvp bwrap failed\n");
	return 127;
}

static int run_demo (bool network_mode) {
	if (GLib.Environment.get_variable ("PATH") == null) {
		GLib.Environment.set_variable ("PATH", "/usr/bin:/bin", true);
	}
	int[] sv = { 0, 0 };
	if (Posix.socketpair (Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
		GLib.stderr.printf ("socketpair failed\n");
		return 1;
	}
	if (network_mode) {
		if (Posix.access ("/usr/bin/python3", Posix.X_OK) != 0 && Posix.access ("/bin/python3", Posix.X_OK) != 0) {
			GLib.stderr.printf ("SKIP: python3 not found (/usr/bin/python3 or /bin/python3)\n");
			Posix.close (sv[0]);
			Posix.close (sv[1]);
			return 77;
		}
	}
	int nr_sock = Seccomp.syscall_resolve_name ("socket");
	nr_openat = Seccomp.syscall_resolve_name ("openat");
	if (nr_sock < 0 || nr_openat < 0) {
		GLib.stderr.printf ("syscall_resolve_name failed\n");
		Posix.close (sv[0]);
		Posix.close (sv[1]);
		return 1;
	}
	supervisor_decode_openat_paths = !network_mode;
	file_saw_inner_target_path = false;

	Posix.pid_t pid = Posix.fork ();
	if (pid < 0) {
		GLib.stderr.printf ("fork failed\n");
		Posix.close (sv[0]);
		Posix.close (sv[1]);
		return 1;
	}
	if (pid == 0) {
		Posix.close (sv[1]);
		Posix._exit (child_run (sv[0], network_mode));
	}
	Posix.close (sv[0]);

	int nfd = Seccomp.receive_unix_fd (sv[1]);
	if (nfd < 0) {
		GLib.stderr.printf ("recv notify fd failed (child exited before passing fd?)\n");
		Posix.close (sv[1]);
		Posix.waitpid (pid, null, 0);
		return 1;
	}
	uint8[] sync_b = { (uint8) 'S' };
	if (Posix.write (sv[1], sync_b, 1) != 1) {
		GLib.stderr.printf ("parent sync write failed\n");
		Posix.close (nfd);
		Posix.close (sv[1]);
		Posix.waitpid (pid, null, 0);
		return 1;
	}
	Posix.close (sv[1]);

	var th = new GLib.Thread<bool> ("sc-notify", () => {
		run_notify_supervisor (nfd);
		return true;
	});

	int st = 0;
	if (Posix.waitpid (pid, out st, 0) < 0) {
		GLib.stderr.printf ("waitpid failed\n");
		Posix.close (nfd);
		th.join ();
		return 1;
	}
	Posix.close (nfd);
	th.join ();

	print_nonzero_counts ();

	if (network_mode) {
		if (nr_sock < MAX_NR && nr_counts[nr_sock] > 0) {
			stdout.puts ("OK: network access reporting — observed socket-related syscalls under bwrap (see REPORT lines).\n");
			return 0;
		}
		GLib.stderr.printf ("FAIL: expected at least one socket syscall in notify log.\n");
		return 1;
	}
	if (file_saw_inner_target_path) {
		stdout.puts ("OK: file access reporting — decoded openat path /root/silly.txt (inner echo under bwrap).\n");
		return 0;
	}
	GLib.stderr.printf ("FAIL: never decoded openat for exact path /root/silly.txt (check Yama ptrace / process_vm_readv).\n");
	return 1;
}

int main (string[] args) {
	nr_counts = new uint64[MAX_NR];
	stdout.flush ();
	if (args.length < 2) {
		GLib.stderr.printf ("usage: oc-test-seccomp-spike network|file\n");
		return 2;
	}
	if (Posix.access ("/proc/self/ns/user", Posix.F_OK) != 0) {
		GLib.stderr.printf ("SKIP: user namespaces unavailable (bwrap likely cannot run)\n");
		return 77;
	}
	if (GLib.Environment.get_variable ("PATH") == null || GLib.Environment.get_variable ("PATH").length == 0) {
		GLib.Environment.set_variable ("PATH", "/usr/bin:/bin", true);
	}
	if (GLib.Environment.get_variable ("OLLM_SPIKE_SKIP_BWRAP") == null) {
		if (GLib.Environment.find_program_in_path ("bwrap") == null) {
			GLib.stderr.printf ("SKIP: bwrap not in PATH\n");
			return 77;
		}
	}
	if (args[1] == "network") {
		return run_demo (true);
	}
	if (args[1] == "file") {
		return run_demo (false);
	}
	GLib.stderr.printf ("mode must be \"network\" or \"file\"\n");
	return 2;
}
