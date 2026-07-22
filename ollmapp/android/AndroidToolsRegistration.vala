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
	 * Registers the Android POC tool subset on {@link OLLMchat.History.Manager}.
	 *
	 * **Temporary:** duplicates {@link OLLMtools.Registry} because the Android APK
	 * does not link full {@code liboctools} yet. Remove when {@code libocfiles} uses
	 * RPC and Android can share {@link OLLMtools.Registry} with a name-list subset
	 * (build all tools, register only what the platform needs).
	 *
	 * Compiles {@link OLLMtools.WebFetch}, {@link OLLMtools.SessionFetch},
	 * {@link OLLMtools.GoogleSearch}, and {@link OLLMwebkit.Tool} into the
	 * Android executable; other liboctools tools are not linked on device.
	 *
	 * @since 1.0
	 */
	public class AndroidToolsRegistration : GLib.Object
	{
		/**
		 * Register tool config types before config load.
		 */
		public static void init_config()
		{
			typeof(OLLMtools.WebFetch.Tool).ensure();
			typeof(OLLMtools.SessionFetch.Tool).ensure();
			typeof(OLLMtools.GoogleSearch.Tool).ensure();
			typeof(OLLMwebkit.Tool).ensure();
			OLLMchat.Tool.BaseTool.register_config(typeof(OLLMtools.WebFetch.Tool));
			OLLMchat.Tool.BaseTool.register_config(typeof(OLLMtools.SessionFetch.Tool));
			OLLMchat.Tool.BaseTool.register_config(typeof(OLLMtools.GoogleSearch.Tool));
			OLLMchat.Tool.BaseTool.register_config(typeof(OLLMwebkit.Tool));
		}

		/**
		 * Ensure config contains entries for POC tools when missing.
		 *
		 * @param config Loaded application configuration
		 */
		public static void setup_config_defaults(OLLMchat.Settings.Config2 config)
		{
			(new OLLMtools.WebFetch.Tool(null)).setup_tool_config_default(config);
			(new OLLMtools.SessionFetch.Tool()).setup_tool_config_default(config);
			(new OLLMtools.GoogleSearch.Tool(null)).setup_tool_config_default(config);
			(new OLLMwebkit.Tool()).setup_tool_config_default(config);
		}

		/**
		 * Register web_fetch, session_fetch, google_search, and browser on the
		 * history manager.
		 *
		 * Also registers {@code web_search} as an alias for {@code google_search}
		 * (same as desktop {@code resources/wrapped-tools/WebSearch.tool}).
		 *
		 * @param manager History manager for the active chat session
		 */
		public static void fill_tools(OLLMchat.History.Manager manager)
		{
			var web_fetch = new OLLMtools.WebFetch.Tool(null);
			AndroidConnectionTls.apply_to_session(web_fetch.soup);
			manager.register_tool(web_fetch);

			manager.register_tool(new OLLMtools.SessionFetch.Tool());

			var google_search = new OLLMtools.GoogleSearch.Tool(null);
			AndroidConnectionTls.apply_to_session(google_search.soup);
			manager.register_tool(google_search);
			manager.tools.set("web_search", google_search);

			var browser_tool = new OLLMwebkit.Tool();
			manager.register_tool(browser_tool);
			manager.notification_reply.connect((notif) => {
				if (!notif.method.has_prefix("event.browser.download.")) {
					return;
				}
				browser_tool.stack.primary.notification_reply(notif);
			});
		}
	}
}
