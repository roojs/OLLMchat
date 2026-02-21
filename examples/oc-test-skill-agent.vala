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
 */

class TestSkillAgentApp : Application, OLLMchat.ApplicationInterface
{
	private static string? opt_project = null;
	private static string? opt_prompt = null;
	private static string? opt_model = null;
	private static string? opt_input = null;
	private static string? opt_input_refine = null;
	private static string? opt_test_output = null;
	private static string? opt_task_list = null;
	private static string? opt_current_file = null;
	private static string? opt_run = null;
	private static int opt_step = 0;
	private static int opt_task_num = 0;

	public OLLMchat.Settings.Config2 config { get; set; }
	public string data_dir { get; set; }

	/** Set by build_runner() when a mode needs project + Runner. */
	private OLLMcoder.Skill.Runner? runner { get; set; default = null; }

	/** Current command line; set in command_line() for the duration of the run. */
	private GLib.ApplicationCommandLine? cl { get; set; default = null; }

	const GLib.OptionEntry[] options = {
		{ "project", 0, 0, GLib.OptionArg.STRING, ref opt_project, 
			"Project path (required for prompt/refine/execute)", "PATH" },
		{ "prompt", 0, 0, GLib.OptionArg.STRING, ref opt_prompt, 
			"User prompt (required for prompt / prompt-run)", "TEXT" },
		{ "model", 'm', 0, GLib.OptionArg.STRING, ref opt_model, 
			"Model ID (overrides default)", "ID" },
		{ "input", 'i', 0, GLib.OptionArg.FILENAME, ref opt_input, 
			"Task list file (for refine/execute/iteration)", "FILE" },
		{ "input-refine", 0, 0, GLib.OptionArg.FILENAME, ref opt_input_refine, 
			"Refinement output file (required for execute-prompt and execute)", "FILE" },
		{ "test-output", 0, 0, GLib.OptionArg.FILENAME, ref opt_test_output,
			"LLM output file to parse (parse-tasklist|parse-refine|parse-execute)", "FILE" },
		{ "task-list", 0, 0, GLib.OptionArg.FILENAME, ref opt_task_list,
			"Task list file (required for parse-refine and parse-execute)", "FILE" },
		{ "current-file", 0, 0, GLib.OptionArg.FILENAME, ref opt_current_file, 
			"Current/open file path (within project); if omitted, no file is active", "FILE" },
		{ "run", 'r', 0, GLib.OptionArg.STRING, ref opt_run,
		 "Mode: prompt|prompt-run|parse-tasklist|parse-refine|parse-execute|refine-prompt|refine|execute-prompt|execute|iteration-prompt|iteration", "MODE" },
		{ "step", 0, 0, GLib.OptionArg.INT, ref opt_step, "Step index (default 0)", "N" },
		{ "task-num", 0, 0, GLib.OptionArg.INT, ref opt_task_num, "Task index within step (default 0)", "N" },
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

	protected override int command_line(GLib.ApplicationCommandLine command_line)
	{
		opt_project = null;
		opt_prompt = null;
		opt_model = null;
		opt_input = null;
		opt_input_refine = null;
		opt_test_output = null;
		opt_task_list = null;
		opt_current_file = null;
		opt_run = null;
		opt_step = 0;
		opt_task_num = 0;
		this.cl = command_line;

		string[] args = command_line.get_arguments();
		var opt_context = new GLib.OptionContext("oc-test-skill-agent — testable skills agent flow");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);

		try {
			unowned string[] unowned_args = args;
			opt_context.parse(ref unowned_args);
		} catch (GLib.OptionError e) {
			this.cl.printerr("error: %s\n", e.message);
			return 1;
		}

		// Determine mode and run
		this.hold();
		this.run_mode.begin((obj, res) => {
			try {
				this.run_mode.end(res);
			} catch (Error e) {
				this.cl.printerr("Error: %s\n", e.message);
			} finally {
				this.release();
				this.quit();
			}
		});
		return 0;
	}

