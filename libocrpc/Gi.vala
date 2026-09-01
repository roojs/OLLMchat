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
		 * Typelib namespace names from {@link register} (''Clutter'', ''Meta'').
		 *
		 * Bare wire prefix ''Clutter.get_default_text_direction'' looks up
		 * here; object aliases stay in {@link types} (''Clutter-Actor'').
		 */
		public static Gee.ArrayList<string> namespaces;

		/**
		 * Inbound call this instance applies. Owner of method / args /
		 * connection — not copied onto {@link Gi}.
		 */
		public Request request { get; construct; }

		private GI.Argument[] in_args = {};

		private GI.Argument[] out_args = {};

		/**
		 * Copies of IN / caller-allocates OUT blobs for the current
		 * {@link dispatch_new} / {@link dispatch_function} invoke.
		 * {@link GI.Argument} pointers alias {@link GLib.Bytes.get_data}
		 * here.
		 */
		private Gee.ArrayList<GLib.Bytes> boxed_keep = new Gee.ArrayList<GLib.Bytes>();

		/**
		 * IN {@link GLib.List} / {@link GLib.SList} heads for the current
		 * invoke. Element pointers are lease-backed GObjects, UTF8
		 * strings, or boxed blobs (transfer none). Assigning ''{}''
		 * runs each compact ''free_function'' (''g_list_free'' /
		 * ''g_slist_free'').
		 */
		private GLib.List<void*>[] glist_keep = {};

		private GLib.SList<void*>[] gslist_keep = {};

		private bool[] skip_wire = {};

		private int[] in_slot = {};

		/**
		 * Call C g_function_info_invoke with an out return slot.
		 *
		 * WORKAROUND: the system vapi
		 * {@link GI.FunctionInfo.invoke} takes
		 * {@link GI.Argument} return_value by value, so
		 * libffi writes the object pointer into a copy and
		 * the caller sees null. This declaration is the same
		 * C function with return_value as ''out''
		 * ({@link GI.Argument}*). Do not use ''fn.invoke''.
		 *
		 * Real fix: correct the annotations / comments on
		 * g_function_info_invoke (and the generated
		 * {@link GI.FunctionInfo.invoke} vapi) so
		 * return_value is ''out''. Then delete this binding
		 * and call ''fn.invoke'' again.
		 *
		 * @param info typelib function to run
		 * @param in_args IN slots
		 * @param out_args OUT slots
		 * @param return_value filled by libffi
		 * @return false when invoke fails
		 * @throws GI.InvokeError from g_function_info_invoke
		 */
		[CCode (cname = "g_function_info_invoke", cheader_filename = "girepository.h")]
		private static extern bool g_function_info_invoke(
			GI.FunctionInfo info,
			[CCode (array_length_cname = "n_in_args", array_length_pos = 2.5)] GI.Argument[] in_args,
			[CCode (array_length_cname = "n_out_args", array_length_pos = 3.5)] GI.Argument[] out_args,
			out GI.Argument return_value
		) throws GI.InvokeError;

		public Gi(Request request)
		{
			GLib.Object(request: request);
		}

		/**
		 * Require ''ns'' / ''version'' and register each object or
		 * interface GType.
		 *
		 * Alias is ''ns-Name'' (hyphen, same style as ''RPC-Live-Remote'').
		 * Skips infos that are not objects or interfaces, or have no GType.
		 * A second register of the same alias is a no-op.
		 * Also records ''ns'' in {@link namespaces} so bare
		 * ''Clutter.fn'' / ''Meta.fn'' dispatch to typelib namespace
		 * functions.
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
			if (namespaces == null) {
				namespaces = new Gee.ArrayList<string>();
			}
			if (!namespaces.contains(ns)) {
				namespaces.add(ns);
			}
			GI.Repository.get_default().require(ns, version, 0);
			var n = GI.Repository.get_default().get_n_infos(ns);
			for (var i = 0; i < n; i++) {
				var info = GI.Repository.get_default().get_info(ns, i);
				if (info.get_type() != GI.InfoType.OBJECT
					&& info.get_type() != GI.InfoType.INTERFACE) {
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
		 * Prefix in {@link types} → object/interface
		 * {@link GI.ObjectInfo.find_method} (objects walk
		 * {@link GI.ObjectInfo.get_parent}). Prefix in
		 * {@link namespaces} → {@link GI.Repository.find_by_name} for a
		 * namespace function. Constructors go to {@link dispatch_new}.
		 * Other callables go to {@link dispatch_function}. Missing
		 * method replies METHOD_NOT_FOUND. Unknown prefix returns false
		 * so {@link Request.dispatch} can fall through.
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
			GI.FunctionInfo fn;
			if (types.has_key(object_name)) {
				var info = GI.Repository.get_default().find_by_gtype(
					types.get(object_name));
				if (info.get_type() == GI.InfoType.INTERFACE) {
					fn = ((GI.InterfaceInfo) info).find_method(method_name);
				} else {
					var obj_info = (GI.ObjectInfo) info;
					fn = obj_info.find_method(method_name);
					while (fn == null) {
						obj_info = obj_info.get_parent();
						if (obj_info == null) {
							break;
						}
						fn = obj_info.find_method(method_name);
					}
				}
				if (fn == null) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.METHOD_NOT_FOUND);
					return true;
				}
			} else {
				if (!namespaces.contains(object_name)) {
					return false;
				}
				var info = GI.Repository.get_default().find_by_name(
					object_name, method_name);
				if (info == null || info.get_type() != GI.InfoType.FUNCTION) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.METHOD_NOT_FOUND);
					return true;
				}
				fn = (GI.FunctionInfo) info;
			}
			this.skip_wire = new bool[fn.get_n_args()];
			this.in_slot = new int[fn.get_n_args()];
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_type().get_tag() != GI.TypeTag.INTERFACE) {
					continue;
				}
				if (arg.get_type().get_interface().get_type() != GI.InfoType.CALLBACK) {
					continue;
				}
				if (arg.get_closure() >= 0) {
					this.skip_wire[arg.get_closure()] = true;
				}
				if (arg.get_destroy() >= 0) {
					this.skip_wire[arg.get_destroy()] = true;
				}
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
			var n_values = 0;
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
				this.in_slot[i] = n_in;
				n_in++;
				if (this.skip_wire[i]) {
					continue;
				}
				n_values++;
			}
			if (n_values != this.request.args.size) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
			}
			this.in_args = new GI.Argument[n_in];
			this.out_args = new GI.Argument[0];
			this.boxed_keep.clear();
			this.glist_keep = {};
			this.gslist_keep = {};
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (this.skip_wire[i]) {
					continue;
				}
				if (!this.convert(arg, vi)) {
					return true;
				}
				vi++;
			}
			var ret = GI.Argument();
			try {
				g_function_info_invoke(fn, this.in_args, this.out_args, out ret);
			} catch (GLib.Error e) {
				this.request.connection.reply_error(this.request,
					(int) RpcErrorCode.INTERNAL_ERROR, e);
				return true;
			}
			var created = (GLib.Object) ret.v_pointer;
			this.request.connection.export(created);
			this.request.reply(new Response() {
				retval = OLLMrpc.val("o", created)
			});
			return true;
		}

		/**
		 * Invoke a typelib callable (instance method or namespace function).
		 *
		 * When {@link GI.FunctionInfo.is_method}, slot 0 is the leased
		 * instance. Namespace functions use no lease and start IN at 0.
		 * Remaining IN args use {@link convert}. The C return uses
		 * {@link scalar} into {@link Response.retval}. OUT / INOUT use
		 * {@link scalar} into {@link Response.args}.
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
			var instance = fn.is_method();
			var id = 0;
			if (instance) {
				if (this.request.lease_id == 0) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				id = (int) this.request.lease_id;
				if (!this.request.connection.leases.has_key(id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
			}
			var n_in = instance ? 1 : 0;
			var n_out = 0;
			var n_values = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				switch (arg.get_direction()) {
					case GI.Direction.IN:
						this.in_slot[i] = n_in;
						n_in++;
						if (this.skip_wire[i]) {
							break;
						}
						n_values++;
						break;

					case GI.Direction.OUT:
						n_out++;
						break;

					case GI.Direction.INOUT:
						this.in_slot[i] = n_in;
						n_in++;
						n_out++;
						if (this.skip_wire[i]) {
							break;
						}
						n_values++;
						break;
				}
			}
			if (n_values != this.request.args.size) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			this.in_args = new GI.Argument[n_in];
			this.out_args = new GI.Argument[n_out];
			this.boxed_keep.clear();
			this.glist_keep = {};
			this.gslist_keep = {};
			if (instance) {
				this.in_args[0].v_pointer = (void*) this.request.connection.leases.get(id);
			}
			var out_i = 0;
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (this.skip_wire[i]) {
					continue;
				}
				if (arg.get_direction() != GI.Direction.OUT) {
					if (!this.convert(arg, vi, instance ? 1 : 0)) {
						return true;
					}
					vi++;
					continue;
				}
				if (!arg.is_caller_allocates() || arg.get_type().get_tag() != GI.TypeTag.INTERFACE) {
					out_i++;
					continue;
				}
				var kind = arg.get_type().get_interface().get_type();
				size_t n = 0;
				if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
					var si = (GI.StructInfo) arg.get_type().get_interface();
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				} else if (kind == GI.InfoType.UNION) {
					n = ((GI.UnionInfo) arg.get_type().get_interface()).get_size();
				}
				if (n == 0) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				var buf = new uint8[n];
				var keep = new GLib.Bytes(buf);
				this.boxed_keep.add(keep);
				this.out_args[out_i].v_pointer = (void*) keep.get_data();
				out_i++;
			}
			var ret = GI.Argument();
			try {
				g_function_info_invoke(fn, this.in_args, this.out_args, out ret);
			} catch (GLib.Error e) {
				this.request.connection.reply_error(this.request,
					(int) RpcErrorCode.INTERNAL_ERROR, e);
				return true;
			}
			var response = new Response();
			var ret_type = fn.get_return_type();
			switch (ret_type.get_tag()) {
				case GI.TypeTag.VOID:
					break;

				case GI.TypeTag.GLIST:
				case GI.TypeTag.GSLIST:
					if (!this.scalar_list(ret_type, ret, response)) {
						return true;
					}
					break;

				case GI.TypeTag.GHASH:
					if (!this.scalar_hash(ret_type, ret, response)) {
						return true;
					}
					break;

				case GI.TypeTag.INTERFACE:
					var kind = ret_type.get_interface().get_type();
					if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
						var packed = new Gee.ArrayList<GLib.Value?>();
						if (!this.scalar(ret_type, ret, packed)) {
							return true;
						}
						response.retval = packed.get(0);
						break;
					}
					var created = (GLib.Object) ret.v_pointer;
					if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(created.get_type())) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return true;
					}
					this.request.connection.export(created);
					response.retval = OLLMrpc.val("o", created);
					break;

				default:
					var packed = new Gee.ArrayList<GLib.Value?>();
					if (!this.scalar(ret_type, ret, packed)) {
						return true;
					}
					response.retval = packed.get(0);
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
				if (!this.scalar(arg.get_type(), this.out_args[oi], response.args)) {
					return true;
				}
				oi++;
			}
			this.request.reply(response);
			return true;
		}

		/**
		 * Fill one {@link in_args} slot from {@link request}.args.
		 *
		 * Uses ''arg'' TypeTag. Reads {@link request}.args at ''vi'' —
		 * writes {@link in_args} at ''vi + offset''. Unknown tags reply
		 * INVALID_PARAMS. ''offset'' is ''0'' for constructors.
		 *
		 * @param arg one IN argument from the callable
		 * @param vi index in {@link request}.args
		 * @param offset added to ''vi'' for {@link in_args} (''1'' when slot 0 is the instance)
		 * @return false when this method already replied an error
		 */
		private bool convert(GI.ArgInfo arg, int vi, int offset = 0)
		{
			var val = this.request.args.get(vi);
			var tag = arg.get_type().get_tag();
			var want = GLib.Type.INVALID;
			switch (tag) {
				case GI.TypeTag.BOOLEAN:
					want = GLib.Type.BOOLEAN;
					break;

				case GI.TypeTag.INT8:
					want = GLib.Type.CHAR;
					break;

				case GI.TypeTag.UINT8:
					want = GLib.Type.UCHAR;
					break;

				case GI.TypeTag.INT16:
				case GI.TypeTag.INT32:
					want = GLib.Type.INT;
					break;

				case GI.TypeTag.UINT16:
				case GI.TypeTag.UINT32:
					want = GLib.Type.UINT;
					break;

				case GI.TypeTag.INT64:
					want = GLib.Type.INT64;
					break;

				case GI.TypeTag.UINT64:
					want = GLib.Type.UINT64;
					break;

				case GI.TypeTag.FLOAT:
					want = GLib.Type.FLOAT;
					break;

				case GI.TypeTag.DOUBLE:
					want = GLib.Type.DOUBLE;
					break;

				default:
					break;
			}
			if (want != GLib.Type.INVALID && val.type() != want) {
				var coerced = GLib.Value(want);
				if (!val.transform(ref coerced)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				val = coerced;
			}
			switch (tag) {
				case GI.TypeTag.BOOLEAN:
					this.in_args[vi + offset].v_boolean = val.get_boolean();
					return true;

				case GI.TypeTag.INT8:
					this.in_args[vi + offset].v_int8 = val.get_schar();
					return true;

				case GI.TypeTag.UINT8:
					this.in_args[vi + offset].v_uint8 = val.get_uchar();
					return true;

				case GI.TypeTag.INT16:
					this.in_args[vi + offset].v_int16 = (int16) val.get_int();
					return true;

				case GI.TypeTag.UINT16:
					this.in_args[vi + offset].v_uint16 = (uint16) val.get_uint();
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

				case GI.TypeTag.FLOAT:
					this.in_args[vi + offset].v_float = val.get_float();
					return true;

				case GI.TypeTag.DOUBLE:
					this.in_args[vi + offset].v_double = val.get_double();
					return true;

				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					this.in_args[vi + offset].v_string = val.get_string();
					return true;

				case GI.TypeTag.ARRAY:
					return this.convert_array(arg, vi, offset);

				case GI.TypeTag.GLIST:
				case GI.TypeTag.GSLIST:
					return this.convert_list(arg, vi, offset);

				case GI.TypeTag.INTERFACE:
					return this.convert_interface(arg, vi, offset);

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		/**
		 * Fill one {@link in_args} slot for a GIR ARRAY IN argument.
		 *
		 * The wire row must match the element {@link GI.TypeTag}. Pointer
		 * aliases the array already in {@link request}.args.
		 *
		 * @param arg one IN argument from the callable
		 * @param vi index in {@link request}.args
		 * @param offset added to ''vi'' for {@link in_args}
		 * @return false when this method already replied an error
		 */
		private bool convert_array(GI.ArgInfo arg, int vi, int offset)
		{
			var val = this.request.args.get(vi);
			var elem = arg.get_type().get_param_type(0);
			if (val.type() == typeof(string[])) {
				switch (elem.get_tag()) {
					case GI.TypeTag.UTF8:
					case GI.TypeTag.FILENAME:
						this.in_args[vi + offset].v_pointer = (void*) (string[]) val;
						return true;
					default:
						break;
				}
			}
			if (val.type() != typeof(GLib.Variant)) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			switch (elem.get_tag()) {
				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					var str_variant = val.dup_variant();
					if (!str_variant.is_of_type(new GLib.VariantType("as"))) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					string[] strv = {};
					for (var i = 0; i < str_variant.n_children(); i++) {
						strv += str_variant.get_child_value(i).get_string();
					}
					this.in_args[vi + offset].v_pointer = (void*) strv;
					return true;

				case GI.TypeTag.INT32:
					var int_variant = val.dup_variant();
					if (!int_variant.is_of_type(new GLib.VariantType("ai"))) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var int_nbytes = int_variant.get_size();
					var int_slab = new uint8[int_nbytes];
					GLib.Memory.copy(int_slab, int_variant.get_data(), int_nbytes);
					var int_keep = new GLib.Bytes(int_slab);
					this.boxed_keep.add(int_keep);
					this.in_args[vi + offset].v_pointer = (void*) int_keep.get_data();
					return true;

				case GI.TypeTag.UINT32:
					var uint_variant = val.dup_variant();
					if (!uint_variant.is_of_type(new GLib.VariantType("au"))) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var uint_nbytes = uint_variant.get_size();
					var uint_slab = new uint8[uint_nbytes];
					GLib.Memory.copy(uint_slab, uint_variant.get_data(), uint_nbytes);
					var uint_keep = new GLib.Bytes(uint_slab);
					this.boxed_keep.add(uint_keep);
					this.in_args[vi + offset].v_pointer = (void*) uint_keep.get_data();
					return true;

				case GI.TypeTag.INT64:
					var i64_variant = val.dup_variant();
					if (!i64_variant.is_of_type(new GLib.VariantType("ax"))) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var i64_nbytes = i64_variant.get_size();
					var i64_slab = new uint8[i64_nbytes];
					GLib.Memory.copy(i64_slab, i64_variant.get_data(), i64_nbytes);
					var i64_keep = new GLib.Bytes(i64_slab);
					this.boxed_keep.add(i64_keep);
					this.in_args[vi + offset].v_pointer = (void*) i64_keep.get_data();
					return true;

				case GI.TypeTag.UINT64:
					var u64_variant = val.dup_variant();
					if (!u64_variant.is_of_type(new GLib.VariantType("at"))) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var u64_nbytes = u64_variant.get_size();
					var u64_slab = new uint8[u64_nbytes];
					GLib.Memory.copy(u64_slab, u64_variant.get_data(), u64_nbytes);
					var u64_keep = new GLib.Bytes(u64_slab);
					this.boxed_keep.add(u64_keep);
					this.in_args[vi + offset].v_pointer = (void*) u64_keep.get_data();
					return true;

				case GI.TypeTag.FLOAT:
					var float_variant = val.dup_variant();
					if (!float_variant.is_of_type(new GLib.VariantType("af"))) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var float_nbytes = float_variant.get_size();
					var float_slab = new uint8[float_nbytes];
					GLib.Memory.copy(float_slab, float_variant.get_data(), float_nbytes);
					var float_keep = new GLib.Bytes(float_slab);
					this.boxed_keep.add(float_keep);
					this.in_args[vi + offset].v_pointer = (void*) float_keep.get_data();
					return true;

				case GI.TypeTag.DOUBLE:
					var double_variant = val.dup_variant();
					if (!double_variant.is_of_type(new GLib.VariantType("ad"))) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var double_nbytes = double_variant.get_size();
					var double_slab = new uint8[double_nbytes];
					GLib.Memory.copy(double_slab, double_variant.get_data(), double_nbytes);
					var double_keep = new GLib.Bytes(double_slab);
					this.boxed_keep.add(double_keep);
					this.in_args[vi + offset].v_pointer = (void*) double_keep.get_data();
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		/**
		 * Fill one {@link in_args} slot for a GIR GLIST / GSLIST IN argument.
		 *
		 * UTF8 / FILENAME: native ''string[]'' (unboxed). GObject /
		 * GInterface: {@link GLib.Variant} ''at'' (uint64 lease ids) via
		 * {@link Transport.Connection.leases}. STRUCT / BOXED / UNION:
		 * {@link GLib.Variant} ''aay'', each blob
		 * {@link GI.StructInfo.get_size}. Empty array → null pointer.
		 * Owned {@link GLib.List} / {@link GLib.SList} of ''void*''. Heads
		 * stay on glist_keep / gslist_keep until the next invoke assigns
		 * ''{}''.
		 *
		 * @param arg one IN argument from the callable
		 * @param vi index in {@link request}.args
		 * @param offset added to ''vi'' for {@link in_args}
		 * @return false when this method already replied an error
		 */
		private bool convert_list(GI.ArgInfo arg, int vi, int offset)
		{
			var val = this.request.args.get(vi);
			var type = arg.get_type();
			var elem = type.get_param_type(0);
			switch (elem.get_tag()) {
				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					if (val.type() != typeof(string[])) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var strv = (string[]) val;
					if (strv.length == 0) {
						this.in_args[vi + offset].v_pointer = null;
						return true;
					}
					if (type.get_tag() == GI.TypeTag.GLIST) {
						GLib.List<void*> utf8_list = null;
						for (var i = 0; i < strv.length; i++) {
							utf8_list.append((void*) strv[i]);
						}
						this.in_args[vi + offset].v_pointer = utf8_list;
						this.glist_keep += (owned) utf8_list;
						return true;
					}
					GLib.SList<void*> utf8_slist = null;
					for (var i = 0; i < strv.length; i++) {
						utf8_slist.append((void*) strv[i]);
					}
					this.in_args[vi + offset].v_pointer = utf8_slist;
					this.gslist_keep += (owned) utf8_slist;
					return true;

				case GI.TypeTag.INTERFACE:
					break;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
			var kind = elem.get_interface().get_type();
			if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED || kind == GI.InfoType.UNION) {
				size_t n = 0;
				if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
					var si = (GI.StructInfo) elem.get_interface();
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				}
				if (kind == GI.InfoType.UNION) {
					n = ((GI.UnionInfo) elem.get_interface()).get_size();
				}
				if (n == 0) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				if (val.type() != typeof(GLib.Variant)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				var blobs = val.dup_variant();
				if (!blobs.is_of_type(new GLib.VariantType("aay"))) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				if (blobs.n_children() == 0) {
					this.in_args[vi + offset].v_pointer = null;
					return true;
				}
				if (type.get_tag() == GI.TypeTag.GLIST) {
					GLib.List<void*> boxed_list = null;
					for (var i = 0; i < blobs.n_children(); i++) {
						var blob = blobs.get_child_value(i).get_data_as_bytes();
						if (blob.get_size() != n) {
							this.request.connection.reply_error(
								this.request, (int) RpcErrorCode.INVALID_PARAMS);
							return false;
						}
						var keep = new GLib.Bytes(blob.get_data());
						this.boxed_keep.add(keep);
						boxed_list.append((void*) keep.get_data());
					}
					this.in_args[vi + offset].v_pointer = boxed_list;
					this.glist_keep += (owned) boxed_list;
					return true;
				}
				GLib.SList<void*> boxed_slist = null;
				for (var i = 0; i < blobs.n_children(); i++) {
					var blob = blobs.get_child_value(i).get_data_as_bytes();
					if (blob.get_size() != n) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var keep = new GLib.Bytes(blob.get_data());
					this.boxed_keep.add(keep);
					boxed_slist.append((void*) keep.get_data());
				}
				this.in_args[vi + offset].v_pointer = boxed_slist;
				this.gslist_keep += (owned) boxed_slist;
				return true;
			}
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			if (val.type() != typeof(GLib.Variant)) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			var variant = val.dup_variant();
			if (!variant.is_of_type(new GLib.VariantType("at"))) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			if (variant.n_children() == 0) {
				this.in_args[vi + offset].v_pointer = null;
				return true;
			}
			if (type.get_tag() == GI.TypeTag.GLIST) {
				GLib.List<void*> list = null;
				for (var i = 0; i < variant.n_children(); i++) {
					var id = (int) variant.get_child_value(i).get_uint64();
					if (!this.request.connection.leases.has_key(id)) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var obj = this.request.connection.leases.get(id);
					if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(obj.get_type())) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					list.append((void*) obj);
				}
				this.in_args[vi + offset].v_pointer = list;
				this.glist_keep += (owned) list;
				return true;
			}
			GLib.SList<void*> slist = null;
			for (var i = 0; i < variant.n_children(); i++) {
				var id = (int) variant.get_child_value(i).get_uint64();
				if (!this.request.connection.leases.has_key(id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				var obj = this.request.connection.leases.get(id);
				if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(obj.get_type())) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				slist.append((void*) obj);
			}
			this.in_args[vi + offset].v_pointer = slist;
			this.gslist_keep += (owned) slist;
			return true;
		}

		/**
		 * Fill one {@link in_args} slot for a GIR INTERFACE argument.
		 *
		 * GObject / GInterface: lease id or a live object in
		 * {@link request}.args. The instance GType must be in
		 * {@link Bin.gtype_to_alias} (''Gi.register'' object types).
		 * STRUCT / BOXED / UNION: {@link GLib.Bytes}
		 * of {@link GI.StructInfo.get_size}. gtype-structs, size 0, and
		 * other InfoTypes reply INVALID_PARAMS (one ''n == 0'' path).
		 *
		 * @param arg one IN argument from the callable
		 * @param vi index in {@link request}.args
		 * @param offset added to ''vi'' for {@link in_args}
		 * @return false when this method already replied an error
		 */
		private bool convert_interface(GI.ArgInfo arg, int vi, int offset)
		{
			var val = this.request.args.get(vi);
			var kind = arg.get_type().get_interface().get_type();
			if (kind == GI.InfoType.CALLBACK) {
				if (val.type() != GLib.Type.UINT64) {
					var coerced = GLib.Value(GLib.Type.UINT64);
					if (!val.transform(ref coerced)) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					val = coerced;
				}
				var id = (int) val.get_uint64();
				if (!this.request.connection.callbacks.has_key(id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				var row = this.request.connection.callbacks.get(id);
				var closure_i = arg.get_closure();
				if (closure_i >= 0) {
					this.in_args[this.in_slot[closure_i]].v_pointer = (void*) row;
				}
				var destroy_i = arg.get_destroy();
				if (destroy_i >= 0) {
					this.in_args[this.in_slot[destroy_i]].v_pointer = (void*) Live.Hook.drop;
				}
				return true;
			}
			if (kind == GI.InfoType.OBJECT || kind == GI.InfoType.INTERFACE) {
				if (val.type().is_a(GLib.Type.OBJECT)) {
					if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(val.get_object().get_type())) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					this.in_args[vi + offset].v_pointer = (void*) val.get_object();
					return true;
				}
				var id = (int) val.get_uint64();
				if (!this.request.connection.leases.has_key(id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				var obj = this.request.connection.leases.get(id);
				if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(obj.get_type())) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				this.in_args[vi + offset].v_pointer = (void*) obj;
				return true;
			}
			if (kind == GI.InfoType.FLAGS) {
				this.in_args[vi + offset].v_uint32 = val.get_flags();
				return true;
			}
			if (kind == GI.InfoType.ENUM) {
				if (val.type().is_a(GLib.Type.ENUM)) {
					this.in_args[vi + offset].v_int32 = val.get_enum();
					return true;
				}
				this.in_args[vi + offset].v_int32 = val.get_int();
				return true;
			}
			size_t n = 0;
			if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
				var si = (GI.StructInfo) arg.get_type().get_interface();
				if (!si.is_gtype_struct()) {
					n = si.get_size();
				}
			} else if (kind == GI.InfoType.UNION) {
				n = ((GI.UnionInfo) arg.get_type().get_interface()).get_size();
			}
			if (n == 0) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			if (val.type() != typeof(GLib.Bytes)) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			var blob = (GLib.Bytes) val.get_boxed();
			if (blob.get_size() != n) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			var keep = new GLib.Bytes(blob.get_data());
			this.boxed_keep.add(keep);
			this.in_args[vi + offset].v_pointer = (void*) keep.get_data();
			return true;
		}

		/**
		 * Append one GI scalar to dest.
		 *
		 * Reverse of {@link convert}. Unknown tags reply INVALID_PARAMS.
		 *
		 * @param type GIR type of the return or OUT argument
		 * @param arg filled by {@link GI.FunctionInfo.invoke}
		 * @param dest OUT list, or a one-element list copied onto retval
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

				case GI.TypeTag.FLOAT:
					var fl = GLib.Value(typeof(float));
					fl.set_float(arg.v_float);
					dest.add(fl);
					return true;

				case GI.TypeTag.DOUBLE:
					var db = GLib.Value(typeof(double));
					db.set_double(arg.v_double);
					dest.add(db);
					return true;

				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					var s = GLib.Value(typeof(string));
					s.set_string(arg.v_string);
					dest.add(s);
					return true;

				case GI.TypeTag.ARRAY:
					return this.scalar_array(type, arg, dest);

				case GI.TypeTag.INTERFACE:
					var kind = type.get_interface().get_type();
					if (kind == GI.InfoType.ENUM) {
						var e = GLib.Value(typeof(int));
						e.set_int(arg.v_int32);
						dest.add(e);
						return true;
					}
					if (kind == GI.InfoType.FLAGS) {
						var f = GLib.Value(typeof(uint));
						f.set_uint(arg.v_uint32);
						dest.add(f);
						return true;
					}
					size_t n = 0;
					if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
						var si = (GI.StructInfo) type.get_interface();
						if (!si.is_gtype_struct()) {
							n = si.get_size();
						}
					} else if (kind == GI.InfoType.UNION) {
						n = ((GI.UnionInfo) type.get_interface()).get_size();
					}
					if (n == 0) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					if (arg.v_pointer == null) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var copy = new uint8[n];
					GLib.Memory.copy(copy, arg.v_pointer, n);
					var boxed_val = GLib.Value(typeof(GLib.Bytes));
					boxed_val.set_boxed(new GLib.Bytes(copy));
					dest.add(boxed_val);
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		/**
		 * Append one GIR ARRAY return / OUT argument to {@link dest}.
		 *
		 * Zero-terminated UTF8 / FILENAME → ''string[]''. Fixed-size
		 * numeric → typed array via {@link GLib.Memory.copy}.
		 *
		 * @param type GIR array type
		 * @param arg filled by {@link GI.FunctionInfo.invoke}
		 * @param dest OUT list, or a one-element list copied onto retval
		 * @return false when this method already replied an error
		 */
		private bool scalar_array(
			GI.TypeInfo type,
			GI.Argument arg,
			Gee.ArrayList<GLib.Value?> dest
		)
		{
			var elem = type.get_param_type(0);
			var n_arr = type.get_array_fixed_size();
			if (n_arr < 0 && type.is_zero_terminated()
				&& (elem.get_tag() == GI.TypeTag.UTF8 || elem.get_tag() == GI.TypeTag.FILENAME)) {
				string[] strv = {};
				unowned string** rows = (string**) arg.v_pointer;
				for (var i = 0; rows[i] != null; i++) {
					strv += rows[i];
				}
				dest.add(new GLib.Variant("as", strv));
				return true;
			}
			if (n_arr < 0) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			switch (elem.get_tag()) {
				case GI.TypeTag.INT32:
					var ints = new int[n_arr];
					GLib.Memory.copy(ints, arg.v_pointer, n_arr * sizeof(int));
					dest.add(GLib.Variant.new_fixed_array(
						new GLib.VariantType("i"), ints, sizeof(int)));
					return true;

				case GI.TypeTag.UINT32:
					var uints = new uint[n_arr];
					GLib.Memory.copy(uints, arg.v_pointer, n_arr * sizeof(uint));
					dest.add(GLib.Variant.new_fixed_array(
						new GLib.VariantType("u"), uints, sizeof(uint)));
					return true;

				case GI.TypeTag.INT64:
					var i64s = new int64[n_arr];
					GLib.Memory.copy(i64s, arg.v_pointer, n_arr * sizeof(int64));
					dest.add(GLib.Variant.new_fixed_array(
						new GLib.VariantType("x"), i64s, sizeof(int64)));
					return true;

				case GI.TypeTag.UINT64:
					var u64s = new uint64[n_arr];
					GLib.Memory.copy(u64s, arg.v_pointer, n_arr * sizeof(uint64));
					dest.add(GLib.Variant.new_fixed_array(
						new GLib.VariantType("t"), u64s, sizeof(uint64)));
					return true;

				case GI.TypeTag.FLOAT:
					var floats = new float[n_arr];
					GLib.Memory.copy(floats, arg.v_pointer, n_arr * sizeof(float));
					dest.add(GLib.Variant.new_fixed_array(
						new GLib.VariantType("f"), floats, sizeof(float)));
					return true;

				case GI.TypeTag.DOUBLE:
					var doubles = new double[n_arr];
					GLib.Memory.copy(doubles, arg.v_pointer, n_arr * sizeof(double));
					dest.add(GLib.Variant.new_fixed_array(
						new GLib.VariantType("d"), doubles, sizeof(double)));
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		/**
		 * Export a GIR GLIST / GSLIST return.
		 *
		 * UTF8 / FILENAME → native ''string[]'' on {@link Response.retval}.
		 * Registered GObject {@link GI.TypeTag.INTERFACE} → leased rows
		 * on {@link Response.retval}. Null utf8 list → empty string array.
		 * Null object list → empty retval.
		 *
		 * @param type GIR list type
		 * @param arg filled by {@link GI.FunctionInfo.invoke}
		 * @param response reply being built
		 * @return false when this method already replied an error
		 */
		private bool scalar_list(
			GI.TypeInfo type,
			GI.Argument arg,
			Response response
		)
		{
			var elem = type.get_param_type(0);
			switch (elem.get_tag()) {
				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					string[] strv = {};
					if (arg.v_pointer != null && type.get_tag() == GI.TypeTag.GLIST) {
						for (unowned GLib.List<void*>? node = (GLib.List<void*>) arg.v_pointer;
							node != null; node = node.next) {
							strv += (string) node.data;
						}
					}
					if (arg.v_pointer != null && type.get_tag() == GI.TypeTag.GSLIST) {
						for (unowned GLib.SList<void*>? node = (GLib.SList<void*>) arg.v_pointer;
							node != null; node = node.next) {
							strv += (string) node.data;
						}
					}
					var as_val = GLib.Value(typeof(string[]));
					as_val.set_boxed(strv);
					response.retval = as_val;
					return true;

				case GI.TypeTag.INTERFACE:
					break;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
			var kind = elem.get_interface().get_type();
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			if (arg.v_pointer == null) {
				return true;
			}
			if (type.get_tag() == GI.TypeTag.GLIST) {
				var list = new Gee.ArrayList<GLib.Object>();
				for (unowned GLib.List<GLib.Object>? node = (GLib.List<GLib.Object>) arg.v_pointer;
					node != null; node = node.next) {
					var obj = node.data;
					if (Bin.gtype_to_alias != null && Bin.gtype_to_alias.has_key(obj.get_type())) {
						this.request.connection.export(obj);
						list.add(obj);
						continue;
					}
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				response.retval = OLLMrpc.val("o", list);
				return true;
			}
			var slist = new Gee.ArrayList<GLib.Object>();
			for (unowned GLib.SList<GLib.Object>? node = (GLib.SList<GLib.Object>) arg.v_pointer;
				node != null; node = node.next) {
				var obj = node.data;
				if (Bin.gtype_to_alias != null && Bin.gtype_to_alias.has_key(obj.get_type())) {
					this.request.connection.export(obj);
					slist.add(obj);
					continue;
				}
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			response.retval = OLLMrpc.val("o", slist);
			return true;
		}

		/**
		 * Export each GObject value from a GIR GHASH return.
		 *
		 * Only ''UTF8'' keys and registered GObject values. Null table →
		 * empty {@link Response.retval}. Iteration order is undefined.
		 *
		 * @param type GIR hash type
		 * @param arg filled by {@link GI.FunctionInfo.invoke}
		 * @param response reply being built
		 * @return false when this method already replied an error
		 */
		private bool scalar_hash(
			GI.TypeInfo type,
			GI.Argument arg,
			Response response
		)
		{
			var key_type = type.get_param_type(0);
			var val_type = type.get_param_type(1);
			if (key_type.get_tag() != GI.TypeTag.UTF8 || val_type.get_tag() != GI.TypeTag.INTERFACE) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			var kind = val_type.get_interface().get_type();
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			if (arg.v_pointer == null) {
				return true;
			}
			var ht = (GLib.HashTable<string, GLib.Object>) arg.v_pointer;
			var list = new Gee.ArrayList<GLib.Object>();
			foreach (var key in ht.get_keys()) {
				var obj = ht[key];
				if (Bin.gtype_to_alias != null && Bin.gtype_to_alias.has_key(obj.get_type())) {
					this.request.connection.export(obj);
					list.add(obj);
					continue;
				}
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			response.retval = OLLMrpc.val("o", list);
			return true;
		}
	}
}
