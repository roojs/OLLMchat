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
	 * Compiles {@link OLLMtools.WebFetch} and {@link OLLMtools.SessionFetch} into
	 * the Android executable only; other liboctools tools are not linked on device.
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
			OLLMchat.Tool.BaseTool.register_config(typeof(OLLMtools.WebFetch.Tool));
			OLLMchat.Tool.BaseTool.register_config(typeof(OLLMtools.SessionFetch.Tool));
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
		}

		/**
		 * Register web_fetch and session_fetch on the history manager.
		 *
		 * @param manager History manager for the active chat session
		 */
		public static void fill_tools(OLLMchat.History.Manager manager)
		{
			manager.register_tool(new OLLMtools.WebFetch.Tool(null));
			manager.register_tool(new OLLMtools.SessionFetch.Tool());
		}
	}
}
