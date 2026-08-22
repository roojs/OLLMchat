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
	 * Register GObject types from a typelib and apply RPC calls to them.
	 *
	 * {@link register} requires the namespace, then maps every object
	 * type to a wire alias ({@link Bin.register}) so a client can call
	 * ''Alias.new'' with no handle, then other methods on the lease.
	 * {@link Request.dispatch} constructs {@link Gi} with the inbound
	 * {@link Request} and calls {@link dispatch}. That method finds the
	 * typelib callable and routes constructors to {@link dispatch_new},
	 * other methods to {@link dispatch_function}.
	 * Windows and Android compile ''windows/Gi.vala'' instead (meson,
	 * not ''#if'').
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Gi.register("Gio", "2.0");
	 * var gi = new OLLMrpc.Gi(req);
	 * gi.dispatch();
	 * }}}
	 */
	public class Gi : GLib.Object
	{
		/**
		 * Wire alias → GType for typelib objects (''Gio-Menu'').
		 */
		public static Gee.HashMap<string, GLib.Type> types;

		/**
		 * Inbound call this instance applies. Owner of method / values /
		 * connection — not copied onto {@link Gi}.
		 */
		public Request request { get; construct; }

		private GI.Argument[] in_args = {};

		private GI.Argument[] out_args = {};

		public Gi(Request request)
		{
			GLib.Object(request: request);
		}

		/**
		 * Require ''ns'' / ''version'' and register each object GType.
		 *
		 * Alias is ''ns-Name'' (hyphen, same style as ''RPC-Live-Remote'').
		 * Skips infos that are not objects, or have no GType. A second
		 * register of the same alias is a no-op.
		 *
		 * @param ns typelib namespace (''Gio'', ''Meta'')
		 * @param version typelib version (''2.0'', ''16'')
		 * @throws GLib.Error when {@link GI.Repository.require} fails
		 */
		public static void register(string ns, string version) throws GLib.Error
		{
			if (types == null) {
				types = new Gee.HashMap<string, GLib.Type>();
			}
			GI.Repository.get_default().require(ns, version, 0);
			var n = GI.Repository.get_default().get_n_infos(ns);
			for (var i = 0; i < n; i++) {
				var info = GI.Repository.get_default().get_info(ns, i);
				if (info.get_type() != GI.InfoType.OBJECT) {
					continue;
				}
				var registered = (GI.RegisteredTypeInfo) info;
				var gtype = registered.get_g_type();
				if (gtype == GLib.Type.INVALID) {
					continue;
				}
				var alias = ns + "-" + info.get_name();
				if (Bin.alias_to_gtype != null && Bin.alias_to_gtype.has_key(alias)) {
					types.set(alias, gtype);
					continue;
				}
				Bin.register(alias, gtype);
				types.set(alias, gtype);
			}
		}

		/**
		 * Find the typelib callable and route it.
		 *
		 * Prefix must be in {@link types}. Looks up
		 * {@link GI.ObjectInfo.find_method} for the wire method name.
		 * Constructors go to {@link dispatch_new}. Other callables
		 * go to {@link dispatch_function}. Missing
		 * method replies METHOD_NOT_FOUND. Prefix not in {@link types}
		 * returns false so {@link Request.dispatch} can fall through.
		 *
		 * @return true when this call was a GI path
		 */
		public bool dispatch()
		{
			if (types == null) {
				return false;
			}
			var dot = this.request.method.index_of_char('.');
			var object_name = this.request.method[0:dot];
			var method_name = this.request.method.substring(dot + 1);
			if (!types.has_key(object_name)) {
				return false;
			}
			var info = GI.Repository.get_default().find_by_gtype(
				types.get(object_name));
			var fn = ((GI.ObjectInfo) info).find_method(method_name);
			if (fn == null) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.METHOD_NOT_FOUND);
				return true;
			}
			if ((fn.get_flags() & GI.FunctionInfoFlags.IS_CONSTRUCTOR) != 0) {
				return this.dispatch_new(fn);
			}
			return this.dispatch_function(fn);
		}

		/**
		 * Construct, export, and reply (Phase 2 ''Alias.new'').
		 *
		 * Arg walk stays here. Each IN slot calls {@link convert}.
		 *
		 * @param fn constructor from {@link dispatch}
		 * @return true — this method always replies
		 */
		private bool dispatch_new(GI.FunctionInfo fn)
		{
			if (!this.request.connection.live_handles) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var n_in = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_direction() != GI.Direction.IN) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				n_in++;
			}
			if (n_in != this.request.values.size) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			this.in_args = new GI.Argument[n_in];
			this.out_args = new GI.Argument[0];
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (!this.convert(arg, vi)) {
					return true;
				}
				vi++;
			}
			var ret = GI.Argument();
			try {
				fn.invoke(this.in_args, this.out_args, ret);
			} catch (GLib.Error e) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INTERNAL_ERROR);
				return true;
			}
			var created = (GLib.Object) ret.v_pointer;
			this.request.connection.export(created);
			var response = new Response();
			response.result.add(created);
			this.request.reply(response);
			return true;
		}

		/**
		 * Invoke a typelib method on a leased object.
		 *
		 * Slot 0 is the instance. Remaining IN args use {@link convert}.
		 * Return and OUT args use {@link scalar} into {@link Response.values}.
		 * A returned GObject goes in {@link Response.result} like ''new''.
		 *
		 * @param fn non-constructor from {@link dispatch}
		 * @return true — this method always replies
		 */
		private bool dispatch_function(GI.FunctionInfo fn)
		{
			if (!this.request.connection.live_handles) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			if (this.request.lease_id == 0) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var id = (int) this.request.lease_id;
			if (!this.request.connection.leases.has_key(id)) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			if (!fn.is_method()) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var n_in = 1;
			var n_out = 0;
			var n_values = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				switch (arg.get_direction()) {
					case GI.Direction.IN:
						n_in++;
						n_values++;
						break;

					case GI.Direction.OUT:
						n_out++;
						break;

					case GI.Direction.INOUT:
						n_in++;
						n_out++;
						n_values++;
						break;
				}
			}
			if (n_values != this.request.values.size) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			this.in_args = new GI.Argument[n_in];
			this.out_args = new GI.Argument[n_out];
			this.in_args[0].v_pointer = (void*) this.request.connection.leases.get(id);
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_direction() == GI.Direction.OUT) {
					continue;
				}
				if (!this.convert(arg, vi, 1)) {
					return true;
				}
				vi++;
			}
			var ret = GI.Argument();
			try {
				fn.invoke(this.in_args, this.out_args, ret);
			} catch (GLib.Error e) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INTERNAL_ERROR);
				return true;
			}
			var response = new Response();
			var ret_type = fn.get_return_type();
			switch (ret_type.get_tag()) {
				case GI.TypeTag.VOID:
					break;

				case GI.TypeTag.INTERFACE:
					var created = (GLib.Object) ret.v_pointer;
					this.request.connection.export(created);
					response.result.add(created);
					break;

				default:
					if (!this.scalar(ret_type, ret, response.values)) {
						return true;
					}
					break;
			}
			var oi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_direction() == GI.Direction.IN) {
					continue;
				}
				if (!this.scalar(arg.get_type(), this.out_args[oi], response.values)) {
					return true;
				}
				oi++;
			}
			this.request.reply(response);
			return true;
		}

		/**
		 * Fill one {@link in_args} slot from {@link request}.values.
		 *
		 * Uses ''arg'' TypeTag. Reads {@link request}.values at ''vi'' —
		 * writes {@link in_args} at ''vi + offset''. Unknown tags reply
		 * INVALID_PARAMS. ''offset'' is ''0'' for constructors.
		 *
		 * @param arg one IN argument from the callable
		 * @param vi index in {@link request}.values
		 * @param offset added to ''vi'' for {@link in_args} (''1'' when slot 0 is the instance)
		 * @return false when this method already replied an error
		 */
		private bool convert(GI.ArgInfo arg, int vi, int offset = 0)
		{
			var val = this.request.values.get(vi);
			switch (arg.get_type().get_tag()) {
				case GI.TypeTag.BOOLEAN:
					this.in_args[vi + offset].v_boolean = val.get_boolean();
					return true;

				case GI.TypeTag.INT32:
					this.in_args[vi + offset].v_int32 = val.get_int();
					return true;

				case GI.TypeTag.INT64:
					this.in_args[vi + offset].v_int64 = val.get_int64();
					return true;

				case GI.TypeTag.UINT32:
					this.in_args[vi + offset].v_uint32 = val.get_uint();
					return true;

				case GI.TypeTag.UINT64:
					this.in_args[vi + offset].v_uint64 = val.get_uint64();
					return true;

				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					this.in_args[vi + offset].v_string = val.get_string();
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		/**
		 * Append one GI scalar to a values list.
		 *
		 * Reverse of {@link convert}. Unknown tags reply INVALID_PARAMS.
		 *
		 * @param type GIR type of the return or OUT argument
		 * @param arg filled by {@link GI.FunctionInfo.invoke}
		 * @param dest {@link Response.values}
		 * @return false when this method already replied an error
		 */
		private bool scalar(GI.TypeInfo type, GI.Argument arg, Gee.ArrayList<GLib.Value?> dest)
		{
			switch (type.get_tag()) {
				case GI.TypeTag.BOOLEAN:
					var b = GLib.Value(typeof(bool));
					b.set_boolean(arg.v_boolean);
					dest.add(b);
					return true;

				case GI.TypeTag.INT8:
					var i8 = GLib.Value(typeof(char));
					i8.set_schar(arg.v_int8);
					dest.add(i8);
					return true;

				case GI.TypeTag.UINT8:
					var u8 = GLib.Value(typeof(uchar));
					u8.set_uchar(arg.v_uint8);
					dest.add(u8);
					return true;

				case GI.TypeTag.INT16:
					var i16 = GLib.Value(typeof(int));
					i16.set_int((int) arg.v_int16);
					dest.add(i16);
					return true;

				case GI.TypeTag.UINT16:
					var u16 = GLib.Value(typeof(uint));
					u16.set_uint((uint) arg.v_uint16);
					dest.add(u16);
					return true;

				case GI.TypeTag.INT32:
					var i32 = GLib.Value(typeof(int));
					i32.set_int(arg.v_int32);
					dest.add(i32);
					return true;

				case GI.TypeTag.UINT32:
					var u32 = GLib.Value(typeof(uint));
					u32.set_uint(arg.v_uint32);
					dest.add(u32);
					return true;

				case GI.TypeTag.INT64:
					var i64 = GLib.Value(typeof(int64));
					i64.set_int64(arg.v_int64);
					dest.add(i64);
					return true;

				case GI.TypeTag.UINT64:
					var u64 = GLib.Value(typeof(uint64));
					u64.set_uint64(arg.v_uint64);
					dest.add(u64);
					return true;

				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					var s = GLib.Value(typeof(string));
					s.set_string(arg.v_string);
					dest.add(s);
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}
	}
}
