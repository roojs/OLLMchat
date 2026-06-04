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

namespace OLLMfilesd.Rpc
{
	/** Server-side request: dispatch into {@link OLLMfilesd.Listen} RPC targets. */
	public class Request : OLLMfiles.Rpc.Request
	{
		public OLLMfilesd.Session session { get; set; }

		private bool has_id = false;

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			if (pspec.get_name() == "id") {
				this.has_id = true;
			}
			base.set_property(pspec.get_name(), value);
		}

		public void dispatch()
		{
			if (!this.has_id
				|| this.jsonrpc != "2.0"
				|| this.method.length == 0) {
				GLib.error("RPC dispatch: invalid JSON-RPC request");
			}

			var dot = this.method.index_of_char('.');
			if (dot < 1 || dot == this.method.length - 1) {
				GLib.error(
					"RPC dispatch: method must be Object.method, got '%s'",
					this.method
				);
			}

			var object_name = this.method[0:dot];
			var method_name = this.method.substring(dot + 1);

			if (object_name == "event") {
				GLib.error(
					"RPC dispatch: clients must not call event.* (got %s)",
					this.method
				);
			}

			var pspec = this.session.listen.get_class().find_property(object_name);
			if (pspec == null) {
				GLib.error(
					"RPC dispatch: no Listen property '%s' for %s",
					object_name,
					this.method
				);
			}

			var val = GLib.Value(pspec.value_type);
			this.session.listen.get_property(object_name, ref val);
			var target = val.get_object();
			if (target == null) {
				GLib.error(
					"RPC dispatch: Listen.%s is null for %s",
					object_name,
					this.method
				);
			}

			var signal_name = "rpc_" + method_name.replace(".", "_");
			var signal_id = GLib.Signal.lookup(signal_name, target.get_type());
			if (signal_id == 0) {
				GLib.error(
					"RPC dispatch: no signal %s on %s for %s",
					signal_name,
					object_name,
					this.method
				);
			}

			GLib.Signal.emit_by_name(target, signal_name, this);
		}
	}
}
