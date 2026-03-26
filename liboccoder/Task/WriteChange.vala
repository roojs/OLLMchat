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

namespace OLLMcoder.Task
{
	/**
	 * One write operation from write-executor output (Change details).
	 *
	 * Phase 5: type shell implementing ``Json.Serializable`` only so ``Tool.writes`` and
	 * ``foreach (... exec ...)`` compile. No payload fields on this type in Phase 5.
	 *
	 * Phase 8: replace this file's body with GObject properties, serialization, markdown
	 * parsing in {@link ResultParser.exec_extract}, and a real {@link exec} implementation
	 * ([1.23.48](1.23.48-refine-stage-reference-injection-phase-8.md)). The final ``exec``
	 * will not match any speculative ``write_file`` / ``ToolCall`` sketch from earlier drafts.
	 */
	public class WriteChange : GLib.Object, Json.Serializable
	{
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

		/**
		 * Builds ``write_file`` call JSON from this object's fields and executes the tool.
		 *
		 * @param run execution {@link Tool}
		 */
		public async void exec (Tool run) throws GLib.Error
		{
			// to be compleded in phase8 
			var impl = run.parent.runner.session.manager.tools.get("write_file")
				as OLLMchat.Tool.BaseTool;
			
			var args = new Json.Object();
			var func = new OLLMchat.Response.CallFunction.with_values("write_file", args);
			var tc = new OLLMchat.Response.ToolCall.with_values("fake-write-id", func);
			run.tool_run_result = yield impl.execute(run.chat(), tc, true);
		}
	}
}
