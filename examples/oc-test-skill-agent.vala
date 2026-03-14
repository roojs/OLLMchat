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
 * Extends TestAppBase for standard debug options, log handling, and help.
 */
class TestSkillAgentApp : TestAppBase
{
	private static string? opt_project = null;
	private static string? opt_prompt = null;
	private static string? opt_input = null;
	private static string? opt_input_refine = null;
	private static string? opt_test_output = null;
	private static string? opt_task_list = null;
	private static string? opt_current_file = null;
	private static string? opt_run = null;
	private static int opt_step = 0;
	private static int opt_task_num = 0;
	private static bool opt_enable_file_scan = false;
	private static string? opt_session = null;
	private static bool opt_interactive = false;
	private static int opt_auto = -1;

	/** Set by build_runner() when a mode needs project + Runner. */
	private OLLMcoder.Skill.Runner? runner { get; set; default = null; }

	/** Loaded session from JSON; set by load_session() for replay. */
	private OLLMchat.History.SessionJson? session { get; set; default = null; }

	/** Current command line; set in run_test() for the duration of the run. */
	private ApplicationCommandLine? cl { get; set; default = null; }

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS]

Testable step-by-step usage of the skills agent flow. Requires --run MODE and --project PATH.

Options:
  -d, --debug                 Enable debug output
  -E, --enable-file-scan       Enable initial project file scan (default: disabled)
  --session FILE              Load session from JSON for replay (no LLM calls)
  --interactive                Replay: press Enter before each parse step
  --auto N                     Replay: run up to N parse steps then stop

Examples:
  {ARG} --run prompt --project=/path/to/project --prompt \"Add a README\"
  {ARG} --debug --run parse-tasklist --project=/path --test-output=llm.txt
  {ARG} --run replay --project=/path --session=history/session.json
  {ARG} --run replay --project=/path --session=session.json --interactive
  {ARG} --run replay --project=/path --session=session.json --auto 3
