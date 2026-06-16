/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Android-only Soup TLS trust store wiring (bundled CA PEM via GTlsFileDatabase).
 *
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

namespace OLLMapp
{
	[CCode (cname = "ollmapp_apply_bundled_tls_database_to_session",
	        cheader_filename = "android-gio-tls.h")]
	private extern void apply_bundled_tls_database_to_session (GLib.Object session);

	/**
	 * Applies the bundled CA trust store to a libsoup session on Android.
	 *
	 * @since 1.0
	 */
	public class AndroidConnectionTls : Object
	{
		public static void apply_to_session (Soup.Session session)
		{
			if (session == null) {
				return;
			}

			apply_bundled_tls_database_to_session (session);
		}
	}
}
