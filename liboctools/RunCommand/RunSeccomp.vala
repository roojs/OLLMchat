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
	 * notify fd to the parent, and records socket/connect/fs events on the parent
	 * main context. Evidence strings are produced for tool output when NOTIFY succeeds.
	 */
	public class RunSeccomp : GLib.Object
	{
		private const int AT_FDCWD = -100;

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
		int nr_unlink = -1;
		int nr_unlinkat = -1;
		int nr_rename = -1;
		int nr_renameat2 = -1;
		int count_socket = 0;
		int count_connect = 0;

		Gee.HashMap<string, bool> file_writes = new Gee.HashMap<string, bool> ();
		/** Sandbox profile for this run; set at construction, must outlive this object. */
		public unowned Bubble bubble { get; private set; }

		/**
		 * @param sandbox_bubble Profile for the same bubblewrap run; used for #wire_launcher and policy checks.
		 */
		public RunSeccomp (Bubble sandbox_bubble)
		{
			this.bubble = sandbox_bubble;
			this.nr_socket = Seccomp.syscall_resolve_name ("socket");
			this.nr_connect = Seccomp.syscall_resolve_name ("connect");
			this.nr_openat = Seccomp.syscall_resolve_name ("openat");
			this.nr_unlink = Seccomp.syscall_resolve_name ("unlink");
			this.nr_unlinkat = Seccomp.syscall_resolve_name ("unlinkat");
			this.nr_rename = Seccomp.syscall_resolve_name ("rename");
			this.nr_renameat2 = Seccomp.syscall_resolve_name ("renameat2");
		}

		/**
		 * Add one SCMP_ACT_NOTIFY rule for a syscall name.
		 *
		 * @param ctx seccomp filter under construction in the child
		 * @param syscall_name syscall name understood by libseccomp
		 * @return 0 on success, negative on failure
		 */
		int add_notify (Seccomp.Filter ctx, string syscall_name)
		{
			return ctx.rule_add_array (
				Seccomp.SCMP_ACT_NOTIFY,
				Seccomp.syscall_resolve_name (syscall_name),
				0,
				null);
		}

		/**
		 * Add NOTIFY rules: socket/connect when the sandbox has network off; fs syscalls for path evidence (this profile always on).
		 */
		int add_notify_rules (Seccomp.Filter ctx)
		{
			int r = 0;
			if (!this.bubble.allow_network) {
				r = this.add_notify (ctx, "socket");
				r = r < 0 ? r : this.add_notify (ctx, "connect");
			}
			r = r < 0 ? r : this.add_notify (ctx, "openat");
			r = r < 0 ? r : this.add_notify (ctx, "unlink");
			r = r < 0 ? r : this.add_notify (ctx, "unlinkat");
			r = r < 0 ? r : this.add_notify (ctx, "rename");
			r = r < 0 ? r : this.add_notify (ctx, "renameat2");
			return r;
		}

		/**
		 * Runs in the child after fork, before exec. NOTIFY rules follow #bubble.
		 */
		void child_seccomp_handshake ()
		{
			int sock = RunSeccomp.SYNC_SOCK_CHILD_FD;
			var ctx = new Seccomp.Filter (Seccomp.SCMP_ACT_ALLOW);
			if (this.add_notify_rules (ctx) < 0) {
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
		 * NOTIFY policy is read from #bubble in the child (see #child_seccomp_handshake).
		 */
		public void wire_launcher (GLib.SubprocessLauncher launcher)
		{
			int[] sv = { 0, 0 };
			if (Posix.socketpair (Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
				this.skipped = "seccomp: socketpair failed";
				return;
			}
			this.parent_sock = sv[0];
			/* take_fd owns sv[1]; GLib closes it after spawn — do not close here or spawn sees a bad FD. */
			launcher.take_fd (sv[1], RunSeccomp.SYNC_SOCK_CHILD_FD);
			launcher.set_child_setup (() => {
				this.child_seccomp_handshake ();
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
		 * Best-effort read of a C string from the traced process (process_vm_readv).
		 *
		 * @param ev kernel notification payload
		 * @param path_address user pointer to pathname
		 * @return path text or empty string
		 */
		string read_remote_cstring (Seccomp.Notif ev, uint64 path_address)
		{
			if (this.notify_fd < 0 || path_address == 0) {
				return "";
			}
			if (Seccomp.notify_id_valid (this.notify_fd, ev.id) != 0) {
				return "";
			}
			const int PATH_CAP = 4096;
			var local = new uint8[PATH_CAP];
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
				return "";
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
			if (this.bubble == null) {
				return;
			}
			if (ev.sc_data.nr == this.nr_openat) {
				var p = this.read_remote_cstring (ev, ev.sc_data.args[1]);
				if (p != "" && !this.bubble.can_write (p)) {
					this.file_writes.set (p, true);
				}
				return;
			}
			if (ev.sc_data.nr == this.nr_unlink) {
				var p = this.read_remote_cstring (ev, ev.sc_data.args[0]);
				if (p != "" && !this.bubble.can_write (p)) {
					this.file_writes.set (p, true);
				}
				return;
			}
			if (ev.sc_data.nr == this.nr_unlinkat) {
				int dirfd = (int) ev.sc_data.args[0];
				var p = this.read_remote_cstring (ev, ev.sc_data.args[1]);
				if (p == "") {
					return;
				}
				if (dirfd != AT_FDCWD && !GLib.Path.is_absolute (p)) {
					return;
				}
				if (!this.bubble.can_write (p)) {
					this.file_writes.set (p, true);
				}
				return;
			}
			if (ev.sc_data.nr == this.nr_rename) {
				var old_path = this.read_remote_cstring (ev, ev.sc_data.args[0]);
				var new_path = this.read_remote_cstring (ev, ev.sc_data.args[1]);
				if (old_path != "" && !this.bubble.can_write (old_path)) {
					this.file_writes.set (old_path, true);
				}
				if (new_path != "" && !this.bubble.can_write (new_path)) {
					this.file_writes.set (new_path, true);
				}
				return;
			}
			if (ev.sc_data.nr == this.nr_renameat2) {
				var old_path = this.read_remote_cstring (ev, ev.sc_data.args[1]);
				var new_path = this.read_remote_cstring (ev, ev.sc_data.args[3]);
				if (old_path != "" && !this.bubble.can_write (old_path)) {
					this.file_writes.set (old_path, true);
				}
				if (new_path != "" && !this.bubble.can_write (new_path)) {
					this.file_writes.set (new_path, true);
				}
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
			if (this.file_writes.size > 0) {
				var keys = this.file_writes.keys.to_array ();
				int lim = keys.length > 50 ? 50 : keys.length;
				var slice = keys[0:lim];
				this.fs = ("---\n" +
					"Sandbox: file operations were restricted because write permission was not requested for these paths (use allow_write with a PATH-style list of absolute directory roots):\n\n" +
					string.joinv ("\n", slice) + "\n"
					).chomp ();
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
