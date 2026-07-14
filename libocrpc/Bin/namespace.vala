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
	 * Binary wire serialization for RPC payloads.
	 *
	 * The OLLMrpc.Bin namespace encodes and decodes {@link Serializable} GObjects
	 * on a per-connection {@link Stream}. Type aliases are process-wide
	 * ({@link register}); property keys are JIT tokens on each Stream.
	 * {@link Json} converts between JSON trees and bin bytes for tests and
	 * HTTP tooling. Wire layout is documented in docs/bin-rpc-protocol.md.
	 *
	 * == Architecture Benefits ==
	 *
	 *  * GObject-native: properties map to wire fields without hand schemas
	 *  * Compact wire: short integers, JIT key tokens, typed object headers
	 *  * Dual use: daemon sockets and JSON bridges share one codec
	 *  * Extensible: override prop read/write for lists and custom shapes
	 *
	 * == Usage Examples ==
	 *
	 * === Register and round-trip ===
	 *
	 * {{{
	 * OLLMrpc.Bin.register("Pair", typeof(Pair));
	 *
	 * var mem = new GLib.MemoryOutputStream.resizable();
	 * var out_stream = new GLib.DataOutputStream(mem);
	 * var write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
	 * write_bin.write(new Pair() { name = "alpha", count = 42 });
	 * out_stream.close();
	 *
	 * var read_bin = new OLLMrpc.Bin.Stream(
	 *     new GLib.DataInputStream(
	 *         new GLib.MemoryInputStream.from_bytes(mem.steal_as_bytes())),
	 *     null);
	 * var parsed = read_bin.parse() as Pair;
	 * }}}
	 *
	 * === JSON bridge ===
	 *
	 * {{{
	 * var json = new OLLMrpc.Bin.Json();
	 * var node = json.from_gobject(pair);
	 * }}}
	 *
	 * == Best Practices ==
	 *
	 *  1. Register every alias before connect/listen (both peers)
	 *  2. One Stream per connection for the channel lifetime
	 *  3. Implement Serializable; override only non-scalar props
	 *  4. Prefer {@link Json.from_gobject} over hand-rolled memory pipes
	 */
	namespace Bin
	{
		/**
		 * {@link Json} encode/decode and {@link Stream} GObject decode options.
		 *
		 * Combine flags with bitwise OR (e.g. {@link AUTO} | {@link IGNORE_UNKNOWN}).
		 * Use the Flags attribute so combined values are valid.
		 *
		 * == Example ==
		 *
		 * {{{
		 * var json = new OLLMrpc.Bin.Json(
		 *     OLLMrpc.Bin.Mode.AUTO | OLLMrpc.Bin.Mode.IGNORE_UNKNOWN);
		 * var stream = new OLLMrpc.Bin.Stream(in_stream, out_stream) {
		 *     mode = OLLMrpc.Bin.Mode.AUTO
		 * };
		 * }}}
		 */
		[Flags]
		public enum Mode {
			/** Default: every object needs wire meta key ''*type''; nested objects need explicit aliases. */
			EXPLICIT = 0,
			/**
			 * Typed root encode without ''*type''; JSON member names
			 * are written as bin tags for Vala/GObject lookup (HTTP Hub):
			 * leading ''_'' maps to ''underscore_'', then ''_'' to ''-'';
			 * GObject-reserved wire names (e.g. ''type'') map to
			 * reserved_property_NAME properties on decode and
			 * reserved_property_NAME encodes as wire NAME.
			 */
			AUTO = 1,
			/** Log {@link GLib.critical} on unknown bin properties and continue decode. */
			IGNORE_UNKNOWN = 2,
			/**
			 * On decode: scalar string wire values whose GObject property is not
			 * {@link GLib.Type.STRING} fill name_str when that companion
			 * string property exists (Hub cardData variants).
			 */
			AUTO_STR = 4,
		}
	}
}
