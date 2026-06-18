/*
 * Windows fallback for the Bubble sandbox API.
 *
 * The real implementation is Linux-specific: it uses bubblewrap, seccomp,
 * Unix-domain fd passing, and gio-unix stream file descriptors. On Windows,
 * callers already fall back to GLib.Subprocess when can_wrap() is false.
 */

namespace OLLMfiles.Sandbox
{
	public class Bubble
	{
		public Overlay overlay;
		public bool allow_network { get; private set; }
		public string bwrap_exe { get; private set; default = ""; }

		public static bool can_wrap()
		{
			return false;
		}

		public Bubble(OLLMfiles.Folder? project, bool allow_network, string[] write_array) throws Error
		{
			this.allow_network = allow_network;
			this.overlay = new Overlay(project);
		}

		public async string exec(string command, string working_dir = "") throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("Bubble sandboxing is not available on Windows");
		}

		public string[] build_bubble_args(string command, string working_dir = "") throws Error
		{
			throw new GLib.IOError.NOT_SUPPORTED("Bubble sandboxing is not available on Windows");
		}

		public bool can_write(string raw_path)
		{
			return false;
		}
	}

	public class RunSeccomp : GLib.Object
	{
		public string network { get; private set; default = ""; }
		public string fs { get; private set; default = ""; }
		public string skipped { get; private set; default = "seccomp is not available on Windows"; }

		public RunSeccomp(Bubble sandbox_bubble)
		{
		}

		public void wire_launcher(GLib.SubprocessLauncher launcher)
		{
		}

		public void finish_handshake()
		{
		}

		public void detach_sources()
		{
		}

		public void finish_evidence_formatting()
		{
		}
	}
}
