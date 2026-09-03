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
	 * {@link Gi} subclass — GIR lookup with typed empty replies.
	 *
	 * Inherits wire resolution and {@link skip_wire} rules from
	 * {@link Gi.dispatch}. Overrides {@link dispatch_new} and
	 * {@link dispatch_function} only — no {@link GI.FunctionInfo.invoke}.
	 * Call {@link Gi.register} before use. Used when
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
		public GiMock(Request request)
		{
			GLib.Object(request: request);
		}

		protected override bool dispatch_new(GI.FunctionInfo fn)
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
			var token = new GLib.Object();
			this.request.connection.export(token);
			this.request.reply(new Response() {
				retval = OLLMrpc.val("o", token)
			});
			return true;
		}

		protected override bool dispatch_function(GI.FunctionInfo fn)
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
					if (type.is_pointer()) {
						return true;
					}
					var token = new GLib.Object();
					this.request.connection.export(token);
					val = OLLMrpc.val("o", token);
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