"""; }

	public TestSkillAgentApp()
	{
		base("org.roojs.oc-test-skill-agent");
	}

	protected override string get_app_name()
	{
		return "oc-test-skill-agent";
	}

	private const OptionEntry[] local_options = {
		{ "project", 0, 0, OptionArg.STRING, ref opt_project, 
			"Project path (required for prompt/refine/execute)", "PATH" },
		{ "prompt", 0, 0, OptionArg.STRING, ref opt_prompt, 
			"User prompt (required for prompt / prompt-run)", "TEXT" },
		{ "model", 'm', 0, OptionArg.STRING, ref opt_model, 
			"Model ID (overrides default)", "ID" },
		{ "input", 'i', 0, OptionArg.FILENAME, ref opt_input, 
			"Task list file (for refine/execute/iteration)", "FILE" },
		{ "input-refine", 0, 0, OptionArg.FILENAME, ref opt_input_refine, 
			"Refinement output file (required for execute-prompt and execute)", "FILE" },
		{ "test-output", 0, 0, OptionArg.FILENAME, ref opt_test_output,
			"LLM output file to parse (parse-tasklist|parse-refine|parse-execute)", "FILE" },
		{ "task-list", 0, 0, OptionArg.FILENAME, ref opt_task_list,
			"Task list file (required for parse-refine and parse-execute)", "FILE" },
		{ "current-file", 0, 0, OptionArg.FILENAME, ref opt_current_file, 
			"Current/open file path (within project); if omitted, no file is active", "FILE" },
		{ "run", 'r', 0, OptionArg.STRING, ref opt_run,
		 "Mode: prompt|prompt-run|parse-tasklist|parse-refine|parse-execute|refine-prompt|refine|execute-prompt|execute|iteration-prompt|iteration|replay", "MODE" },
		{ "enable-file-scan", 'E', 0, OptionArg.NONE, ref opt_enable_file_scan,
		 "Enable initial project file scan (default: disabled)", null },
		{ "step", 0, 0, OptionArg.INT, ref opt_step, "Step index (default 0)", "N" },
		{ "task-num", 0, 0, OptionArg.INT, ref opt_task_num, "Task index within step (default 0)", "N" },
		{ "session", 0, 0, OptionArg.FILENAME, ref opt_session,
			"Session JSON file for replay (--run replay); no LLM calls", "FILE" },
		{ "interactive", 0, 0, OptionArg.NONE, ref opt_interactive,
			"Replay: press Enter to run next parse step", null },
		{ "auto", 0, 0, OptionArg.INT, ref opt_auto,
			"Replay: run up to N parse steps then stop (for bug testing)", "N" },
		{ null }
	};

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		// Only include debug and debug-critical from base_options
		var base_opts = new OptionEntry[3];
		base_opts[0] = base_options[0];  // debug option
		base_opts[1] = base_options[1];  // debug-critical option
		base_opts[2] = { null };
		opt_context.add_main_entries(base_opts, null);

		var app_group = new OptionGroup("oc-test-skill-agent", "Skills agent test options", "Show oc-test-skill-agent options");
		app_group.add_entries(local_options);
		opt_context.add_group(app_group);

		return opt_context;
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
		this.cl = command_line;
		opt_run = opt_run == null ? "" : opt_run;
		if (opt_run == "") {
			this.cl.printerr("--run MODE is required. See --help for modes.\n");
			return;
		}
		if (opt_run != "replay" && (opt_project == null || opt_project == "")) {
			throw new GLib.IOError.INVALID_ARGUMENT("--project PATH is required");
		}
		if (opt_run == "replay" && (opt_project == null || opt_project == "")) {
			throw new GLib.IOError.INVALID_ARGUMENT("--run replay requires --project PATH");
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
				var list = this.runner.pending;
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
				this.runner.sr_factory.skill_manager.scan();
				var list = this.runner.pending;
				var skill_issues = list.validate_skills();
				if (skill_issues != "") {
					this.cl.printerr("%s", skill_issues);
					throw new GLib.IOError.INVALID_ARGUMENT(skill_issues.strip());
				}
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
				var tpl = this.runner.iteration_prompt("", this.runner.pending, "");
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
				result_parser.parse_task_list_iteration();
				if (result_parser.issues != "") {
					this.cl.printerr("Iteration parse issues: %s\n", result_parser.issues);
					return;
				}
				var new_list = this.runner.pending;
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
				var list = this.runner.pending;
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
				var list = this.runner.pending;
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
				foreach (var ex in detail.exec_runs) {
					stdout.printf("%s", ex.summary.to_markdown_with_content());
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
				var list = this.runner.pending;
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
				detail.build_exec_runs();
				yield detail.run_exec();
				foreach (var ex in detail.exec_runs) {
					stdout.printf("%s", ex.summary.to_markdown_with_content());
					
				}
				return;
			}
			case "replay": {
				if (opt_session == null || opt_session == "") {
					throw new GLib.IOError.INVALID_ARGUMENT("--run replay requires --session FILE");
				}
				yield this.run_replay();
				return;
			}
			default:
				this.cl.printerr("Unknown --run mode: %s. Use --help for modes.\n", opt_run);
				return;
		}
	}

	private async void build_runner(string project_path_override = "") throws Error
	{
		var project_path = project_path_override != "" ? project_path_override : (opt_project ?? "");
		var db_path = GLib.Path.build_filename(this.data_dir, "files.sqlite");
		var db = new SQ.Database(db_path, false);
		var project_manager = new OLLMfiles.ProjectManager(db);
		project_manager.disable_initial_scan = !opt_enable_file_scan;
		if (!opt_enable_file_scan) {
			this.cl.printerr("oc-test-skill-agent: initial file scan disabled (use -E or --enable-file-scan to enable).\n");
		}
		yield project_manager.load_projects_from_db();

		if (project_path == "") {
			this.cl.printerr("Project path required (--project PATH or session with project_path set).\n");
			throw new GLib.IOError.INVALID_ARGUMENT("Project path required");
		}
		var project = project_manager.projects.path_map.get(project_path);
		if (project == null) {
			this.cl.printerr("Project not found: %s\n", project_path);
			throw new GLib.IOError.NOT_FOUND("Project not found: " + project_path);
		}
		yield project.load_files_from_db();
		OLLMfiles.Folder.background_recurse = false;
		
		yield project_manager.activate_project(project);
		project.project_files.update_from(project);
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
		// Fetch model details (sets model_obj so Agent.Base can enable think/stream from capabilities)
		yield session.model_usage.verify_model(this.config);
		// Register tools so execute/refine can validate and run tool calls (e.g. codebase_search)
		var vector_registry = new OLLMvector.Registry();
		vector_registry.init_config();
		vector_registry.setup_config_defaults(history_manager.config);
		vector_registry.fill_tools(history_manager, project_manager);
		var codebase_tool = history_manager.tools.get("codebase_search") as OLLMvector.Tool.CodebaseSearchTool;
		if (codebase_tool != null) {
			try {
				yield codebase_tool.init_databases(history_manager.config, this.data_dir);
			} catch (GLib.Error e) {
				this.cl.printerr("Warning: codebase_search init_databases failed: %s (tool registered but search will fail)\n", e.message);
			}
		}
		this.runner = (OLLMcoder.Skill.Runner) factory.create_agent(session);
		this.runner.sr_factory.skill_manager.scan();
		var chat = this.runner.chat();
		GLib.debug("oc-test-skill-agent: chat stream=%s think=%s", chat.stream.to_string(), chat.think.to_string());
		var last_was_thinking = false;
		var first_chunk = true;
		chat.stream_chunk.connect((new_text, is_thinking, _response) => {
			if (new_text.length == 0) {
				return;
			}
			if (first_chunk) {
				first_chunk = false;
				this.cl.printerr(is_thinking ? "\nThinking...\n" : "\nContent...\n");
				this.cl.printerr("%s", new_text);
				last_was_thinking = is_thinking;
				return;
			}
			if (is_thinking != last_was_thinking) {
				this.cl.printerr(is_thinking ? "\nThinking...\n" : "\nContent...\n");
			}
			this.cl.printerr("%s", new_text);
			last_was_thinking = is_thinking;
		});
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

	/**
	 * Load session JSON from path and set this.session. Callers use this.session (e.g. project_path, messages) and content_list() for the replay content list.
	 * On error prints to stderr and exits.
	 */
	private void load_session(string path)
	{
		if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
			this.cl.printerr("Session file not found: %s\n", path);
			Process.exit(1);
		}
		string data;
		try {
			GLib.FileUtils.get_contents(path, out data);
		} catch (GLib.FileError e) {
			this.cl.printerr("Failed to read session file: %s\n", e.message);
			Process.exit(1);
		}
		var parser = new Json.Parser();
		try {
			parser.load_from_data(data, -1);
		} catch (GLib.Error e) {
			this.cl.printerr("Failed to parse session JSON: %s\n", e.message);
			Process.exit(1);
		}
		var root = parser.get_root();
		if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
			this.cl.printerr("Session JSON root is not an object\n");
			Process.exit(1);
		}
		var json_session = Json.gobject_deserialize(typeof(OLLMchat.History.SessionJson), root) as OLLMchat.History.SessionJson;
		if (json_session == null) {
			this.cl.printerr("Failed to deserialize session JSON\n");
			Process.exit(1);
		}
		this.session = json_session;
	}

	private async void run_replay()
	{
		this.load_session(opt_session);
		this.cl.printerr("Replay from %s (%d messages)\n", opt_session, (int) this.session.messages.size);
		var project_path = this.session.project_path != "" ? this.session.project_path : opt_project;
		if (project_path == null || project_path == "") {
			this.cl.printerr("Replay requires --project PATH or a session with project_path set.\n");
			Process.exit(1);
		}
		try {
			yield this.build_runner(project_path ?? "");
		} catch (GLib.Error e) {
			this.cl.printerr("%s\n", e.message);
			Process.exit(1);
		}
		try {
			yield this.runner.run_replay_from_messages(this.session.messages);
		} catch (GLib.Error e) {
			this.cl.printerr("Replay failed: %s\n", e.message);
			Process.exit(1);
		}
		this.cl.printerr("Replay done.\n");
	}

	public static int main(string[] args)
	{
		var app = new TestSkillAgentApp();
		return app.run(args);
	}
}
