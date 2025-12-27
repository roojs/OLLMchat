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
		
		public OllmchatApplication()
		{
			Object(
				application_id: "org.roojs.ollmchat",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);
			
			// Set up debug logging
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				OLLMchat.ApplicationInterface.debug_log("ollmchat", dom, lvl, msg);
			});
			
			// Set up data_dir
			this.data_dir = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), ".local", "share", "ollmchat"
			);
			
			// Register ocvector types before loading config (static registration)
			OLLMvector.Database.register_config();
			OLLMvector.Indexing.Analysis.register_config();
			
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
	}

	int main(string[] args)
	{
		var app = new OllmchatApplication();
		return app.run(args);
	}
}
