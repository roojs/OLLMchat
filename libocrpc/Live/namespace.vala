/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * Opt-in live GObject handles for {@link OLLMrpc}.
 *
 * Unix builds compile {@link Remote}, {@link Subscribe}, {@link Buffer}, etc.
 * from separate ''Live/'' sources. Windows and Android compile
 * ''Live/namespace.windows.vala'' instead (meson, not ''#if'').
 *
 * {@link Buffer} — Unix: {@link Buffer}; Windows: shell in that file.
 */
namespace OLLMrpc.Live
{
	/** Boxed GTypes that already passed {@link boxed_ok}. */
	private static Gee.HashMap<GLib.Type, bool> boxed_valid;

	/**
	 * GI layout check for a registered boxed GType.
	 *
	 * First call walks fields; later calls return. Size 0 / disguised
	 * passes. Size greater than 0 with a field tag at or above UTF8
	 * is fatal.
	 *
	 * @param gtype boxed GType already in {@link Bin.gtype_to_alias}
	 */
	public static void boxed_ok(GLib.Type gtype)
	{
		if (boxed_valid == null) {
			boxed_valid = new Gee.HashMap<GLib.Type, bool>();
		}
		if (boxed_valid.has_key(gtype)) {
			return;
		}
		var gi = GI.Repository.get_default().find_by_gtype(gtype);
		if (gi == null) {
			GLib.error("boxed type '%s' has no GI info", gtype.name());
		}
		if (gi.get_type() == GI.InfoType.STRUCT || gi.get_type() == GI.InfoType.BOXED) {
			var si = (GI.StructInfo) gi;
			if (!si.is_gtype_struct() && si.get_size() > 0) {
				for (var fi = 0; fi < si.get_n_fields(); fi++) {
					if ((int) si.get_field(fi).get_type().get_tag() < (int) GI.TypeTag.UTF8) {
						continue;
					}
					GLib.error("boxed type '%s' is not wire-portable", gtype.name());
				}
			}
		}
		if (gi.get_type() == GI.InfoType.UNION) {
			var ui = (GI.UnionInfo) gi;
			if (ui.get_size() > 0) {
				for (var fi = 0; fi < ui.get_n_fields(); fi++) {
					if ((int) ui.get_field(fi).get_type().get_tag() < (int) GI.TypeTag.UTF8) {
						continue;
					}
					GLib.error("boxed type '%s' is not wire-portable", gtype.name());
				}
			}
		}
		boxed_valid.set(gtype, true);
	}
}
