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
	 * GIR lookup with typed empty replies (no {@link GI.FunctionInfo.invoke}).
	 *
	 * Same wire resolution as {@link Gi.dispatch} using {@link Gi.types} and
	 * {@link Gi.namespaces}. Call {@link Gi.register} before use. Used when
	 * {@link Request.register_mock} was called.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Gi.register("Meta", "16");
	 * OLLMrpc.Gi.register("Clutter", "16");
	 * OLLMrpc.Gi.register("St", "16");
	 * OLLMrpc.Request.register_mock(new HelperMock());
	 * }}}
	 *
	 * @see Gi
	 * @see MockDispatch
	 * @see Request.register_mock
	 */
	public class GiMock : Gi
	{
		private bool[] skip_wire = {};

		private static Gee.HashMap<string, GLib.Type>? mock_gtypes;

		// g_type_register_static_simple is not bound in gobject-2.0.vapi (Vala 0.56).
		[CCode (cname = "g_type_register_static_simple", cheader_name = "glib-object.h")]
		private static extern GLib.Type register_static_simple_type (
			GLib.Type parent_type,
			string type_name,
			uint class_size,
			GLib.ClassInitFunc class_init,
			uint instance_size,
			GLib.InstanceInitFunc instance_init,
			GLib.TypeFlags flags
		);

		public GiMock(Request request)
		{
			GLib.Object(request: request);
		}

		/**
		 * Resolve wire method and reply with typed empties.
		 *
		 * @return true when this call was a GI mock path
		 */
		public new bool dispatch()
		{
			if (Gi.types == null) {
				return false;
			}
			var dot = this.request.method.index_of_char('.');
			var object_name = this.request.method[0:dot];
			var method_name = this.request.method.substring(dot + 1);
			GI.FunctionInfo fn;
			if (Gi.types.has_key(object_name)) {
				var info = GI.Repository.get_default().find_by_gtype(
					Gi.types.get(object_name));
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
				if (!Gi.namespaces.contains(object_name)) {
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
				return this.mock_new(fn);
			}
			return this.mock_function(fn);
		}

		private bool mock_new(GI.FunctionInfo fn)
		{
			if (!this.request.connection.live_handles) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
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
				if (this.skip_wire[i]) {
					continue;
				}
				n_values++;
			}
			if (this.request.args.size > n_values) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (this.skip_wire[i]) {
					continue;
				}
				if (vi >= this.request.args.size) {
					if (!arg.may_be_null()) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return true;
					}
					vi++;
					continue;
				}
				vi++;
			}
			var token = (GLib.Object?) null;
			if (!this.mint_object_lease(fn.get_return_type(), out token)) {
				return true;
			}
			if (token != null) {
				this.request.connection.export(token);
			}
			this.request.reply(new Response() {
				retval = OLLMrpc.val("o", token)
			});
			return true;
		}

		/**
		 * Register (or return cached) fake GType for a wire alias.
		 *
		 * Used by mock servers to mint leases for abstract GIR types without
		 * invoking C. Queries class and instance sizes from the alias GType
		 * (required on GLib 2.84+).
		 *
		 * == Example ==
		 *
		 * {{{
		 * OLLMrpc.Gi.register("Meta", "16");
		 * var gtype = OLLMrpc.GiMock.fake_gtype_for_alias("Meta-Compositor");
		 * var obj = (GLib.Object) GLib.Object.new(gtype);
		 * }}}
		 *
		 * @param alias wire alias from {@link Gi.register} (e.g. Meta-Compositor)
		 * @return fake GType registered under OLLMrpcGiMock_*
		 * @throws GLib.Error unknown alias or registration failure
		 */
		public static GLib.Type fake_gtype_for_alias(string alias) throws GLib.Error
		{
			if (GiMock.mock_gtypes == null) {
				GiMock.mock_gtypes = new Gee.HashMap<string, GLib.Type>();
			}
			if (GiMock.mock_gtypes.has_key(alias)) {
				return GiMock.mock_gtypes.get(alias);
			}
			if (Bin.alias_to_gtype == null || !Bin.alias_to_gtype.has_key(alias)) {
				throw new Bin.StreamError.REGISTRATION(
					"unknown wire alias '%s'", alias);
			}
			var parent = Bin.alias_to_gtype.get(alias);
			var type_name = "OLLMrpcGiMock_" + alias.replace("-", "_");
			GLib.Type fake_gtype = GLib.Type.from_name(type_name);
			if (fake_gtype == GLib.Type.INVALID) {
				GLib.TypeQuery parent_query = {};
				parent.query(out parent_query);
				fake_gtype = GiMock.register_static_simple_type(
					parent,
					type_name,
					parent_query.class_size,
					null,
					parent_query.instance_size,
					null,
					GLib.TypeFlags.NONE
				);
			}
			if (fake_gtype == GLib.Type.INVALID) {
				throw new Bin.StreamError.REGISTRATION(
					"mock gtype register failed for '%s'", alias);
			}
			if (!Bin.gtype_to_alias.has_key(fake_gtype)) {
				Bin.register_alias(alias, fake_gtype);
			}
			GiMock.mock_gtypes.set(alias, fake_gtype);
			return fake_gtype;
		}

		/**
		 * Mint a lease whose GType encodes on the wire as the GIR return type.
		 *
		 * Registers a per-alias fake GType (cached) via {@link Bin.register_alias}
		 * so {@link Bin.Stream.write_reg_gtype} succeeds without invoking C.
		 */
		private bool mint_object_lease(GI.TypeInfo type, out GLib.Object? token)
		{
			token = null;
			if (type.is_pointer()) {
				return true;
			}
			var kind = type.get_interface().get_type();
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			var gtype = ((GI.RegisteredTypeInfo) type.get_interface()).get_g_type();
			if (gtype == GLib.Type.INVALID) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(gtype)) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			try {
				token = (GLib.Object) GLib.Object.new(
					GiMock.fake_gtype_for_alias(
						Bin.gtype_to_alias.get(gtype)));
			} catch (GLib.Error e) {
				this.request.connection.reply_error(this.request,
					(int) RpcErrorCode.INTERNAL_ERROR, e);
				return false;
			}
			return true;
		}

		private bool mock_function(GI.FunctionInfo fn)
		{
			if (!this.request.connection.live_handles) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var instance = fn.is_method();
			if (instance) {
				if (this.request.lease_id == 0) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				if (!this.request.connection.leases.has_key((int) this.request.lease_id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
			}
			var n_values = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				switch (arg.get_direction()) {
					case GI.Direction.IN:
						if (this.skip_wire[i]) {
							break;
						}
						n_values++;
						break;

					case GI.Direction.INOUT:
						if (this.skip_wire[i]) {
							break;
						}
						n_values++;
						break;

					case GI.Direction.OUT:
						break;
				}
			}
			if (this.request.args.size > n_values) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (this.skip_wire[i]) {
					continue;
				}
				if (arg.get_direction() == GI.Direction.OUT) {
					continue;
				}
				if (vi >= this.request.args.size) {
					if (!arg.may_be_null()) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return true;
					}
					vi++;
					continue;
				}
				vi++;
			}
			var response = new Response();
			if (!this.mock_retval(fn.get_return_type(), response)) {
				return true;
			}
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_direction() == GI.Direction.IN) {
					continue;
				}
				GLib.Value out_val;
				if (!this.mock_empty(arg.get_type(), out out_val)) {
					return true;
				}
				if (out_val.type() != GLib.Type.INVALID) {
					response.args.add(out_val);
				}
			}
			this.request.reply(response);
			return true;
		}

		private bool mock_retval(GI.TypeInfo type, Response response)
		{
			switch (type.get_tag()) {
				case GI.TypeTag.VOID:
				case GI.TypeTag.GHASH:
					return true;

				default:
					break;
			}
			GLib.Value val;
			if (!this.mock_empty(type, out val)) {
				return false;
			}
			if (val.type() != GLib.Type.INVALID) {
				response.retval = val;
			}
			return true;
		}

		private bool mock_empty(GI.TypeInfo type, out GLib.Value val)
		{
			val = GLib.Value(GLib.Type.INVALID);
			switch (type.get_tag()) {
				case GI.TypeTag.BOOLEAN:
					val = GLib.Value(typeof(bool));
					val.set_boolean(false);
					return true;

				case GI.TypeTag.INT8:
					val = GLib.Value(typeof(char));
					val.set_schar(0);
					return true;

				case GI.TypeTag.UINT8:
					val = GLib.Value(typeof(uchar));
					val.set_uchar(0);
					return true;

				case GI.TypeTag.INT16:
					val = GLib.Value(typeof(int));
					val.set_int(0);
					return true;

				case GI.TypeTag.UINT16:
					val = GLib.Value(typeof(uint));
					val.set_uint(0);
					return true;

				case GI.TypeTag.INT32:
					val = GLib.Value(typeof(int));
					val.set_int(0);
					return true;

				case GI.TypeTag.UINT32:
					val = GLib.Value(typeof(uint));
					val.set_uint(0);
					return true;

				case GI.TypeTag.INT64:
					val = GLib.Value(typeof(int64));
					val.set_int64(0);
					return true;

				case GI.TypeTag.UINT64:
					val = GLib.Value(typeof(uint64));
					val.set_uint64(0);
					return true;

				case GI.TypeTag.FLOAT:
					val = GLib.Value(typeof(float));
					val.set_float(0.0f);
					return true;

				case GI.TypeTag.DOUBLE:
					val = GLib.Value(typeof(double));
					val.set_double(0.0);
					return true;

				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					val = GLib.Value(typeof(string));
					val.set_string(null);
					return true;

				case GI.TypeTag.GLIST:
				case GI.TypeTag.GSLIST:
					return this.mock_empty_list(type, out val);

				case GI.TypeTag.INTERFACE:
					return this.mock_empty_interface(type, out val);

				case GI.TypeTag.ARRAY:
					return this.mock_empty_array(type, out val);

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		private bool mock_empty_list(GI.TypeInfo type, out GLib.Value val)
		{
			val = GLib.Value(GLib.Type.INVALID);
			var elem = type.get_param_type(0);
			switch (elem.get_tag()) {
				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					val = GLib.Value(typeof(string[]));
					val.set_boxed(new string[] {});
					return true;

				case GI.TypeTag.INTERFACE:
					var kind = elem.get_interface().get_type();
					if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					val = OLLMrpc.val("o", new Gee.ArrayList<GLib.Object>());
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		private bool mock_empty_interface(GI.TypeInfo type, out GLib.Value val)
		{
			val = GLib.Value(GLib.Type.INVALID);
			var kind = type.get_interface().get_type();
			switch (kind) {
				case GI.InfoType.ENUM:
					val = GLib.Value(typeof(int));
					val.set_int(0);
					return true;

				case GI.InfoType.FLAGS:
					val = GLib.Value(typeof(uint));
					val.set_uint(0);
					return true;

				case GI.InfoType.OBJECT:
				case GI.InfoType.INTERFACE:
					GLib.Object? token = null;
					if (!this.mint_object_lease(type, out token)) {
						return false;
					}
					if (token != null) {
						this.request.connection.export(token);
						val = OLLMrpc.val("o", token);
					}
					return true;

				case GI.InfoType.STRUCT:
				case GI.InfoType.BOXED:
				case GI.InfoType.UNION:
					size_t n = 0;
					if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
						var si = (GI.StructInfo) type.get_interface();
						if (!si.is_gtype_struct()) {
							n = si.get_size();
						}
					}
					if (kind == GI.InfoType.UNION) {
						n = ((GI.UnionInfo) type.get_interface()).get_size();
					}
					if (n == 0) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var copy = new uint8[n];
					val = GLib.Value(typeof(GLib.Bytes));
					val.set_boxed(new GLib.Bytes(copy));
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}

		private bool mock_empty_array(GI.TypeInfo type, out GLib.Value val)
		{
			val = GLib.Value(GLib.Type.INVALID);
			var elem = type.get_param_type(0);
			var n_arr = type.get_array_fixed_size();
			if (n_arr < 0 && type.is_zero_terminated()
				&& (elem.get_tag() == GI.TypeTag.UTF8
					|| elem.get_tag() == GI.TypeTag.FILENAME)) {
				val = new GLib.Variant("as", new string[] {});
				return true;
			}
			if (n_arr < 0) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return false;
			}
			switch (elem.get_tag()) {
				case GI.TypeTag.INT32:
					val = GLib.Variant.new_fixed_array(
						new GLib.VariantType("i"),
						new int[n_arr], sizeof(int));
					return true;

				case GI.TypeTag.UINT32:
					val = GLib.Variant.new_fixed_array(
						new GLib.VariantType("u"),
						new uint[n_arr], sizeof(uint));
					return true;

				case GI.TypeTag.INT64:
					val = GLib.Variant.new_fixed_array(
						new GLib.VariantType("x"),
						new int64[n_arr], sizeof(int64));
					return true;

				case GI.TypeTag.UINT64:
					val = GLib.Variant.new_fixed_array(
						new GLib.VariantType("t"),
						new uint64[n_arr], sizeof(uint64));
					return true;

				case GI.TypeTag.FLOAT:
					val = GLib.Variant.new_fixed_array(
						new GLib.VariantType("f"),
						new float[n_arr], sizeof(float));
					return true;

				case GI.TypeTag.DOUBLE:
					val = GLib.Variant.new_fixed_array(
						new GLib.VariantType("d"),
						new double[n_arr], sizeof(double));
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}
	}
}
