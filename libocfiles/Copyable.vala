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

namespace OLLMfiles
{
	/**
	 * GObject types that copy writable properties from another instance.
	 *
	 * GLib has no built-in assign/overlay — only per-property get/set and
	 * {@link GLib.ObjectClass.list_properties}. Use {@link copy_from} to merge
	 * a deserialized RPC row (or scan snapshot) onto an existing client object
	 * without replacing it (keeps buffer/UI references).
	 *
	 * Pass property names in {{{except}}} to skip (e.g. {{{manager}}}, {{{buffer}}}).
	 *
	 * **Not in Meson** — experiment / V2 cutover only until wired.
	 */
	public interface Copyable : Object
	{
		/**
		 * Copy properties from {@link source} onto this object.
		 *
		 * @param source Object to copy from (typically the same {@link GLib.Type})
		 * @param except Property names to skip (null = copy all writable fields)
		 */
		public virtual void copy_from(GLib.Object source, string[]? except = null)
		{
			var target = (GLib.Object) this;
			unowned var target_class = target.get_class();

			foreach (unowned ParamSpec pspec in source.get_class().list_properties()) {
				if (except != null && GLib.strv_contains(except, pspec.name)) {
					continue;
				}
				if ((pspec.flags & GLib.ParamFlags.WRITABLE) == 0) {
					continue;
				}
				if ((pspec.flags & GLib.ParamFlags.CONSTRUCT_ONLY) != 0) {
					continue;
				}

				var target_pspec = target_class.find_property(pspec.name);
				if (target_pspec == null) {
					continue;
				}
				if ((target_pspec.flags & GLib.ParamFlags.WRITABLE) == 0) {
					continue;
				}
				if (target_pspec.value_type != pspec.value_type) {
					continue;
				}

				Value val = Value(pspec.value_type);
				source.get_property(pspec.name, ref val);
				target.set_property(pspec.name, val);
			}
		}
	}
}
