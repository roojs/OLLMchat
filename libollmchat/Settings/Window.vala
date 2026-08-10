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

namespace OLLMchat.Settings
{
	/**
	 * Per-window open project, file, and agent persisted in
	 * {@link Config2}.
	 *
	 * Stored under the ''windows'' map keyed by UUID from
	 * ''GLib.Uuid.string_random()''. Runtime
	 * {@link OLLMfiles.ProjectManager} still holds live
	 * ''active_project'' / ''active_file'' objects; this type stores
	 * paths and agent factory id for restore. Not shown in the
	 * settings UI — no ''Description'' attributes.
	 *
	 * == Usage Examples ==
	 *
	 * === Code (seed on first run) ===
	 *
	 * {{{
	 * var id = GLib.Uuid.string_random();
	 * config.windows.set(id, new Window() {
	 *     project = "/home/user/project",
	 *     file = "",
	 *     agent = "agent-pi"
	 * });
	 * }}}
	 *
	 * === JSON (config.2.json) ===
	 *
	 * {{{
	 * "windows": {
	 *   "a3f1c9e2-b8d0-4f6a-9c1e-2d4b6a8c0e1f": {
	 *     "project": "/home/user/project",
	 *     "file": "",
	 *     "agent": "agent-pi"
	 *   }
	 * }
	 * }}}
	 */
	public class Window : Object, Json.Serializable
	{
		/**
		 * Absolute project path for this window (empty = none).
		 */
		public string project { get; set; default = ""; }

		/**
		 * Absolute open file path for this window (empty = none).
		 */
		public string file { get; set; default = ""; }

		/**
		 * Agent factory id in use (e.g. ''agent-pi'', ''just-ask'').
		 */
		public string agent { get; set; default = ""; }

		/**
		 * Default constructor.
		 */
		public Window()
		{
		}

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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}
