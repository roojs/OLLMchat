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
	 * Headless {@code ollmfilesd} entry point: open DB, migrate, RPC over socket or stdio.
	 */
	public class OllmfilesdApplication : GLib.Application, OLLMchat.ApplicationInterface
	{
		public OLLMchat.Settings.Config2 config { get; set; }
		public string data_dir { get; set; }

		public static bool opt_debug = false;
		public static bool opt_debug_critical = false;
		public static bool opt_interactive = false;
		public static string? opt_data_dir = null;
		public static string opt_rpc_script = "";

		private string pid_path;
		private string socket_path;

		public ProjectManager project_manager { get; private set; }
		public Daemon daemon { get; private set; }
		private OLLMrpc.Transport.Listen? listen;
		private static weak OllmfilesdApplication? instance;

		private const OptionEntry[] app_options = {
			{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "interactive", 'i', 0, OptionArg.NONE, ref opt_interactive, "Stdin/stdout JSON-RPC (no fork, no socket)", null },
			{ "rpc-script", 0, 0, OptionArg.FILENAME, ref opt_rpc_script, "NDJSON RPC script (implies --interactive)", "FILE" },
			{ "data-dir", 0, 0, OptionArg.STRING, ref opt_data_dir, "Data directory (DB, socket, pid)", "DIR" },
			{ null }
		};

		public OllmfilesdApplication()
		{
			var app_flags = GLib.ApplicationFlags.HANDLES_COMMAND_LINE;
			if (GLib.Environment.get_variable("OLLMFILES_IS_TEST") != null) {
				app_flags |= GLib.ApplicationFlags.NON_UNIQUE;
			}

			Object(
				application_id: "org.roojs.ollmfilesd",
				flags: app_flags
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
				this.release();
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
					instance.quit();
				}
				return false;
			});
		}

		protected override int command_line(ApplicationCommandLine command_line)
		{
			opt_debug = false;
			opt_debug_critical = false;
			opt_interactive = false;
			opt_data_dir = null;
			opt_rpc_script = "";

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

			OLLMchat.debug_on = opt_debug;
			OLLMchat.debug_critical_enabled = opt_debug_critical;

			if (opt_rpc_script != "") {
				opt_interactive = true;
			}

			if (opt_data_dir != null) {
				this.data_dir = opt_data_dir;
				this.pid_path = GLib.Path.build_filename(
					this.data_dir,
					"ollmfilesd.pid"
				);
				this.socket_path = GLib.Path.build_filename(
					this.data_dir,
					"ollmfilesd.sock"
				);
			}

			if (!opt_interactive) {
				if (!this.daemonize()) {
					command_line.printerr("error: could not daemonize\n");
					return 1;
				}
			}

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
					GLib.Path.build_filename(this.data_dir, "files.sqlite"),
					true
				)
			);

			if (this.project_manager.db != null) {
				var db_file = GLib.File.new_for_path(
					this.project_manager.db.filename
				);
				if (!db_file.query_exists()
					&& GLib.Environment.get_variable("OLLMFILES_IS_TEST") == null) {
					var migrator = new ProjectMigrate(this.project_manager);
					yield migrator.migrate_all();
				}

				yield this.project_manager.load_projects_from_db();
			}

			this.project_manager.vector_db_path =
				GLib.Path.build_filename (
					this.data_dir, "codedb.faiss.vectors");
			this.project_manager.background_scan =
				new OLLMfilesd.Vector.BackgroundScan (
					this,
					this.project_manager,
					this.config);
			yield this.project_manager.background_scan.open_vector_db ();

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

			if (opt_interactive) {
				this.listen = new Stdio(this, opt_rpc_script);
				this.listen.start();
				if (opt_rpc_script == "") {
					return;
				}
				while (GLib.MainContext.default().pending()) {
					GLib.MainContext.default().iteration(true);
				}
				this.quit();
				return;
			}

			this.listen = new OLLMrpc.Transport.SocketListen(this.socket_path);
			if (!this.listen.start()) {
				GLib.error("failed to start RPC listener");
			}
			this.write_pid();
			GLib.debug("ollmfilesd listening on %s", this.socket_path);
		}

		/**
		 * Classic double-fork daemonize. Parent exits; only the grandchild
		 * returns. Skipped for {@link opt_interactive}.
		 */
		private bool daemonize()
		{
			Posix.pid_t pid = Posix.fork();
			if (pid < 0) {
				return false;
			}
			if (pid > 0) {
				Posix._exit(0);
			}

			if (Posix.setsid() < 0) {
				return false;
			}

			pid = Posix.fork();
			if (pid < 0) {
				return false;
			}
			if (pid > 0) {
				Posix._exit(0);
			}

			Posix.chdir("/");
			Posix.umask(0);

			int null_fd = Posix.open("/dev/null", Posix.O_RDWR);
			if (null_fd < 0) {
				return false;
			}
			Posix.dup2(null_fd, Posix.STDIN_FILENO);
			Posix.dup2(null_fd, Posix.STDOUT_FILENO);
			Posix.dup2(null_fd, Posix.STDERR_FILENO);
			if (null_fd > Posix.STDERR_FILENO) {
				Posix.close(null_fd);
			}
			return true;
		}

		private void write_pid()
		{
			try {
				GLib.FileUtils.set_contents(
					this.pid_path,
					((int) Posix.getpid()).to_string() + "\n"
				);
			} catch (GLib.FileError e) {
				GLib.error("could not write pid file: %s", e.message);
			}
		}

		public void broadcast(OLLMrpc.Notification notification)
		{
			if (this.listen != null) {
				this.listen.broadcast(notification);
			}
		}

		public void cleanup()
		{
			this.project_manager.db.backup_real();
			if (this.listen != null) {
				this.listen.stop();
				this.listen = null;
			}
			if (!GLib.FileUtils.test(this.pid_path, GLib.FileTest.EXISTS)) {
				return;
			}
			try {
				GLib.FileUtils.unlink(this.pid_path);
			} catch (GLib.FileError e) {
				GLib.warning("could not remove pid file: %s", e.message);
			}
		}
	}

	int main(string[] args)
	{
		var app = new OllmfilesdApplication();
		return app.run(args);
	}
}
