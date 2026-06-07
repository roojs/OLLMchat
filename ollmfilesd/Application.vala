/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd
{
	/**
	 * Headless {@code ollmfilesd} entry point: open DB, migrate, listen, pid file.
	 */
	public class OllmfilesdApplication : GLib.Application, OLLMchat.ApplicationInterface
	{
		public OLLMchat.Settings.Config2 config { get; set; }
		public string data_dir { get; set; }

		public static bool opt_debug = false;
		public static bool opt_debug_critical = false;
		public static bool opt_foreground = false;
		public static bool opt_interactive = false;

		private string pid_path;
		private string socket_path;

		public ProjectManager project_manager { get; private set; }
		private Daemon daemon { get; set; }
		private OLLMrpc.Listen? listen;
		private GLib.IOChannel? stdin_channel;
		private uint stdin_watch_id = 0;
		private static weak OllmfilesdApplication? instance;

		private const OptionEntry[] app_options = {
			{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "foreground", 0, 0, OptionArg.NONE, ref opt_foreground, "Run in foreground (tests, gdb)", null },
			{ "interactive", 'i', 0, OptionArg.NONE, ref opt_interactive, "Read JSON-RPC lines from stdin (implies --foreground)", null },
			{ null }
		};

		public OllmfilesdApplication()
		{
			Object(
				application_id: "org.roojs.ollmfilesd",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
			);

			instance = this;

			GLib.Log.set_default_handler((dom, lvl, msg) => {
				OLLMchat.ApplicationInterface.debug_log("ollmfilesd", dom, lvl, msg);
			});

			this.data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(),
				"ollmchat"
			);
			this.pid_path = GLib.Path.build_filename(
				this.data_dir,
				"ollmfilesd.pid"
			);
			this.socket_path = GLib.Path.build_filename(
				this.data_dir,
				"ollmfilesd.sock"
			);

			this.config = this.load_config();

			Posix.signal(Posix.Signal.TERM, on_sigterm);
			Posix.signal(Posix.Signal.INT, on_sigterm);

			this.shutdown.connect(() => {
				this.cleanup();
			});
		}

		public override OLLMchat.Settings.Config2 load_config()
		{
			return base_load_config();
		}

		private static void on_sigterm(int signum)
		{
			if (instance == null) {
				return;
			}
			GLib.Idle.add(() => {
				if (instance != null) {
					instance.cleanup();
					instance.release();
					instance.quit();
				}
				return false;
			});
		}

		protected override int command_line(ApplicationCommandLine command_line)
		{
			opt_debug = false;
			opt_debug_critical = false;
			opt_foreground = false;
			opt_interactive = false;

			string[] args = command_line.get_arguments();
			var opt_context = new OptionContext(this.get_application_id());
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);

			try {
				unowned string[] unowned_args = args;
				opt_context.parse(ref unowned_args);
			} catch (OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr(
					"Run '%s --help' to see a full list of available command line options.\n",
					args[0]
				);
				return 1;
			}

			if (opt_interactive) {
				opt_foreground = true;
			}

			OLLMchat.debug_on = opt_debug;
			OLLMchat.debug_critical_enabled = opt_debug_critical;

			this.hold();
			this.initialize.begin((obj, res) => {
				try {
					this.initialize.end(res);
				} catch (GLib.Error e) {
					command_line.printerr("error: %s\n", e.message);
					this.release();
					this.quit();
				}
			});

			return 0;
		}

		private async void initialize() throws GLib.Error
		{
			this.ensure_data_dir();

			this.project_manager = new ProjectManager(
				new SQ.Database(
					GLib.Path.build_filename(this.data_dir, "files.sqlite")
				)
			);

			if (this.project_manager.db != null) {
				var db_file = GLib.File.new_for_path(
					this.project_manager.db.filename
				);
				if (!db_file.query_exists()) {
					var migrator = new ProjectMigrate(this.project_manager);
					yield migrator.migrate_all();
				}

				yield this.project_manager.load_projects_from_db();
			}

			this.daemon = new Daemon(this);
			OLLMrpc.Request.register(
				"Daemon", this.daemon,
				(new DaemonParams()).get_type()
			);
			OLLMrpc.Request.register(
				"ProjectManager", this.project_manager,
				(new ProjectParams()).get_type()
			);
			OLLMrpc.Request.register(
				"File", new File(this.project_manager),
				(new FileParams()).get_type()
			);

			this.listen = new OLLMrpc.Listen(this.socket_path);

			if (!this.listen.start()) {
				throw new GLib.IOError.FAILED(
					"failed to bind RPC socket at %s".printf(this.socket_path)
				);
			}

			this.write_pid();
			GLib.debug("ollmfilesd listening on %s", this.socket_path);

			if (opt_interactive) {
				GLib.stderr.printf(
					"ollmfilesd interactive on %s\n"
						+ "  one JSON-RPC request per line on stdin\n"
						+ "  help — this message\n"
						+ "  quit — exit\n",
					this.socket_path
				);
				this.stdin_channel = new GLib.IOChannel.unix_new(Posix.STDIN_FILENO);
				this.stdin_channel.set_encoding(null);
				this.stdin_channel.set_buffered(true);
				this.stdin_watch_id = this.stdin_channel.add_watch(
					GLib.IOCondition.IN | GLib.IOCondition.HUP,
					this.on_stdin
				);
			}
		}

		private bool on_stdin(
			GLib.IOChannel source,
			GLib.IOCondition condition
		)
		{
			if ((condition & GLib.IOCondition.HUP) != 0) {
				this.cleanup();
				this.release();
				this.quit();
				return false;
			}

			string? line = null;
			size_t length = 0;
			GLib.IOStatus status;
			try {
				status = source.read_line(out line, out length, null);
			} catch (GLib.Error e) {
				GLib.stderr.printf("stdin read error: %s\n", e.message);
				return true;
			}
			if (status == GLib.IOStatus.EOF) {
				this.cleanup();
				this.release();
				this.quit();
				return false;
			}
			if (status != GLib.IOStatus.NORMAL || line == null) {
				return true;
			}

			line = line.strip();
			if (line == "") {
				return true;
			}
			if (line == "help") {
				GLib.stderr.printf(
					"send one JSON-RPC line, e.g.\n"
						+ "  {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"Daemon.hello\","
						+ "\"params\":{\"protocol\":1,\"client\":\"stdio\"}}\n"
				);
				return true;
			}
			if (line == "quit" || line == "exit") {
				this.cleanup();
				this.release();
				this.quit();
				return false;
			}

			this.send_rpc.begin(line);
			return true;
		}

		private async void send_rpc(string line)
		{
			GLib.SocketConnection? conn = null;
			try {
				var client = new GLib.SocketClient();
				conn = yield client.connect_async(
					new GLib.UnixSocketAddress(this.socket_path),
					null
				);
				var output = new GLib.DataOutputStream(conn.get_output_stream());
				var input = new GLib.DataInputStream(conn.get_input_stream());
				input.set_newline_type(GLib.DataStreamNewlineType.LF);

				var payload = line;
				if (!payload.has_suffix("\n")) {
					payload += "\n";
				}
				output.put_string(payload);
				yield output.flush_async(GLib.Priority.DEFAULT, null);

				string? response = yield input.read_line_async(
					GLib.Priority.DEFAULT,
					null
				);
				if (response != null) {
					GLib.stdout.printf("%s\n", response);
				}
			} catch (GLib.Error e) {
				GLib.stderr.printf("rpc error: %s\n", e.message);
			} finally {
				if (conn != null) {
					try {
						conn.close();
					} catch (GLib.Error e) {
					}
				}
			}
		}

		private void write_pid()
		{
			try {
				GLib.FileUtils.set_contents(
					this.pid_path,
					((int) Posix.getpid()).to_string() + "\n"
				);
			} catch (GLib.FileError e) {
				GLib.warning("could not write pid file: %s", e.message);
			}
		}

		public void cleanup()
		{
			if (this.stdin_watch_id != 0) {
				GLib.Source.remove(this.stdin_watch_id);
				this.stdin_watch_id = 0;
			}
			this.stdin_channel = null;
			if (this.listen != null) {
				this.listen.stop();
				this.listen = null;
			}
			if (GLib.FileUtils.test(this.pid_path, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.unlink(this.pid_path);
				} catch (GLib.FileError e) {
					GLib.warning("could not remove pid file: %s", e.message);
				}
			}
		}
	}

	int main(string[] args)
	{
		var app = new OllmfilesdApplication();
		return app.run(args);
	}
}
