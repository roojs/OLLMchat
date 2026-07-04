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
	 * Base bag for JSON-RPC request arguments on {@link Request.param}.
	 *
	 * Daemon param types live in {{{ollmfilesd/CallParam.vala}}} and extend
	 * this class (e.g. {{{FolderParams}}}, {{{FileParams}}}). Add a wire field
	 * by adding a GObject property on the subclass — json-glib default
	 * {@link Json.Serializable} serializes and deserializes it; custom
	 * {@link Json.Serializable} overrides are not needed for ordinary
	 * {{{string}}}, {{{bool}}}, integer, or {{{string[]}}} fields.
	 *
	 * @see Request
	 */
	public class CallParam : GLib.Object, Json.Serializable, Bin.Serializable
	{
		/**
		 * Positional arguments for legacy or generic callers.
		 *
		 * Named object methods use properties on {@link CallParam} subclasses
		 * instead (see {@link Request} wire examples).
		 */
		public string[] args { get; set; default = new string[] {}; }

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}
	}
}
