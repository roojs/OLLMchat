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

/**
 * Base for libocrpc smoke tests — extends {@link TestAppBase} for ''--debug''
 * and standard log handling. Subclasses implement {@link run_rpc_test}.
 */
public abstract class RpcTestAppBase : TestAppBase
{
	protected RpcTestAppBase(string application_id)
	{
		base(application_id);
	}

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var base_opts = new OptionEntry[3];
		base_opts[0] = base_options[0];
		base_opts[1] = base_options[1];
		base_opts[2] = { null };
		opt_context.add_main_entries(base_opts, null);
		return opt_context;
	}

	public override OLLMchat.Settings.Config2 load_config()
	{
		return new OLLMchat.Settings.Config2();
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		this.run_rpc_test(command_line);
	}

	protected abstract void run_rpc_test(ApplicationCommandLine command_line) throws Error;

	protected void fail(ApplicationCommandLine command_line, string message) throws Error
	{
		command_line.printerr("%s\n", message);
		throw new GLib.IOError.FAILED("%s", message);
	}

	protected void check(
		ApplicationCommandLine command_line,
		bool ok,
		string message
	) throws Error
	{
		if (!ok) {
			this.fail(command_line, message);
		}
	}
}
