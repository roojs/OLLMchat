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
 * oc-test-skill-agent — testable step-by-step usage of the skills agent flow.
 *
 * Plan: docs/plans/1.23.19-testable-agent-flow.md
 *
 * NOT in build: add to examples/meson.build when ready.
 */

class TestSkillAgentApp : Application, OLLMchat.ApplicationInterface
{
	private static string? opt_project = null;
	private static string? opt_prompt = null;
	private static string? opt_model = null;
	private static bool opt_run_prompt = false;
	private static string? opt_parse_tasklist = null;
	private static string? opt_parse_refine = null;
	private static string? opt_parse_execute = null;
	private static int opt_refine_task = -1;
	private static bool opt_run_refine = false;
	private static string? opt_execute_task = null;  // N or FILE
	private static int opt_run_execute_task_n = -1;

	public OLLMchat.Settings.Config2 config { get; set; }
	public string data_dir { get; set; }

	const OptionEntry[] options = {
		{ "project", 0, 0, OptionArg.STRING, ref opt_project, "Project path (required for prompt modes)", "PATH" },
		{ "prompt", 0, 0, OptionArg.STRING, ref opt_prompt, "User prompt (required for task-creation modes)", "TEXT" },
		{ "model", 'm', 0, OptionArg.STRING, ref opt_model, "Model ID (overrides default)", "ID" },
		{ "run-prompt", 0, 0, OptionArg.NONE, ref opt_run_prompt, "Run task-creation prompt with model; print response", null },
		{ "parse-tasklist", 0, 0, OptionArg.FILENAME, ref opt_parse_tasklist, "Parse FILE as task-list output; print summary", "FILE" },
		{ "parse-refine", 0, 0, OptionArg.FILENAME, ref opt_parse_refine, "Parse FILE as refinement output; print summary", "FILE" },
		{ "parse-execute", 0, 0, OptionArg.FILENAME, ref opt_parse_execute, "Parse FILE as executor output; print summary", "FILE" },
		{ "refine-task", 0, 0, OptionArg.INT, ref opt_refine_task, "Output refinement prompt for task N (1-based)", "N" },
		{ "run-refine", 0, 0, OptionArg.NONE, ref opt_run_refine, "Run refinement for task N with LLM; print response", null },
		{ "execute-task", 0, 0, OptionArg.STRING, ref opt_execute_task, "Run execute-task tools; output executor prompt (N or FILE)", "N|FILE" },
		{ "run-execute-task", 0, 0, OptionArg.INT, ref opt_run_execute_task_n, "Run executor with LLM for task N; print results", "N" },
		{ null }
	};

	public TestSkillAgentApp()
	{
		Object(
			application_id: "org.roojs.oc-test-skill-agent",
			flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
		);
		this.data_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), ".local", "share", "ollmchat");
		this.config = this.load_config();
	}

	public OLLMchat.Settings.Config2 load_config()
	{
		return base_load_config();
	}

	protected override int command_line(ApplicationCommandLine command_line)
	{
		opt_project = null;
		opt_prompt = null;
		opt_model = null;
		opt_run_prompt = false;
		opt_parse_tasklist = null;
		opt_parse_refine = null;
		opt_parse_execute = null;
		opt_refine_task = -1;
		opt_run_refine = false;
		opt_execute_task = null;
		opt_run_execute_task_n = -1;

		string[] args = command_line.get_arguments();
		var opt_context = new OptionContext("oc-test-skill-agent — testable skills agent flow");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);

		try {
			unowned string[] unowned_args = args;
			opt_context.parse(ref unowned_args);
		} catch (OptionError e) {
			command_line.printerr("error: %s\n", e.message);
			return 1;
		}

		// Determine mode and run
		this.hold();
		this.run_mode.begin(command_line, (obj, res) => {
			try {
				this.run_mode.end(res);
			} catch (Error e) {
				command_line.printerr("Error: %s\n", e.message);
			} finally {
				this.release();
				this.quit();
			}
		});
		return 0;
	}

	private async void run_mode(ApplicationCommandLine cl) throws Error
	{
		// §3.1: output task-creation prompt (no LLM)
		if (!opt_run_prompt && opt_project != null && opt_prompt != null &&
		    opt_parse_tasklist == null && opt_parse_refine == null && opt_parse_execute == null &&
		    opt_refine_task < 0 && !opt_run_refine && opt_execute_task == null && opt_run_execute_task_n < 0) {
			// TODO: build Runner with --project, call build_task_creation_prompt(), print system + user
			cl.printerr("Not implemented: output task-creation prompt (requires Runner.build_task_creation_prompt API).\n");
			return;
		}

		// §3.2: run task-creation prompt
		if (opt_run_prompt) {
			if (opt_project == null || opt_prompt == null) {
				throw new GLib.IOError.INVALID_ARGUMENT("--run-prompt requires --project and --prompt");
			}
			// TODO: build prompt via Runner, send with --model or default, print response
			cl.printerr("Not implemented: --run-prompt (requires Runner.build_task_creation_prompt API).\n");
			return;
		}

		// §3.3: parse tasklist file
		if (opt_parse_tasklist != null) {
			// TODO: read file, minimal Runner + ResultParser, parse_task_list(), print summary
			cl.printerr("Not implemented: --parse-tasklist (requires minimal Runner + ProjectManager).\n");
			return;
		}

		// §3.3.1: parse refinement file
		if (opt_parse_refine != null) {
			// TODO: read file, ResultParser + minimal Details, extract_refinement(), print summary
			cl.printerr("Not implemented: --parse-refine.\n");
			return;
		}

		// §3.3.2: parse execute file
		if (opt_parse_execute != null) {
			// TODO: read file, ResultParser + minimal Details, extract_exec(), print summary
			cl.printerr("Not implemented: --parse-execute.\n");
			return;
		}

		// §3.4 / §3.5: refine-task N, run-refine N
		if (opt_refine_task >= 1 || opt_run_refine) {
			// TODO: task list in memory or from file; Details.get_refinement_prompt() or run LLM
			cl.printerr("Not implemented: --refine-task / --run-refine (requires Details refinement prompt API).\n");
			return;
		}

		// §3.6: execute-task
		if (opt_execute_task != null) {
			// TODO: run_tools(), then Details.get_executor_prompt(), print
			cl.printerr("Not implemented: --execute-task (requires Details executor prompt API).\n");
			return;
		}

		// §3.7: run-execute-task
		if (opt_run_execute_task_n >= 1) {
			cl.printerr("Not implemented: --run-execute-task.\n");
			return;
		}

		// No mode selected
		cl.printerr("No mode selected. Use --help for options.\n");
	}

	public static int main(string[] args)
	{
		var app = new TestSkillAgentApp();
		return app.run(args);
	}
}
