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

namespace OLLMchat.Settings
{
	/**
	 * Which codebase-search setting a {@link SearchFault} refers to.
	 *
	 * NONE is a tool-level fault. EMBED and ANALYSIS are the
	 * Embedding Model and Analysis Model rows.
	 */
	public enum SearchSlot {
		NONE,
		EMBED,
		ANALYSIS
	}

	/**
	 * Why a codebase-search model check failed.
	 *
	 * Stored on {@link ModelUsage.fault} and sent with Banner.show.
	 * {@link text} is the banner sentence. The model name, connection,
	 * and raw error stay data on the usage and the config.
	 */
	public enum SearchFault {
		NONE,
		MISSING,
		UNREADABLE,
		DISABLED,
		EMPTY,
		NO_CONNECTION,
		NO_MODEL,
		UNKNOWN_CONNECTION,
		LIST_FAILED,
		NOT_LISTED,
		CALL_FAILED;

		/**
		 * Banner sentence for this fault.
		 *
		 * Names the Settings row, the configured model, and the
		 * connection. Called when a banner is shown, not when the
		 * failure is detected.
		 *
		 * @param slot Embedding Model, Analysis Model, or neither
		 * @param detail Raw error from a failed call, or empty
		 * @param config Application config, for the row and connection
		 * @return Text for the banner
		 */
		public string text(SearchSlot slot, string detail, Config2 config)
		{
			var row = "model";
			var prop = "";
			var model = "";
			var where = "";
			var tool = config.tools.has_key("codebase_search")
				? config.tools.get("codebase_search")
				: null;
			switch (slot) {
				case SearchSlot.EMBED:
					row = "Embedding Model";
					prop = "embed";
					break;

				case SearchSlot.ANALYSIS:
					row = "Analysis Model";
					prop = "analysis";
					break;

				default:
					break;
			}
			if (tool != null && prop != "") {
				var pspec = tool.get_class().find_property(prop);
				if (pspec != null) {
					row = pspec.get_nick();
					var held = Value(pspec.value_type);
					((GLib.Object) tool).get_property(prop, ref held);
					var usage = held.get_object() as ModelUsage;
					if (usage != null) {
						model = usage.model;
						where = usage.connection;
						var named = config.connections.get(usage.connection);
						if (named != null && named.name != "") {
							where = named.name + " (" + usage.connection + ")";
						}
					}
				}
			}
			switch (this) {
				case SearchFault.MISSING:
					return "Semantic Codebase Search Tool is not in Settings → Tools.";
				case SearchFault.UNREADABLE:
					return "Semantic Codebase Search Tool settings could not be read. Open Settings → Tools.";
				case SearchFault.DISABLED:
					{
						var enable = "Enable";
						if (tool != null) {
							var enabled_prop = tool.get_class().find_property("enabled");
							if (enabled_prop != null) {
								enable = enabled_prop.get_nick();
							}
						}
						return "Semantic Codebase Search Tool is turned off. Turn on " +
							enable + " under Settings → Tools.";
					}
				case SearchFault.EMPTY:
					return "Semantic Codebase Search Tool → " + row +
						": no connection and no model are set. Change " + row +
						" under Settings → Tools.";
				case SearchFault.NO_CONNECTION:
					return "Semantic Codebase Search Tool → " + row +
						": no connection is set (model " + model + "). Change " + row +
						" under Settings → Tools.";
				case SearchFault.NO_MODEL:
					return "Semantic Codebase Search Tool → " + row +
						": no model is selected (connection " + where + "). Change " +
						row + " under Settings → Tools.";
				case SearchFault.UNKNOWN_CONNECTION:
					return "Semantic Codebase Search Tool → " + row +
						": connection " + where +
						" is not in Settings → Connections (model " + model +
						"). Change " + row + " under Settings → Tools.";
				case SearchFault.LIST_FAILED:
					return "Semantic Codebase Search Tool → " + row +
						": could not list models on " + where + ": " + detail +
						". Change " + row + " under Settings → Tools.";
				case SearchFault.NOT_LISTED:
					return "Semantic Codebase Search Tool → " + row + ": " + model +
						" is not listed on " + where + ". Change " + row +
						" under Settings → Tools.";
				case SearchFault.CALL_FAILED:
					return "Semantic Codebase Search Tool → " + row + ": " + model +
						" on " + where + " failed: " + detail + ". Change " + row +
						" under Settings → Tools.";
				default:
					return "Semantic Codebase Search Tool could not start. Open Settings → Tools.";
			}
		}
	}
}
