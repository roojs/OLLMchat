/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Android-only helpers to attach bundled TLS trust to OLLMchat connections.
 *
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

namespace OLLMapp
{
	/**
	 * Applies bundled CA trust to libollmchat connection objects on Android.
	 *
	 * @since 1.0
	 */
	public class AndroidConnectionConfigTls : Object
	{
		public static void apply_to_connection (
			OLLMchat.Settings.Connection connection)
		{
			if (connection == null || connection.soup == null) {
				return;
			}

			AndroidConnectionTls.apply_to_session (connection.soup);
		}

		public static void apply_to_config (OLLMchat.Settings.Config2 config)
		{
			if (config == null) {
				return;
			}

			foreach (var entry in config.connections.entries) {
				apply_to_connection (entry.value);
			}
		}
	}
}