	private async void build_runner() throws Error
	{
		var db_path = GLib.Path.build_filename(this.data_dir, "files.sqlite");
		var db = new SQ.Database(db_path, false);
		var project_manager = new OLLMfiles.ProjectManager(db);
		yield project_manager.load_projects_from_db();

		var project = project_manager.projects.path_map.get(opt_project);
		if (project == null) {
			this.cl.printerr("Project not found: %s\n", opt_project);
			throw new GLib.IOError.NOT_FOUND("Project not found: " + opt_project);
		}
		yield project.load_files_from_db();
		OLLMfiles.Folder.background_recurse = false;
		yield project.read_dir(new GLib.DateTime.now_local().to_unix(), true);
		project.project_files.update_from(project);
		yield project_manager.activate_project(project);
		project_manager.activate_file(null);
		if (opt_current_file != null && opt_current_file != "") {
			string path = GLib.Path.is_absolute(opt_current_file) ? opt_current_file : GLib.Path.build_filename(project.path, opt_current_file);
			var file = project_manager.get_file_from_active_project(path);
			if (file == null) {
				this.cl.printerr("File not in project: %s\n", path);
				throw new GLib.IOError.NOT_FOUND("File not in project: " + path);
			}
			project_manager.activate_file(file);
		} 

		var skills_dirs = new Gee.ArrayList<string>();
		skills_dirs.add(GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), "gitlive", "OLLMchat", "resources", "skills"));
		var factory = new OLLMcoder.Skill.Factory(project_manager, skills_dirs, "");
		var history_manager = new OLLMchat.History.Manager(this);
		var session = new OLLMchat.History.EmptySession(history_manager);
		if (opt_model != null && opt_model != "") {
			var default_usage = history_manager.default_model_usage;
			var override_usage = new OLLMchat.Settings.ModelUsage() {
				connection = default_usage.connection,
				model = opt_model,
				model_obj = null,
				options = default_usage.options.clone()
			};
			session.activate_model(override_usage);
		}
		this.runner = (OLLMcoder.Skill.Runner) factory.create_agent(session);
	}

	private void load_task_list(string path) throws GLib.Error
	{
		if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
			this.cl.printerr("File not found: %s\n", path);
			throw new GLib.IOError.NOT_FOUND("File not found: " + path);
		}
		string content;
		GLib.FileUtils.get_contents(path, out content);
		var parser = new OLLMcoder.Task.ResultParser(this.runner, content);
		parser.parse_task_list();
		if (parser.issues != "") {
			this.cl.printerr("Parse issues: %s\n", parser.issues);
			throw new GLib.IOError.INVALID_ARGUMENT(parser.issues);
		}
	}

	private void load_refinement(string path, OLLMcoder.Task.Details detail) throws GLib.Error
	{
		if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
			this.cl.printerr("Refinement file not found: %s\n", path);
			throw new GLib.IOError.NOT_FOUND("File not found: " + path);
		}
		string content;
		GLib.FileUtils.get_contents(path, out content);
		var parser = new OLLMcoder.Task.ResultParser(this.runner, content);
		parser.extract_refinement(detail);
		if (parser.issues != "") {
			this.cl.printerr("Refinement parse issues: %s\n", parser.issues);
			throw new GLib.IOError.INVALID_ARGUMENT(parser.issues);
		}
	}

	private async void run_mode() throws Error
	{
		opt_run = opt_run == null ? "" : opt_run;
		if (opt_run == "") {
			this.cl.printerr("--run MODE is required. See --help for modes.\n");
			return;
		}
		if (opt_project == null || opt_project == "") {
			throw new GLib.IOError.INVALID_ARGUMENT("--project PATH is required");
		}

		switch (opt_run) {
			case "prompt":
				if (opt_prompt == null || opt_prompt == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run prompt requires --prompt");
				}
				yield this.build_runner();
				var tpl = this.runner.task_creation_prompt(opt_prompt, "", "",
					this.runner.sr_factory.skill_manager, this.runner.sr_factory.project_manager);
				stdout.printf("=== system ===\n%s\n=== user ===\n%s\n", tpl.filled_system, tpl.filled_user);
				return;
			case "prompt-run":
				if (opt_prompt == null || opt_prompt == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run prompt-run requires --prompt");
				}
				yield this.build_runner();
				var tpl = this.runner.task_creation_prompt(opt_prompt, "", "",
					this.runner.sr_factory.skill_manager, this.runner.sr_factory.project_manager);
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_obj = yield this.runner.chat().send(messages, null);
				var content = response_obj != null && response_obj.message != null ? response_obj.message.content : "";
				stdout.printf("%s", content);
				return;
			case "parse-tasklist":
				if (opt_test_output == null || opt_test_output == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run parse-tasklist requires --test-output FILE (task list creation LLM output)");
				}
				yield this.build_runner();
				this.load_task_list(opt_test_output);
				var list = this.runner.task_list;
				stdout.printf("Steps: %d\n", (int) list.steps.size);
				int task_index = 0;
				foreach (var step in list.steps) {
					stdout.printf("  Step: %d tasks\n", (int) step.children.size);
					foreach (var t in step.children) {
						task_index++;
						var skill = t.task_data.has_key("Skill") ?
							t.task_data.get("Skill").to_markdown().strip() : "";
						var needed = t.task_data.has_key("What is needed") ?
							t.task_data.get("What is needed").to_markdown().strip() : "";
						stdout.printf("    Task %d: skill=%s  What is needed: %s\n",
							task_index, skill, needed.replace("\n", " "));
					}
				}
				return;
			case "refine-prompt":
			case "refine": {
				if (opt_input == null || opt_input == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run refine-prompt / refine requires --input FILE (task list)");
				}
				yield this.build_runner();
				this.load_task_list(opt_input);
				var list = this.runner.task_list;
				if (opt_step < 0 || opt_step >= (int) list.steps.size) {
					this.cl.printerr("Step %d out of range (0..%d).\n", opt_step, (int) list.steps.size - 1);
					throw new GLib.IOError.NOT_FOUND("Step out of range");
				}
				var step = list.steps.get(opt_step);
				if (opt_task_num < 0 || opt_task_num >= (int) step.children.size) {
					this.cl.printerr("Task %d out of range (0..%d).\n", opt_task_num, (int) step.children.size - 1);
					throw new GLib.IOError.NOT_FOUND("Task out of range");
				}
				var detail = step.children.get(opt_task_num);
				var tpl = detail.refinement_prompt();
				if (opt_run != "refine") {
					stdout.printf("=== system ===\n%s\n=== user ===\n%s\n", 
						tpl.filled_system, tpl.filled_user);
					return;
				}
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_obj = yield this.runner.chat().send(messages, null);
				stdout.printf("%s", response_obj != null && response_obj.message != null ?
					 response_obj.message.content : "");
				return;
			}
			case "iteration-prompt":
			case "iteration": {
				if (opt_input == null || opt_input == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run iteration-prompt / iteration requires --input FILE (task list)");
				}
				yield this.build_runner();
				this.load_task_list(opt_input);
				var tpl = this.runner.iteration_prompt("");
				if (opt_run == "iteration-prompt") {
					stdout.printf("=== system ===\n%s\n=== user ===\n%s\n", tpl.filled_system, tpl.filled_user);
					return;
				}
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_obj = yield this.runner.chat().send(messages, null);
				var response_text = response_obj != null && response_obj.message != null ?
					 response_obj.message.content : "";
				var result_parser = new OLLMcoder.Task.ResultParser(this.runner, response_text);
				result_parser.parse_task_list();
				if (result_parser.issues != "") {
					this.cl.printerr("Iteration parse issues: %s\n", result_parser.issues);
					return;
				}
				var new_list = this.runner.task_list;
				stdout.printf("Steps: %d\n", (int) new_list.steps.size);
				int task_count = 0;
				foreach (var step in new_list.steps) {
					task_count += (int) step.children.size;
				}
				stdout.printf("Tasks: %d\n", task_count);
				if (new_list.goals_summary_md != "") {
					stdout.printf("Goals summary: %s\n", new_list.goals_summary_md.strip().replace("\n", " "));
				}
				stdout.printf("%s", response_text);
				return;
			}
			case "parse-refine": {
				if (opt_test_output == null || opt_test_output == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run parse-refine requires --test-output FILE (refinement LLM output)");
				}
				if (!GLib.FileUtils.test(opt_test_output, GLib.FileTest.EXISTS)) {
					this.cl.printerr("Refinement file not found: %s\n", opt_test_output);
					throw new GLib.IOError.NOT_FOUND("File not found: " + opt_test_output);
				}
				if (opt_task_list == null || opt_task_list == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run parse-refine requires --task-list FILE (task list)");
				}
				yield this.build_runner();
				this.load_task_list(opt_task_list);
				var list = this.runner.task_list;
				if (opt_step < 0 || opt_step >= (int) list.steps.size) {
					this.cl.printerr("Step %d out of range (0..%d).\n", opt_step, (int) list.steps.size - 1);
					throw new GLib.IOError.NOT_FOUND("Step out of range");
				}
				var step = list.steps.get(opt_step);
				if (opt_task_num < 0 || opt_task_num >= (int) step.children.size) {
					this.cl.printerr("Task %d out of range (0..%d).\n", opt_task_num, (int) step.children.size - 1);
					throw new GLib.IOError.NOT_FOUND("Task out of range");
				}
				var detail = step.children.get(opt_task_num);
				string content;
				GLib.FileUtils.get_contents(opt_test_output, out content);
				var parser = new OLLMcoder.Task.ResultParser(this.runner, content);
				parser.extract_refinement(detail);
				if (parser.issues != "") {
					this.cl.printerr("Refinement parse issues: %s\n", parser.issues);
				}
				stdout.printf("Tools: %d\n", (int) detail.tools.size);
				stdout.printf("Code blocks: %d\n", (int) detail.code_blocks.size);
				return;
			}
			case "parse-execute": {
				if (opt_test_output == null || opt_test_output == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run parse-execute requires --test-output FILE (executor LLM output)");
				}
				if (!GLib.FileUtils.test(opt_test_output, GLib.FileTest.EXISTS)) {
					this.cl.printerr("Executor output file not found: %s\n", opt_test_output);
					throw new GLib.IOError.NOT_FOUND("File not found: " + opt_test_output);
				}
				if (opt_task_list == null || opt_task_list == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run parse-execute requires --task-list FILE (task list)");
				}
				yield this.build_runner();
				this.load_task_list(opt_task_list);
				var list = this.runner.task_list;
				if (opt_step < 0 || opt_step >= (int) list.steps.size) {
					this.cl.printerr("Step %d out of range (0..%d).\n", opt_step, (int) list.steps.size - 1);
					throw new GLib.IOError.NOT_FOUND("Step out of range");
				}
				var step = list.steps.get(opt_step);
				if (opt_task_num < 0 || opt_task_num >= (int) step.children.size) {
					this.cl.printerr("Task %d out of range (0..%d).\n", opt_task_num, (int) step.children.size - 1);
					throw new GLib.IOError.NOT_FOUND("Task out of range");
				}
				var detail = step.children.get(opt_task_num);
				string content;
				GLib.FileUtils.get_contents(opt_test_output, out content);
				var parser = new OLLMcoder.Task.ResultParser(this.runner, content);
				parser.extract_exec(detail);
				if (parser.issues != "") {
					this.cl.printerr("Executor parse issues: %s\n", parser.issues);
				}
				if (detail.result != "") {
					stdout.printf("%s", detail.result);
				}
				return;
			}
			case "execute-prompt":
			case "execute": {
				if (opt_input == null || opt_input == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run execute-prompt / execute requires --input FILE (task list)");
				}
				if (opt_input_refine == null || opt_input_refine == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run execute-prompt / execute requires --input-refine FILE (refinement output)");
				}
				yield this.build_runner();
				this.load_task_list(opt_input);
				var list = this.runner.task_list;
				if (opt_step < 0 || opt_step >= (int) list.steps.size) {
					this.cl.printerr("Step %d out of range (0..%d).\n", opt_step, (int) list.steps.size - 1);
					throw new GLib.IOError.NOT_FOUND("Step out of range");
				}
				var step = list.steps.get(opt_step);
				if (opt_task_num < 0 || opt_task_num >= (int) step.children.size) {
					this.cl.printerr("Task %d out of range (0..%d).\n", opt_task_num, (int) step.children.size - 1);
					throw new GLib.IOError.NOT_FOUND("Task out of range");
				}
				var detail = step.children.get(opt_task_num);
				this.load_refinement(opt_input_refine, detail);
				yield detail.run_tools();
				var tpl = detail.executor_prompt();
				if (opt_run == "execute-prompt") {
					stdout.printf("=== system ===\n%s\n=== user ===\n%s\n", tpl.filled_system, tpl.filled_user);
					return;
				}
				var messages = new Gee.ArrayList<OLLMchat.Message>();
				messages.add(new OLLMchat.Message("system", tpl.filled_system));
				messages.add(new OLLMchat.Message("user", tpl.filled_user));
				var response_obj = yield this.runner.chat().send(messages, null);
				var response_text = response_obj != null && response_obj.message != null ?
					 response_obj.message.content : "";
				var result_parser = new OLLMcoder.Task.ResultParser(this.runner, response_text);
				result_parser.extract_exec(detail);
				if (result_parser.issues != "") {
					this.cl.printerr("Executor parse issues: %s\n", result_parser.issues);
				}
				if (detail.result != "") {
					stdout.printf("%s", detail.result);
				} else {
					stdout.printf("%s", response_text);
				}
				return;
			}
			default:
				this.cl.printerr("Unknown --run mode: %s. Use --help for modes.\n", opt_run);
				return;
		}
	}

	public static int main(string[] args)
	{
		var app = new TestSkillAgentApp();
		return app.run(args);
	}
}
