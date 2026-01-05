/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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

namespace OLLMchat 
{

	/**
	 * Main application class implementing OLLMchat.ApplicationInterface interface.
	 */
	public class OllmchatApplication : Adw.Application, OLLMchat.ApplicationInterface
	{
		public OLLMchat.Settings.Config2 config { get; set; }
		public string data_dir { get; set; }
		
		public static bool opt_debug = false;
		public static bool opt_debug_critical = false;
		public static bool opt_disable_indexer = false;
		
		private const OptionEntry[] app_options = {
			{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "disable-indexer", 0, 0, OptionArg.NONE, ref opt_disable_indexer, "Disable background semantic search indexing", null },
			{ null }
		};
		
		public OllmchatApplication()
		{
			Object(
				application_id: "org.roojs.ollmchat",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
			);
			
			// Set up debug logging
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				OLLMchat.ApplicationInterface.debug_log("ollmchat", dom, lvl, msg);
			});
			
			// Set up data_dir
			this.data_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
			);
			
			// Register tool config types before loading config (Phase 1: config type registration)
			// Use unified tool config registration to discover and register all tool config types
			// Ensure all tool classes are registered in GType system before discovery.
			// We can't think of any other way to do this - GType registration is lazy
			// and classes won't be in the registry until they're explicitly referenced.
			// This is the only place with all dependencies available.
			// Note: OLLMchat.Tools.* classes exist but aren't compiled - use OLLMtools.* instead
			typeof(OLLMtools.ReadFile).ensure();
			typeof(OLLMtools.RunCommand).ensure();
			typeof(OLLMtools.WebFetchTool).ensure();
			typeof(OLLMtools.EditMode).ensure();
			typeof(OLLMvector.Tool.CodebaseSearchTool).ensure();
			typeof(OLLMtools.GoogleSearchTool).ensure();
			Tool.BaseTool.register_config();
			
			// Load config after registrations
			this.config = this.load_config();
			
			// Connect activate signal
			this.activate.connect(() => {
				var window = new OllmchatWindow(this);
				this.add_window(window);
				window.present();
			});
		}
		
		public override OLLMchat.Settings.Config2 load_config()
		{
			// Call base implementation
			return base_load_config();
		}
		
		protected override int command_line(ApplicationCommandLine command_line)
		{
			// Reset static option variables at start of each command line invocation
			opt_debug = false;
			opt_debug_critical = false;
			opt_disable_indexer = false;
			
			string[] args = command_line.get_arguments();
			var opt_context = new OptionContext(this.get_application_id());
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);
			
			try {
				unowned string[] unowned_args = args;
				opt_context.parse(ref unowned_args);
			} catch (OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr("Run '%s --help' to see a full list of available command line options.\n", args[0]);
				return 1;
			}
			
			// Set debug flags
			OLLMchat.debug_on = opt_debug;
			OLLMchat.debug_critical_enabled = opt_debug_critical;
			
			// Activate the application (this will call activate signal)
			// Use hold/release to keep app alive during async operations
			this.hold();
			this.activate();
			this.release();
			
			return 0;
		}
	}

	int main(string[] args)
	{
		var app = new OllmchatApplication();
		return app.run(args);
	}
}
