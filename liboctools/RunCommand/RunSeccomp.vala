/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OLLMtools.RunCommand
{
	/**
	 * Seccomp user-notify setup and aggregation for a single bubblewrap run.
	 *
	 * Installs NOTIFY rules in the spawn child (before exec into bwrap), passes the
	 * notify fd to the parent, and records socket/connect/openat events on the parent
	 * main context. Evidence strings are produced for tool output when NOTIFY succeeds.
	 */
	public class RunSeccomp : GLib.Object
	{
		/**
		 * Fixed child fd for the sync socket end (must not collide with stdio 0–2).
		 */
		public const int SYNC_SOCK_CHILD_FD = 3;

		public string network { get; private set; default = ""; }
		public string fs { get; private set; default = ""; }
		public string skipped { get; private set; default = ""; }

		int parent_sock = -1;
		int notify_fd = -1;
		uint unix_fd_source = 0;

		int nr_socket = -1;
		int nr_connect = -1;
		int nr_openat = -1;
		int count_socket = 0;
		int count_connect = 0;
		string[] openat_paths = {};

		static bool child_want_network;
		static bool child_want_fs;

		public RunSeccomp ()
		{
			this.nr_socket = Seccomp.syscall_resolve_name ("socket");
			this.nr_connect = Seccomp.syscall_resolve_name ("connect");
			this.nr_openat = Seccomp.syscall_resolve_name ("openat");
		}

		/**
		 * Add one SCMP_ACT_NOTIFY rule for a syscall name.
		 *
		 * @param ctx seccomp filter under construction in the child
		 * @param syscall_name syscall name understood by libseccomp
		 * @return 0 on success, negative on failure
		 */
		static int add_notify (Seccomp.Filter ctx, string syscall_name)
		{
			return ctx.rule_add_array (
				Seccomp.SCMP_ACT_NOTIFY,
				Seccomp.syscall_resolve_name (syscall_name),
				0,
				null);
		}

		/**
		 * Add NOTIFY rules for socket/connect and optionally openat.
		 */
		static int add_notify_rules (Seccomp.Filter ctx, bool want_network, bool want_fs)
		{
			int r;
			if (want_network) {
				r = RunSeccomp.add_notify (ctx, "socket");
				if (r < 0) {
					return r;
				}
				r = RunSeccomp.add_notify (ctx, "connect");
				if (r < 0) {
					return r;
				}
			}
			if (want_fs) {
				r = RunSeccomp.add_notify (ctx, "openat");
				if (r < 0) {
					return r;
				}
			}
			return 0;
		}

		static void child_seccomp_handshake ()
		{
			int sock = RunSeccomp.SYNC_SOCK_CHILD_FD;
			var ctx = new Seccomp.Filter (Seccomp.SCMP_ACT_ALLOW);
			if (RunSeccomp.add_notify_rules (ctx, RunSeccomp.child_want_network, RunSeccomp.child_want_fs) < 0) {
				return;
			}
			if (SeccompLinux.prctl (SeccompLinux.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
				return;
			}
			if (ctx.load () < 0) {
				return;
			}
			int nfd = ctx.notify_fd ();
			if (nfd < 0) {
				return;
			}
			if (Seccomp.pass_unix_fd (sock, nfd) != 0) {
				Posix.close (nfd);
				return;
			}
			Posix.close (nfd);
			var sync = new uint8[1];
			if (Posix.read (sock, sync, 1) != 1 || sync[0] != 'S') {
				return;
			}
			Posix.close (sock);
		}

		/**
		 * Prepare a launcher: socketpair, map child end to SYNC_SOCK_CHILD_FD, child_setup installs filter.
		 */
		public void wire_launcher (
			GLib.SubprocessLauncher launcher,
			bool want_network_syscalls,
			bool want_fs_syscalls)
		{
			int[] sv = { 0, 0 };
			if (Posix.socketpair (Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
				this.skipped = "seccomp: socketpair failed";
				return;
			}
			this.parent_sock = sv[0];
			launcher.take_fd (sv[1], RunSeccomp.SYNC_SOCK_CHILD_FD);
			Posix.close (sv[1]);
			RunSeccomp.child_want_network = want_network_syscalls;
			RunSeccomp.child_want_fs = want_fs_syscalls;
			launcher.set_child_setup (() => {
				RunSeccomp.child_seccomp_handshake ();
			});
		}

		/**
		 * After spawn: receive notify fd, always send sync byte so the child never blocks.
		 */
		public void finish_handshake ()
		{
			if (this.parent_sock < 0) {
				this.skipped = "seccomp: internal error (no sync socket)";
				return;
			}
			int nfd = Seccomp.receive_unix_fd (this.parent_sock);
			if (nfd < 0) {
				this.skipped = "Seccomp user-notify was not set up for this run; syscall evidence is unavailable.";
			}
			uint8[] sync_b = { (uint8) 'S' };
			if (Posix.write (this.parent_sock, sync_b, 1) != 1) {
				this.skipped = "Seccomp user-notify handshake did not complete; syscall evidence is unavailable.";
				if (nfd >= 0) {
					Posix.close (nfd);
				}
				Posix.close (this.parent_sock);
				this.parent_sock = -1;
				this.notify_fd = -1;
				return;
			}
			Posix.close (this.parent_sock);
			this.parent_sock = -1;
			if (nfd >= 0) {
				this.notify_fd = nfd;
			} else {
				this.notify_fd = -1;
			}
		}

		/**
		 * Best-effort pathname for an openat user-notify event (process_vm_readv).
		 *
		 * @param ev kernel notification payload
		 * @return path text or null
		 */
		string? decode_openat_path (Seccomp.Notif ev)
		{
			if (this.notify_fd < 0) {
				return null;
			}
			if (ev.sc_data.nr != this.nr_openat) {
				return null;
			}
			if (Seccomp.notify_id_valid (this.notify_fd, ev.id) != 0) {
				return null;
			}
			uint64 path_address = ev.sc_data.args[1];
			if (path_address == 0) {
				return null;
			}
			const int OPENAT_PATH_CAP = 4096;
			var local = new uint8[OPENAT_PATH_CAP];
			size_t copy_len = local.length - 1;
			var local_iov = Posix.iovector () { iov_base = local, iov_len = copy_len };
			var remote_iov = Posix.iovector () {
				iov_base = (void*) (uintptr) path_address,
				iov_len = copy_len
			};
			ssize_t n = Seccomp.vm_readv (
				(int) ev.pid,
				&local_iov,
				1,
				&remote_iov,
				1,
				0);
			if (n <= 0) {
				return null;
			}
			local[n] = 0;
			size_t run = 0;
			for (; run < (size_t) n && local[run] != 0; run++) {
			}
			return ((string) local).substring (0, (long) run);
		}

		void on_notify_event (Seccomp.Notif ev)
		{
			if (ev.sc_data.nr == this.nr_socket) {
				this.count_socket++;
				return;
			}
			if (ev.sc_data.nr == this.nr_connect) {
				this.count_connect++;
				return;
			}
			if (ev.sc_data.nr != this.nr_openat) {
				return;
			}
			string? p = this.decode_openat_path (ev);
			if (p != null) {
				this.openat_paths += p;
			}
		}

		/**
		 * Drain the notify fd until EAGAIN (non-blocking).
		 */
		public void drain_notify_readable ()
		{
			if (this.notify_fd < 0) {
				return;
			}
			for (;;) {
				Seccomp.Notif* req_ptr;
				Seccomp.NotifResp* resp_ptr;
				if (Seccomp.notify_alloc (out req_ptr, out resp_ptr) != 0) {
					return;
				}
				int r = Seccomp.notify_receive (this.notify_fd, req_ptr);
				if (r < 0) {
					Seccomp.notify_free (req_ptr, resp_ptr);
					if (Posix.errno == Posix.EAGAIN || Posix.errno == Posix.EWOULDBLOCK) {
						return;
					}
					return;
				}
				Seccomp.Notif ev = *req_ptr;
				this.on_notify_event (ev);
				resp_ptr.id = ev.id;
				resp_ptr.val = 0;
				resp_ptr.error = 0;
				resp_ptr.flags = Seccomp.USER_NOTIF_FLAG_CONTINUE;
				Seccomp.notify_respond (this.notify_fd, resp_ptr);
				Seccomp.notify_free (req_ptr, resp_ptr);
			}
		}

		/**
		 * Attach an IO watch on the default main context for NOTIFY while the subprocess runs.
		 */
		public void attach_notify_loop ()
		{
			if (this.notify_fd < 0) {
				return;
			}
			int fl = Posix.fcntl (this.notify_fd, Posix.F_GETFL, 0);
			if (fl >= 0) {
				Posix.fcntl (this.notify_fd, Posix.F_SETFL, fl | Posix.O_NONBLOCK);
			}
			var ch = new GLib.IOChannel.unix_new (this.notify_fd);
			ch.set_flags (GLib.IOFlags.NONBLOCK);
			this.unix_fd_source = ch.add_watch (
				GLib.IOCondition.IN | GLib.IOCondition.HUP,
				(ch, cond) => {
					this.drain_notify_readable ();
					return true;
				});
		}

		/**
		 * Build network/fs appendix strings from counters (call after process exit + drain).
		 */
		public void finish_evidence_formatting ()
		{
			if (this.count_socket > 0 || this.count_connect > 0) {
				string summary = "socket (%d×), connect (%d×)".printf (
					this.count_socket,
					this.count_connect);
				this.network = (@"---
Sandbox: networking was disabled for this run, but the command attempted network-related operations:

$(summary)

To enable networking on a later run, pass \"network\": true in run_command (user approval required).
").chomp ();
			}
			if (this.openat_paths.length > 0) {
				string paths_block = string.joinv ("\n", this.openat_paths);
				this.fs = (@"---
Sandbox: a write or filesystem operation targeted a path outside the directories allowed for this run.

$(paths_block)

To request access, add write_roots: a semicolon-separated list of absolute directory roots, e.g.
  \"write_roots\": \"/path/to/output;/path/to/cache\"
Avoid \"/\" or entire home unless necessary; users often reject broad paths.
").chomp ();
			}
		}

		/**
		 * Remove fd source and close fds (safe from exec finally if spawn failed early).
		 */
		public void detach_sources ()
		{
			if (this.unix_fd_source != 0) {
				GLib.Source.remove (this.unix_fd_source);
				this.unix_fd_source = 0;
			}
			if (this.notify_fd >= 0) {
				Posix.close (this.notify_fd);
				this.notify_fd = -1;
			}
			if (this.parent_sock >= 0) {
				Posix.close (this.parent_sock);
				this.parent_sock = -1;
			}
		}
	}
}
