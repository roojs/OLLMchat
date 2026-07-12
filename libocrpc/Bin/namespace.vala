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
	 * Binary wire serialization for RPC payloads (JIT keys/types, short/long encodings).
	 *
	 * See docs/bin-rpc-protocol.md for the wire specification.
	 */
	namespace Bin
	{
 		/**
		 * {@link Json} encode/decode and {@link Stream} GObject decode options.
		 *
		 * Combine flags with bitwise OR (e.g. {@link AUTO} | {@link IGNORE_UNKNOWN}).
		 * Use the Flags attribute so combined values are valid.
		 */
		[Flags]
		public enum Mode {
			/** Default: every object needs {{{*type}}}; nested objects need explicit aliases. */
			EXPLICIT = 0,
			/**
			 * Typed root encode without {{{*type}}}; JSON member names
			 * are written as bin tags for Vala/GObject lookup (HTTP Hub):
			 * leading {{{_}}} → {{{underscore_}}}, then {{{_}}} → {{{-}}};
			 * GObject-reserved wire names (e.g. {{{type}}}) map to
			 * {{{reserved_property_<name>}}} properties on decode and
			 * {{{reserved_property_<name>}}} encodes as wire {{{<name>}}}.
			 */
			AUTO = 1,
			/** Log {@link GLib.critical} on unknown bin properties and continue decode. */
			IGNORE_UNKNOWN = 2,
			/**
			 * On decode: scalar string wire values whose GObject property is not
			 * {@link GLib.Type.STRING} fill {{{name_str}}} when that companion
			 * string property exists (Hub cardData variants).
			 */
			AUTO_STR = 4,
		}
	}
}
