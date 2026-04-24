/*
 * Small helper for libseccomp user-notify: owns one notify_alloc buffer pair.
 * Built only as part of oc-test-seccomp-spike (not a shared library).
 */

/**
 * Owns one libseccomp user-notify buffer pair (`notify_alloc` / `notify_free`).
 * Call sites use `Seccomp.Notif` by value via `snapshot_request ()`.
 */
class UserNotifExchange : GLib.Object {
	public enum WaitResult {
		READY,
		INTERRUPTED,
		CLOSED
	}

	Seccomp.Notif* _req;
	Seccomp.NotifResp* _reply;

	private UserNotifExchange () {
	}

	public static UserNotifExchange? try_begin () {
		Seccomp.Notif* r;
		Seccomp.NotifResp* s;
		if (Seccomp.notify_alloc (out r, out s) != 0) {
			return null;
		}
		var o = new UserNotifExchange ();
		o._req = r;
		o._reply = s;
		return o;
	}

	public WaitResult wait_for_kernel (int notify_fd) {
		if (Seccomp.notify_receive (notify_fd, _req) < 0) {
			Seccomp.notify_free (_req, _reply);
			_req = null;
			_reply = null;
			if (Posix.errno == Posix.EINTR) {
				return WaitResult.INTERRUPTED;
			}
			return WaitResult.CLOSED;
		}
		return WaitResult.READY;
	}

	public Seccomp.Notif snapshot_request () {
		return *_req;
	}

	public void prepare_continue_reply (Seccomp.Notif observed) {
		_reply.id = observed.id;
		_reply.val = 0;
		_reply.error = 0;
		_reply.flags = Seccomp.USER_NOTIF_FLAG_CONTINUE;
	}

	public bool submit_reply (int notify_fd) {
		bool ok = Seccomp.notify_respond (notify_fd, _reply) >= 0;
		Seccomp.notify_free (_req, _reply);
		_req = null;
		_reply = null;
		return ok;
	}

	~UserNotifExchange () {
		if (_req != null) {
			Seccomp.notify_free (_req, _reply);
			_req = null;
			_reply = null;
		}
	}
}
