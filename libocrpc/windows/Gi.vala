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

namespace OLLMrpc
{
	/**
	 * Compile-only {@link Gi} shell when typelib invoke is not built.
	 *
	 * {@link register} is a no-op. {@link dispatch} always returns false
	 * so unlisted methods do not fall through to a signal path.
	 */
	public class Gi : GLib.Object
	{
		public static Gee.HashMap<string, GLib.Type> types;

		public Request request { get; construct; }

		public Gi(Request request)
		{
			GLib.Object(request: request);
		}

		public static void register(string ns, string version) throws GLib.Error
		{
		}

		/**
		 * Typelib vfunc offsets are not available without girepository.
		 */
		public static int vfunc_offset(
			string ns,
			string class_name,
			string vfunc_name
		)
		{
			GLib.error("Gi.vfunc_offset: not available on this platform");
		}

		/**
		 * Typelib vfunc slots are not available without girepository.
		 */
		public static void* vfunc_slot(
			GLib.Type type,
			string ns,
			string class_name,
			string vfunc_name
		)
		{
			GLib.error("Gi.vfunc_slot: not available on this platform");
		}

		/**
		 * Typelib vfunc names are not available without girepository.
		 */
		public static string[] vfunc_names(string ns, string class_name)
		{
			GLib.error("Gi.vfunc_names: not available on this platform");
		}

		public bool dispatch()
		{
			return false;
		}
	}
}
