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

namespace OLLMapp 
{
	/**
	 * About button widget that shows an Adw.AboutWindow when clicked.
	 * Self-contained component that handles its own dialog.
	 */
	public class About : Gtk.Button
	{
		private Adw.AboutWindow? about_window = null;
		
		/**
		 * Creates a new About button.
		 */
		public About()
		{
			this.icon_name = "help-about-symbolic";
			this.tooltip_text = "About";
			
			this.clicked.connect(() => {
				this.show_about_dialog();
			});
		}
		
		/**
		 * Shows the about dialog.
		 */
		private void show_about_dialog()
		{
			// Create dialog if it doesn't exist
			if (this.about_window == null) {
				this.about_window = new Adw.AboutWindow() {
					application_name = "OLLMchat",
					application_icon = "org.roojs.ollmchat",
					version = OLLMapp.APP_VERSION,
					developer_name = "Alan Knowles",
					website = "https://github.com/roojs/OLLMchat",
					issue_url = "https://github.com/roojs/OLLMchat/issues",
					license_type = Gtk.License.LGPL_3_0,
					copyright = "Copyright © 2026 Alan Knowles",
					default_width = 600,  // Set width ~30% wider than default
					comments = """<b>OLLMchat</b> is a work-in-progress AI application for 
interacting with LLMs (Large Language Models) such as Ollama and OpenAI, 
featuring a full-featured chat interface with code assistant capabilities 
including semantic codebase search.

<b>Key Features:</b>
• Full-featured chat interface for interacting with LLMs (Ollama/OpenAI)
• Code assistant agent with semantic codebase search capabilities
• Chat history management with session browser
• Tool integration: ReadFile, EditMode, RunCommand, WebFetch, and 
  CodebaseSearch
• Project management and file tracking
• Permission system for secure tool access
• Support for multiple agent types (Just Ask, Code Assistant)
• Settings dialog with model search and download from Ollama

The application provides a comprehensive solution for local LLM work, 
combining powerful AI capabilities with a modern GTK4 interface."""
				};
				
				// Set transient for the active window
				var active_window = this.get_root() as Gtk.Window;
				if (active_window != null) {
					this.about_window.set_transient_for(active_window);
				}
			}
			
			this.about_window.present();
		}
	}
}
