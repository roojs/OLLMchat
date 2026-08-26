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
	 * Call listed RPC instance methods via libffi.
	 *
	 * {@link Request.add_class} records the method table.
	 * {@link Request.dispatch} constructs {@link Ffi} with the inbound
	 * {@link Request} and calls {@link dispatch}. That method looks up
	 * the C symbol and calls it. Unlisted prefixes return false so
	 * {@link Request.dispatch} can try {@link Gi}.
	 * Compiled on every platform (not ''gi_src'').
	 *
	 * {@link pack} writes one {@link Libffi.Arg} from a D-Bus letter
	 * and a {@link GLib.Value}. ''S'' is one wire ''string[]'' and two
	 * C args (pointer + Vala hidden length). {@link Gi} will extend
	 * {@link Ffi} and use {@link pack} for typelib scalars in a later cut.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Request.add_class(
	 *     "RPC-Daemon", typeof(Daemon), "hello", "is", null
	 * );
	 * var ffi = new OLLMrpc.Ffi(req);
	 * ffi.dispatch();
	 * }}}
	 */
	public class Ffi : GLib.Object
	{
		/**
		 * Inbound call this instance applies. Owner of method / args /
		 * connection — not copied onto {@link Ffi}.
		 */
		public Request request { get; construct; }

		public Ffi(Request request)
		{
			GLib.Object(request: request);
		}

		/**
		 * Fill one libffi slot from a D-Bus letter and a
		 * {@link GLib.Value}.
		 *
		 * Same letters as ''OLLMrpc.args''. {@link Gi} will extend
		 * {@link Ffi} and use this for scalars later; this cut does not
		 * rewrite {@link Gi}.
		 *
		 * @param tag D-Bus letter or ''as'' / ''ay''
		 * @param val boxed argument
		 * @param slot union written for libffi
		 * @param atype matching {@link Libffi.Type} const
		 */
		internal void pack(
			string tag,
			GLib.Value val,
			ref Libffi.Arg slot,
			out Libffi.Type atype
		) {
			switch (tag) {
				case "s":
				case "g":
					slot.set_pointer((void*) val.get_string());
					atype = Libffi.POINTER;
					break;

				case "b":
					slot.set_int32(val.get_boolean() ? 1 : 0);
					atype = Libffi.SINT32;
					break;

				case "y":
					slot.set_uint8(val.get_uchar());
					atype = Libffi.UINT8;
					break;

				case "n":
					slot.set_int16((int16) val.get_int());
					atype = Libffi.SINT16;
					break;

				case "q":
					slot.set_uint16((uint16) val.get_uint());
					atype = Libffi.UINT16;
					break;

				case "u":
					slot.set_uint32(val.get_uint());
					atype = Libffi.UINT32;
					break;

				case "x":
					slot.set_int64(val.get_int64());
					atype = Libffi.SINT64;
					break;

				case "t":
					slot.set_uint64(val.get_uint64());
					atype = Libffi.UINT64;
					break;

				case "f":
					slot.set_float(val.get_float());
					atype = Libffi.FLOAT;
					break;

				case "d":
					slot.set_double(val.get_double());
					atype = Libffi.DOUBLE;
					break;

				case "o":
					slot.set_pointer((void*) val.get_object());
					atype = Libffi.POINTER;
					break;

				case "as":
				case "ay":
					slot.set_pointer(val.get_boxed());
					atype = Libffi.POINTER;
					break;

				case "v":
					slot.set_pointer(val.peek_pointer());
					atype = Libffi.POINTER;
					break;

				default:
					slot.set_int32(val.get_int());
					atype = Libffi.SINT32;
					break;
			}
		}

		/**
		 * FFI-call a listed instance method.
		 *
		 * Empty signature is (self, Request) only. The method may
		 * still read {@link Request.args}. A non-empty signature must
		 * match the inbound args size.
		 *
		 * @return true when this method is listed
		 */
		public bool dispatch()
		{
			if (Request.methods == null) {
				return false;
			}
			var dot = this.request.method.index_of_char('.');
			var object_name = this.request.method[0:dot];
			var method_name = this.request.method.substring(dot + 1);
			if (!Request.methods.has_key(object_name)
				|| !Request.methods.get(object_name).has_key(method_name)) {
				return false;
			}
			var signature = Request.methods.get(object_name).get(method_name);
			var n_wire = 0;
			var n_slots = 0;
			var offset = 0;
			while (offset < signature.length) {
				var rest = signature.substring(offset);
				if (rest.has_prefix("f")) {
					offset += 1;
					n_wire += 1;
					n_slots += 1;
					continue;
				}
				if (rest.has_prefix("S")) {
					offset += 1;
					n_wire += 1;
					n_slots += 2;
					continue;
				}
				var rest_ptr = (char*) rest;
				var next = (char*) null;
				if (!GLib.VariantType.string_scan(rest, null, out next)
					|| next == rest_ptr) {
					GLib.error("invalid D-Bus type signature %s", signature);
				}
				offset += (int) ((uint8*) next - (uint8*) rest_ptr);
				n_wire += 1;
				n_slots += 1;
			}
			if (signature != "" && n_wire != this.request.args.size) {
				GLib.critical("RPC dispatch: %s args size %d want %d",
					this.request.method, this.request.args.size, n_wire);
				return true;
			}
			if (Request.handlers == null
				|| !Request.handlers.has_key(object_name)) {
				GLib.critical("RPC dispatch: no handler instance for %s",
					this.request.method);
				return true;
			}
			var self = Request.handlers.get(object_name);
			if (this.request.lease_id == 0) {
				var id = (int) this.request.connection.export(self);
				self = this.request.connection.leases.get(id);
			}
			if (this.request.lease_id != 0) {
				var id = (int) this.request.lease_id;
				if (!this.request.connection.leases.has_key(id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				if (Request.live == null || !Request.live.has_key(object_name)) {
					self = this.request.connection.leases.get(id);
				}
			}
			var camel = new GLib.Regex("(?<=[a-z])([A-Z])");
			var symbol = camel.replace(
				Request.types.get(object_name).name(), -1, 0, "_\\1"
			).down() + "_" + method_name.replace(".", "_");
			var mod = GLib.Module.open(null, GLib.ModuleFlags.LAZY);
			if (mod == null) {
				GLib.critical("RPC dispatch: Module.open failed for %s",
					this.request.method);
				return true;
			}
			var fn = (void*) null;
			if (!mod.symbol(symbol, out fn)) {
				GLib.critical("RPC dispatch: no symbol %s for %s",
					symbol, this.request.method);
				return true;
			}
			var nargs = 2 + n_slots;
			var atypes = new Libffi.Type[nargs];
			var slots = new Libffi.Arg[nargs];
			slots[0].set_pointer((void*) self);
			slots[1].set_pointer((void*) this.request);
			atypes[0] = Libffi.POINTER;
			atypes[1] = Libffi.POINTER;
			offset = 0;
			var ai = 0;
			var si = 0;
			while (offset < signature.length) {
				var rest = signature.substring(offset);
				if (rest.has_prefix("S")) {
					this.pack("as", this.request.args.get(ai), ref slots[2 + si], out atypes[2 + si]);
					slots[2 + si + 1].set_int32(((string[]) this.request.args.get(ai).get_boxed()).length);
					atypes[2 + si + 1] = Libffi.SINT32;
					offset += 1;
					si += 2;
					ai += 1;
					continue;
				}
				var tag = "";
				if (rest.has_prefix("f")) {
					tag = "f";
					offset += 1;
				} else {
					var rest_ptr = (char*) rest;
					var next = (char*) null;
					if (!GLib.VariantType.string_scan(rest, null, out next)
						|| next == rest_ptr) {
						GLib.error("invalid D-Bus type signature %s", signature);
					}
					var n = (long) ((uint8*) next - (uint8*) rest_ptr);
					tag = rest.substring(0, n);
					offset += (int) n;
				}
				this.pack(tag, this.request.args.get(ai), ref slots[2 + si], out atypes[2 + si]);
				si += 1;
				ai += 1;
			}
			var cif = Libffi.Cif();
			if (Libffi.Cif.prep(out cif, atypes) != 0) {
				GLib.critical("RPC dispatch: ffi_prep_cif failed for %s",
					this.request.method);
				return true;
			}
			cif.call(fn, slots);
			return true;
		}
	}
}
