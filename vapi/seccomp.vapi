/* Hand-maintained OO binding for libseccomp. Do not overwrite from vapigen;
 * see contrib/seccomp-gir/ for GIR regeneration reference.
 * Companion C for user-notify fd passing: seccomp-fd-pass.c + seccomp-fd-pass.h (link when using pass_unix_fd / receive_unix_fd). */

[CCode (lower_case_cprefix = "seccomp_", cheader_filename = "seccomp.h")]
namespace Seccomp {
	[CCode (cname = "scmp_datum_t")]
	[SimpleType]
	public struct Datum : uint64 {
	}
	[CCode (cname = "scmp_version", has_type_id = false)]
	public struct VersionInfo {
		public uint major;
		public uint minor;
		public uint micro;
	}
	[CCode (cname = "scmp_arg_cmp", has_type_id = false)]
	public struct ArgCmp {
		public uint arg;
		public void* op;
		public Datum datum_a;
		public Datum datum_b;
	}

	/** Opaque seccomp filter; wraps `scmp_filter_ctx`. */
	[Compact]
	[CCode (cname = "scmp_filter_ctx", free_function = "seccomp_release", cheader_filename = "seccomp.h")]
	public class Filter {
		[CCode (cname = "seccomp_init")]
		public Filter (uint32 def_action);

		[CCode (cname = "seccomp_arch_add")]
		public int arch_add (uint32 arch_token);
		[CCode (cname = "seccomp_arch_exist")]
		public int arch_exist (uint32 arch_token);
		[CCode (cname = "seccomp_arch_remove")]
		public int arch_remove (uint32 arch_token);

		[CCode (cname = "seccomp_attr_get")]
		public int attr_get (void* attr, uint32 value);
		[CCode (cname = "seccomp_attr_set")]
		public int attr_set (void* attr, uint32 value);

		[CCode (cname = "seccomp_export_bpf")]
		public int export_bpf (int fd);
		[CCode (cname = "seccomp_export_pfc")]
		public int export_pfc (int fd);

		[CCode (cname = "seccomp_load")]
		public int load ();

		[CCode (cname = "seccomp_notify_fd")]
		public int notify_fd ();

		[CCode (cname = "seccomp_reset")]
		public int reset (uint32 def_action);

		[CCode (cname = "seccomp_rule_add_array")]
		public int rule_add_array (uint32 action, int syscall, uint arg_cnt, void* arg_array);
		[CCode (cname = "seccomp_rule_add_exact_array")]
		public int rule_add_exact_array (uint32 action, int syscall, uint arg_cnt, void* arg_array);

		[CCode (cname = "seccomp_syscall_priority")]
		public int syscall_priority (int syscall, uint8 priority);

		[CCode (cname = "seccomp_merge")]
		public static int merge (Filter dst, Filter src);
	}

	[CCode (cname = "AUDIT_ARCH_AARCH64")]
	public const int AUDIT_ARCH_AARCH64;
	[CCode (cname = "AUDIT_ARCH_MIPS64")]
	public const int AUDIT_ARCH_MIPS64;
	[CCode (cname = "AUDIT_ARCH_MIPS64N32")]
	public const int AUDIT_ARCH_MIPS64N32;
	[CCode (cname = "AUDIT_ARCH_MIPSEL64N32")]
	public const int AUDIT_ARCH_MIPSEL64N32;
	[CCode (cname = "AUDIT_ARCH_PPC64LE")]
	public const int AUDIT_ARCH_PPC64LE;
	[CCode (cname = "AUDIT_ARCH_RISCV64")]
	public const int AUDIT_ARCH_RISCV64;
	[CCode (cname = "EM_AARCH64")]
	public const int EM_AARCH64;
	[CCode (cname = "EM_MIPS")]
	public const int EM_MIPS;
	[CCode (cname = "EM_RISCV")]
	public const int EM_RISCV;
	[CCode (cname = "SECCOMP_RET_USER_NOTIF")]
	public const int RET_USER_NOTIF;
	[CCode (cname = "SCMP_ACT_ALLOW")]
	public const int SCMP_ACT_ALLOW;
	[CCode (cname = "SCMP_ACT_KILL_PROCESS")]
	public const int SCMP_ACT_KILL_PROCESS;
	[CCode (cname = "SCMP_ACT_KILL_THREAD")]
	public const int SCMP_ACT_KILL_THREAD;
	[CCode (cname = "SCMP_ACT_LOG")]
	public const int SCMP_ACT_LOG;
	[CCode (cname = "SCMP_ACT_NOTIFY")]
	public const int SCMP_ACT_NOTIFY;
	[CCode (cname = "SCMP_ACT_TRAP")]
	public const int SCMP_ACT_TRAP;
	[CCode (cname = "SCMP_ARCH_NATIVE")]
	public const int SCMP_ARCH_NATIVE;
	[CCode (cname = "SCMP_ARCH_X32")]
	public const int SCMP_ARCH_X32;
	[CCode (cname = "SCMP_VER_MAJOR")]
	public const int SCMP_VER_MAJOR;
	[CCode (cname = "SCMP_VER_MICRO")]
	public const int SCMP_VER_MICRO;
	[CCode (cname = "SCMP_VER_MINOR")]
	public const int SCMP_VER_MINOR;

	public static uint api_get ();
	public static int api_set (uint level);

	public static uint32 arch_native ();
	public static uint32 arch_resolve_name (string arch_name);

	/** Kernel `struct seccomp_data` (`linux/seccomp.h`). */
	[CCode (cname = "struct seccomp_data", has_type_id = false, cheader_filename = "linux/seccomp.h")]
	public struct NotifData {
		public int32 nr;
		public uint32 arch;
		public uint64 instruction_pointer;
		public uint64 args[6];
	}

	/** Kernel `struct seccomp_notif`. */
	[CCode (cname = "struct seccomp_notif", has_type_id = false, cheader_filename = "linux/seccomp.h")]
	public struct Notif {
		public uint64 id;
		public uint32 pid;
		public uint32 flags;
		[CCode (cname = "data")]
		public NotifData sc_data;
	}

	/** Kernel `struct seccomp_notif_resp`. */
	[CCode (cname = "struct seccomp_notif_resp", has_type_id = false, cheader_filename = "linux/seccomp.h")]
	public struct NotifResp {
		public uint64 id;
		public int64 val;
		public int32 error;
		public uint32 flags;
	}

	/** `SECCOMP_USER_NOTIF_FLAG_CONTINUE` — pass syscall through after recording. */
	[CCode (cname = "SECCOMP_USER_NOTIF_FLAG_CONTINUE", cheader_filename = "linux/seccomp.h")]
	public const uint32 USER_NOTIF_FLAG_CONTINUE;

	/** Allocates `struct seccomp_notif` / `struct seccomp_notif_resp` buffers (libseccomp). */
	public static int notify_alloc (out unowned Notif* req, out unowned NotifResp* resp);
	public static void notify_free (Notif* req, NotifResp* resp);
	public static int notify_id_valid (int fd, uint64 id);
	public static int notify_receive (int fd, Notif* req);
	public static int notify_respond (int fd, NotifResp* resp);

	public static int syscall_resolve_name (string name);
	public static int syscall_resolve_name_arch (uint32 arch_token, string name);
	public static int syscall_resolve_name_rewrite (uint32 arch_token, string name);
	public static string syscall_resolve_num_arch (uint32 arch_token, int num);

	public static void* version ();

	/**
	 * Send one file descriptor over a connected Unix-domain `SOCK_STREAM` socket (`SCM_RIGHTS`).
	 * Typical use: child passes the user-notify listener fd to a parent supervisor. Safe in a
	 * child after `Posix.fork` and before `exec` (do not use Gio on that path). Returns 0 on success, -1 with `errno` on failure.
	 */
	[CCode (cname = "seccomp_fd_pass_send", cheader_filename = "seccomp-fd-pass.h")]
	public static int pass_unix_fd (int socket_fd, int fd_to_pass);

	/**
	 * Receive one file descriptor from the peer's next `SCM_RIGHTS` message. Returns the new fd, or -1 with `errno` on failure.
	 */
	[CCode (cname = "seccomp_fd_pass_recv", cheader_filename = "seccomp-fd-pass.h")]
	public static int receive_unix_fd (int socket_fd);
}

/** Linux syscalls/constants used with seccomp user-notify (no `seccomp_` prefix). */
[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "sys/prctl.h,linux/prctl.h,sys/uio.h")]
namespace SeccompLinux {
	[CCode (cname = "prctl", cheader_filename = "sys/prctl.h")]
	public int prctl (int option, ulong arg2 = 0, ulong arg3 = 0, ulong arg4 = 0, ulong arg5 = 0);

	[CCode (cname = "process_vm_readv", cheader_filename = "sys/uio.h")]
	public ssize_t process_vm_readv (int pid, void* local_iov, ulong liovcnt, void* remote_iov, ulong riovcnt, ulong flags = 0);

	[CCode (cname = "PR_SET_NO_NEW_PRIVS", cheader_filename = "linux/prctl.h")]
	public const int PR_SET_NO_NEW_PRIVS;
}
