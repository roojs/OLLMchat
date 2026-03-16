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

public enum MarkdownPhase
{
	COARSE,
	REFINEMENT,
	LIST,
	REFINE_COMPLETED,
	EXECUTION
}

/**
 * One task in the plan. Built from task list output; updated from
 * refinement output.
 *
 * Task list (input): each list item under a task section heading has a nested list
 * with labels ''What is needed'', ''Skill'', ''References'', ''Expected output''.
 * Links in References: current_file, paths, plan:...
 * Keys are exactly these labels (no other format accepted):
 * "What is needed", "Skill", "References", "Expected output",
 * "Requires user approval".
 *
 * Refined task (refinement output): section "Refined task" with same list plus
 * ''Skill call'' and an optional fenced code block. Parser uses
 * ListItem.to_key_map() for both; update_props(refined_map); code added
 * directly to code_blocks.
 *
 * Execution: after refinement, the runner calls build_exec_runs() then run_exec().
 * exec_runs holds one Tool per run; each Tool.run() runs the tool (if any)
 * then the LLM.
 * Summaries and documents live on each Tool in exec_runs.
 * (ex.document).
 */
public class Details : OLLMchat.Agent.Base
{
	// - stored task content (exact keys only, see class doc)
	/**
	 * Map from ListItem.to_key_map(); keys are exact labels only.
	 * All task content is read from here.
	 */
	public Gee.Map<string, Markdown.Document.Block> task_data {
		get; set; default = new Gee.HashMap<string, Markdown.Document.Block>(); }

	/**
	 * True when this task should gate execution (e.g. modifies files);
	 * from task list format.
	 */
	public bool requires_user_approval { get; set; default = false; }

	/**
	 * True after run_exec success; exec_runs then hold summaries and documents.
	 */
	public bool exec_done { get; set; default = false; }

	/**
	 * Validation errors; append with this.issues += "\n" + msg.
	 * Parser checks and appends with section context.
	 */
	public string issues { get; set; default = ""; }

	/**
	 * Step index (0-based) of the section this task belongs to, or -1 if not set.
	 * Set when the task list is built (e.g. in ResultParser.parse_task_list) so we don't
	 * re-derive section from position later.
	 */
	public int step_index { get; set; default = -1; }

	/**
	 * Step this task belongs to; required so Details looks up the tree (step.list.runner)
	 * for runner, session, etc.
	 */
	public weak Step step { get; set; }

	/**
	 * Executor output summary (Result summary section).
	 */
	/**
	 * Runner; looked up from step.list.runner (tree: runner → list → step → details).
	 */
	public OLLMcoder.Skill.Runner runner {
		get { return this.step.list.runner; }
	}

	/**
	 * Alias to runner.sr_factory.skill_manager (no setter).
	 */
	public OLLMcoder.Skill.Manager skill_manager {
		get { return this.runner.sr_factory.skill_manager; }
	}

	/**
	 * Parser for last refine or executor response; exec_runs valid after exec_done
	 * (from exec_runs). Initialized in ctor so issues is always available.
	 */
	public ResultParser result_parser { get; set; }

	/**
	 * Markdown links from references block (current_file, paths, plan:...);
	 * Runner resolves for prompt fill. Filled in fill_task_data().
	 */
	public Gee.ArrayList<Markdown.Document.Format> reference_targets { 
		get; set; default = new Gee.ArrayList<Markdown.Document.Format>(); }

	/**
	 * Code blocks from refinement (parser); add directly.
	 */
	public Gee.ArrayList<Markdown.Document.Block> code_blocks { 
		get; set; default = new Gee.ArrayList<Markdown.Document.Block>(); }

	/**
	 * Tool instances from `## Tool Calls` section (ResultParser);
	 * build_exec_runs() uses them for scenario 1.
	 */
	public Gee.ArrayList<Tool> tools { get; set; default = new Gee.ArrayList<Tool>(); }

	/**
	 * Tool instances per execution run. Populated by build_* methods;
	 * run_exec() runs each (tool if needed, then LLM).
	 * REFINE_COMPLETED uses their summaries.
	 */
	public Gee.ArrayList<Tool> exec_runs { get; set; default = new Gee.ArrayList<Tool>(); }

	/**
	 * Initial task_data from ListItem.to_key_map() for one task list item
	 * (keys: exact labels only, see class doc). Runner and session come from step.list.runner (tree).
	 *
	 * @param step the step this task belongs to (provides list and runner via tree)
	 * @param task_data initial map from list item (exact keys only)
	 */
	public Details(Step step, Gee.Map<string, Markdown.Document.Block> task_data)
	{
		base(step.list.runner.factory, step.list.runner.session);
		this.step = step;
		this.task_data = task_data;
		this.issues = "";
		this.result_parser = new ResultParser(step.list.runner, "");
		this.fill_task_data();
		if (this.runner.in_replay) {
			this.chat_call = this.runner.chat_call;
		}
	}

	private void fill_task_data()
	{
		this.requires_user_approval = this.task_data.has_key("Requires user approval");
		string[] keys_to_fill = {
			"What is needed",
			"Skill",
			"References",
			"Expected output" };
		var empty = new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH);
		foreach (var key in keys_to_fill) {
			if (!this.task_data.has_key(key)) {
				this.task_data.set(key, empty);
			}
		}
		this.reference_targets = this.task_data.get("References").links();
	}

	/**
	 * Write this task's result to session task dir.
	 * When exec_runs.size > 1, writes slug + "-" + ex.id + ".md" per Tool
	 * (document content).
	 * Single run writes slug + suffix + ".md" with that run's document or result.
	 *
	 * @param suffix filename suffix for single-run output (default "")
	 */
	public void write(string suffix = "")
	{
		var base_dir = this.runner.session.task_dir();
		if (this.exec_runs.size > 1) {
			foreach (var ex in this.exec_runs) {
				var path = GLib.Path.build_filename(base_dir, this.slug() + "-" + ex.id + ".md");
				try {
					GLib.FileUtils.set_contents(path, ex.document != null ? ex.document.to_markdown() : "");
				} catch (GLib.FileError e) {
					GLib.critical("Details.write: failed to write %s: %s", path, e.message);
				}
			}
			return;
		}
		var path = GLib.Path.build_filename(base_dir, this.slug() + suffix + ".md");
		var content = (this.exec_runs.size == 1 && this.exec_runs.get(0).document != null)
			? this.exec_runs.get(0).document.to_markdown()
			: (this.exec_runs.size == 1 && this.exec_runs.get(0).summary != null
				? this.exec_runs.get(0).summary.to_markdown_with_content() : "");
		try {
			GLib.FileUtils.set_contents(path, content);
		} catch (GLib.FileError e) {
			GLib.critical("Details.write: failed to write %s: %s", path, e.message);
		}
	}

	/**
	 * Apply refined task map: set each key from refined_map into this.task_data,
	 * then re-run fill.
	 *
	 * @param refined_map map from refined task list item (same key set as task_data)
	 */
	public void update_props(Gee.Map<string, Markdown.Document.Block> refined_map)
	{
		this.issues = "";
		foreach (var e in refined_map.entries) {
			// Keep original task's Skill; do not overwrite from refinement output.
			if (e.key == "Skill") {
				continue;
			}
			this.task_data.set(e.key, e.value);
		}
		this.fill_task_data();
	}

	/**
	 * Validate reference_targets hrefs; append to issues on invalid.
	 * Call from parsing process after fill_names (pass list so task-output
	 * anchors can be validated).
	 *
	 * @param stage LIST = task creation/iteration (may reference pending tasks, http(s) URLs accepted); REFINEMENT = refinement output (completed tasks only, task ref must have section anchor that exists).
	 * Task output refs use task URI only. Future: taskname plus tool id plus .md when TaskResult map exists.
	 */
	public void validate_references(MarkdownPhase stage = MarkdownPhase.REFINEMENT)
	{
		foreach (var link in this.reference_targets) {
			var href = link.href;
			if (link.path == "") {
				var anchor = link.hash;
				if (this.runner.user_request != null && this.runner.user_request.headings.has_key(anchor)) {
					GLib.debug("validate_references: anchor href=%s accepted (user_request=%p has_key(%s)=true)",
						 href, this.runner.user_request, anchor);
					continue;
				}
				this.issues += "\n" + "Invalid reference target \"" + href + "\": unknown anchor \"" + anchor + "\".";
				continue;
			}
			if (link.scheme == "http" || link.scheme == "https") {
				if (stage == MarkdownPhase.LIST) {
					continue;
				}
				this.issues += "\n" +
					 "References must not contain http(s) URLs. Do not put URLs in References " + 
					 	"- create a tool call (e.g. web_fetch) in ## Tool Calls to fetch the content instead.";
				continue;
			}
			if (link.path != "" && link.scheme == "file") {
				var project = this.runner.sr_factory.project_manager.active_project;
				string resolved_path;
				if (link.is_relative) {
					if (project == null) {
						this.issues += "\n" + "Invalid reference target \"" + href + "\": relative file path requires an active project.";
						continue;
					}
					resolved_path = link.abspath(project.path);
				} else {
					resolved_path = link.path;
				}
				if (resolved_path == "") {
					continue;
				}

				// When we have an active project, validate using project index first (no filesystem).
				if (project != null) {
					// Path is a known file in the project → valid.
					if (project.project_files.child_map.has_key(resolved_path)) {
						continue;
					}
					// Path is a known directory. At REFINEMENT stage reject; at LIST (task) stage allow.
					if (project.project_files.folder_map.has_key(resolved_path)) {
						if (stage == MarkdownPhase.REFINEMENT) {
							this.issues += "\n" + "Invalid reference target \"" + href + "\": path is a directory; use a file path, not a folder.";
							continue;
						}
						continue;
					}
					// Path not in project index. Check whether path is under project root (prefix).
					var under_project = GLib.File.new_for_path(resolved_path);
					var project_root = GLib.File.new_for_path(project.path);
					var is_under_project = under_project.has_prefix(project_root) || under_project.equal(project_root);
					// Relative: reject if outside project; if under project then not in index → error.
					if (link.is_relative) {
						if (!is_under_project) {
							this.issues += "\n" + "Invalid reference target \"" + href + "\": path is outside project folder.";
							continue;
						}
						this.issues += "\n" + "Invalid reference target \"" + href + "\": path is not in project (use a file that exists in the project).";
						continue;
					}
					// Absolute path not in index. If under project root → not in project (error). Outside → allow fallback.
					if (is_under_project) {
						this.issues += "\n" + "Invalid reference target \"" + href + "\": path is not in project (use a file that exists in the project).";
						continue;
					}
					// Outside project root → allow fall through to filesystem checks.
				}

				// Fallback: path not in project index (or no project). Check filesystem.
				var resolved_file = GLib.File.new_for_path(resolved_path);
				if (!resolved_file.query_exists()) {
					this.issues += "\n" + "Invalid reference target \"" + href + "\": file does not exist (resolved from project folder).";
					continue;
				}
				// Not a directory → valid file reference.
				if (resolved_file.query_file_type(GLib.FileQueryInfoFlags.NONE) != GLib.FileType.DIRECTORY) {
					continue;
				}
				if (stage == MarkdownPhase.REFINEMENT) {
					this.issues += "\n" + "Invalid reference target \"" + href + "\": path is a directory; use a file path, not a folder.";
					continue;
				}
				continue;
			}
			// task://slug.md#section — At LIST only the first step (step_index==0) gets full validation; later steps validated when they become current in iteration. REFINEMENT: completed only, section required and must exist.
			if (link.scheme == "task") {
				var path = link.path.strip();
				if (path.contains("/")) {
					this.issues += "\n" + "Invalid reference target \"" + href + "\": task path must not contain '/'.";
					continue;
				}
				var slug = path.has_suffix(".md") ? path.substring(0, path.length - 3) : path;
				slug = slug.strip();
				if (slug == "") {
					this.issues += "\n" + "Invalid reference target \"" + href + "\": task path is empty.";
					continue;
				}
				Details? ref_task = null;
				switch (stage) {
					case MarkdownPhase.REFINEMENT:
						ref_task = this.runner.completed.slugs.get(slug);
						if (ref_task == null) {
							this.issues += "\n" + "Invalid reference target \"" + href + "\": no completed task for \"" + slug + "\" (references must be to completed tasks only).";
							continue;
						}
						if (link.hash == "") {
							this.issues += "\n" + "Invalid reference target \"" + href + "\": task reference must include a section anchor (e.g. task://" + slug + ".md#section-name).";
							continue;
						}
						if (ref_task.exec_runs.size > 0) {
							var run = ref_task.exec_runs.get(0);
							if (!run.document.headings.has_key(link.hash)) {
								this.issues += "\n" + "Invalid reference target \"" + href + "\": task \"" + slug + "\" has no section \"" + link.hash + "\".";
								continue;
							}
							GLib.debug("validate_references: task href=%s slug=%s hash=%s accepted (exec_runs.size=%u headings.has_key=true)", 
								href, slug, link.hash, ref_task.exec_runs.size);
						} else {
							GLib.debug("validate_references: task href=%s slug=%s accepted with exec_runs.size=0 (no section check)", 
								href, slug);
						}
						break;
					case MarkdownPhase.LIST:
					default:
						ref_task = this.runner.completed.slugs.get(slug);
						if (ref_task == null) {
							ref_task = this.runner.pending.slugs.get(slug);
						}
						if (ref_task == null) {
							this.issues += "\n" + "Invalid reference target \"" + href + "\": no task for \"" + slug + "\".";
							continue;
						}
						// First step only: require section anchor and section exist so we never build refinement prompt with invalid refs; later steps validated when current.
						if (this.step_index != 0) {
							continue;
						}
						if (link.hash == "") {
							this.issues += "\n" + "Invalid reference target \"" + href + "\": task reference must include a section anchor (e.g. task://" + slug + ".md#section-name).";
							continue;
						}
						if (ref_task.exec_runs.size > 0) {
							var run = ref_task.exec_runs.get(0);
							if (!run.document.headings.has_key(link.hash)) {
								this.issues += "\n" + "Invalid reference target \"" + href + "\": task \"" + slug + "\" has no section \"" + link.hash + "\".";
								continue;
							}
						}
						break;
				}
				if (this.step_index >= 0 && ref_task.step_index >= 0 && ref_task.step_index >= this.step_index) {
					this.issues += "\n" + "Reference target \"" + href + 
						"\" refers to a task in the same or later section. A task may only reference the output of a task from an earlier section. "
						+ "I suggest you split this task into its own section.";
				}
				continue;
			}
			this.issues += "\n" + "Invalid reference target \"" + href + "\". "
				+ "Use only: #anchor (document sections), task://taskname.md or task://taskname.md#section, http(s) URL, or absolute file path (must exist).";
		}
	}

	/**
	 * If task_data has no "Name" or empty, set Name = (Skill or "Task") + " " + index.
	 * Single method.
	 *
	 * @param i step index (0-based) used for the default name
	 */
	public void fill_name(int i)
	{
		var name_block = this.task_data.has_key("Name") ?
			this.task_data.get("Name").to_markdown().strip() : "";
		if (name_block != "") {
			return;
		}
		// Allow empty skill; validate_skills() will report this as a bad task.
		var skill = this.task_data.has_key("Skill") ?
			this.task_data.get("Skill").to_markdown().strip() : "";
		var name = (skill != "" ? skill : "Task") + " " + i.to_string();
		var b = new Markdown.Document.Block(Markdown.FormatType.PARAGRAPH);
		b.adopt(new Markdown.Document.Format.from_text(name));
		this.task_data.set("Name", b);
	}

	/**
	 * This task's name as slug (e.g. "Research 1" → "research-1").
	 * Returns "" if no Name in task_data or empty.
	 *
	 * @return slug string for filenames and task refs
	 */
	public string slug()
	{
		if (!this.task_data.has_key("Name")) {
			return "";
		}
		var name = this.task_data.get("Name").to_markdown().strip();
		if (name == "") {
			return "";
		}
		var s = new GLib.Regex("[^a-z0-9]+").replace(name.down(), -1, 0, "-");
		return new GLib.Regex("^-+|-+$").replace(s, -1, 0, "");
	}

	/**
	 * Label for this task in issue messages: section number and name or slug
	 * (e.g. "section 2 \"Research 1\"" or "section 2 (slug: research-1)") so
	 * the LLM can locate the task in the task list.
	 */
	public string issue_label()
	{
		var section = (this.step.title != "") ?
			this.step.title : "section " + (this.step_index >= 0 ? (this.step_index + 1).to_string() : "?");
		var name = this.task_data.has_key("Name") ? 
			this.task_data.get("Name").to_markdown().strip() : "";
		if (name != "") {
			return section + " \"" + name + "\"";
		}
		var s = this.slug();
		if (s != "") {
			return section + " (slug: " + s + ")";
		}
		return section + " (unnamed)";
	}

	private bool refined_done = false;
	private GLib.Error? refine_error = null;
	private GLib.SourceFunc? resume_refined = null;

	/**
	 * True when refinement failed after exhausting communication retries
	 * (e.g. send threw 3 times). Caller should report to user.
	 */
	public bool last_failure_was_communication { get; private set; default = false; }

	public async void wait_refined() throws GLib.Error
	{
		if (this.refined_done) {
			if (this.refine_error != null) {
				throw this.refine_error;
			}
			return;
		}
		this.resume_refined = wait_refined.callback;
		yield;
		this.resume_refined = null;
		if (this.refine_error != null) {
			throw this.refine_error;
		}
	}

	/**
	 * Build refinement prompt template (no current_file; reference_contents
	 * includes current file when in the task's References).
	 */
	public OLLMcoder.Skill.PromptTemplate refinement_prompt() throws GLib.Error
	{
		var definition = this.skill_manager.fetch(this);
		var tpl = OLLMcoder.Skill.PromptTemplate.template("task_refinement.md");
		tpl.system_fill(0);
		var completed_md = this.runner.completed.to_markdown(MarkdownPhase.REFINE_COMPLETED);
		tpl.fill(7,
			"issues", tpl.header_raw("Issues with the current call", this.result_parser.issues),
			"task_data", tpl.header_raw("Task", this.to_markdown(MarkdownPhase.REFINEMENT)),
			"environment", this.runner.env(),
			"project_description", (this.runner.sr_factory.project_manager.active_project == null ?
				"" : this.runner.sr_factory.project_manager.active_project.project_description()),
			"task_reference_contents", this.reference_contents(),
			"skill_details", definition.refine,
			"completed_task_list", (completed_md == "" ? "" : 
				"## Completed tasks (so far)\n\n" + completed_md));
		return tpl;
	}

	/**
	 * Refinement: fill template. Caller has validated via skill_manager.validate(this);
	 * definition from skill_manager.fetch(this) is non-null. Details builds
	 * task_reference_contents by looping reference_targets and asking Runner
	 * for each item (see "Building the task reference block").
	 * Up to 5 refinement attempts; up to 3 communication retries per attempt.
	 * Caller (Runner) must catch and report to user; see 1.23.14.
	 */
	public async void refine(GLib.Cancellable? cancellable = null) throws GLib.Error
	{
		this.refined_done = false;
		this.refine_error = null;
		this.add_message(new OLLMchat.Message("ui",
			OLLMchat.Message.fenced("markdown.oc-frame-info Refining " + 
				this.task_data.get("Name").to_markdown().strip() + " with (" +
					 this.session.model_usage.display_name_with_size() + ")",
					  this.to_markdown(MarkdownPhase.COARSE))));
		yield this.fill_model();
		// Refiner must not have tools; the model must only output text (Skill call + Tool Calls as text).
		this.chat_call.tools.clear();
		// Load file reference buffers so reference_contents() can get content (same as code search tool)
		yield this.runner.load_files(this.reference_targets);
		for (var i = 0; i < 5; i++) {
			if (cancellable != null && cancellable.is_cancelled()) {
				return;
			}
			this.add_message(new OLLMchat.Message("ui-waiting", "Waiting for response…"));
			var tpl = this.refinement_prompt();
			var messages = new Gee.ArrayList<OLLMchat.Message>();
			messages.add(new OLLMchat.Message("system", tpl.filled_system));
			messages.add(new OLLMchat.Message("user", tpl.filled_user));

			var response_text = "";
			for (var attempt = 0; attempt < 3; attempt++) {
				try {
					var response = yield this.chat_call.send(messages, cancellable);
					response_text = response != null ? response.message.content : "";
					break;
				} catch (GLib.Error e) {
					if (attempt != 2) {
						continue;
					}
					this.refine_error = new GLib.IOError.INVALID_ARGUMENT("Task refinement: " + e.message);
					throw this.refine_error;
				}
			}
			if (cancellable != null && cancellable.is_cancelled()) {
				return;
			}
			this.result_parser = new ResultParser(this.runner, response_text);
			this.result_parser.extract_refinement(this);
			var task_name = this.task_data.get("Name").to_markdown().strip();
			if (this.runner.in_replay) {
				((OLLMchat.Call.ReplayChat) this.chat_call).report_replay_outcome(this.result_parser.issues);
			}
			if (this.result_parser.issues == "") {
				this.runner.replay_step("refinement_success: " + task_name, response_text);
				this.add_message(new OLLMchat.Message("ui", "Got result for: " +
					this.task_data.get("Name").to_markdown().strip()));
				this.refined_done = true;
				if (this.resume_refined != null) {
					this.resume_refined();
				}
				return;
			}
			if (i < 4) {
				this.runner.replay_step("refinement_parse_issues: " + task_name,
					response_text + "\n\nParse issues:\n" + this.result_parser.issues);
				this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
					"text.oc-frame-warning Refinement for \"" + 
						this.task_data.get("Name").to_markdown().strip() + "\" had issues (retrying)",
					this.result_parser.issues.strip())));
			}
		}
		this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
			"text.oc-frame-warning Refinement for \"" + 
				this.task_data.get("Name").to_markdown().strip() + "\" failed after 5 tries",
			this.result_parser.issues.strip())));
		throw new GLib.IOError.INVALID_ARGUMENT("Task refinement: " + this.result_parser.issues);
	}

	/**
	 * Set chat_call.model from this task's skill definition when the skill
	 * header has an optional model and it is available; otherwise use default.
	 */
	protected override async void fill_model()
	{
		var definition = this.skill_manager.fetch(this);
		if (!definition.header.has_key("model")) {
			yield base.fill_model();
			return;
		}
		var skill_model = definition.header.get("model").strip();
		if (skill_model != "" && this.connection.models.has_key(skill_model)) {
			this.chat_call.model = skill_model;
			// this.add_message(new OLLMchat.Message("ui", "skill using " + skill_model + " model."));
			return;
		}
		if (skill_model != "") {
			this.add_message(new OLLMchat.Message("ui", OLLMchat.Message.fenced(
				"text.oc-frame-warning Model unavailable",
				"The skill requested the model \"" + skill_model +
					 "\", but it was not available. Using your selected model instead.")));
		}
		yield base.fill_model();
	}

	/**
	 * Task as markdown for a given phase. Does not add section headings
	 * (e.g. `## Task`); caller adds header.
	 * COARSE: creation keys. REFINEMENT: task list + `## Tool Calls` when tools exist.
	 * LIST: task list + ##### Result summary (raw) when exec_done.
	 * EXECUTION: same as REFINEMENT for Tool Calls.
	 *
	 * @param phase which phase (COARSE, REFINEMENT, LIST, REFINE_COMPLETED,
	 * EXECUTION)
	 * @return markdown string for this phase
	 */
	public string to_markdown(MarkdownPhase phase)
	{
		string[] order = {
			"Name",
			"What is needed",
			"Skill",
			"References",
			"Expected output",
			"Output"
		};
		var ret = "";
		for (var i = 0; i < order.length; i++) {
			var key = order[i];
			switch (key) {
				case "References":
					if (phase == MarkdownPhase.REFINE_COMPLETED) {
						continue;
					}
					break;
				case "Output":
					if ((phase != MarkdownPhase.LIST && phase != MarkdownPhase.REFINE_COMPLETED)
						 || !this.exec_done || this.exec_runs.size == 0) {
						continue;
					}
					// Output raw result summaries: numbered headings + pretext with task links
					if (this.exec_runs.size > 0) {
						var task_ref = "task://" + this.slug() + ".md";
						ret += "#### Task Result Output summaries\n\n";
						ret += this.exec_runs.size.to_string()
							 + " subtool(s) were run — these are the outputs. ";
						ret += "You can refer to them as ";
						var ref_parts = new string[this.exec_runs.size];
						for (var ri = 0; ri < this.exec_runs.size; ri++) {
							var n = (ri + 1).to_string();
							ref_parts[ri] = "[Result summary " + n + "](" 
								+ task_ref + "#result-summary-" + n + ")";
						}
						ret += string.joinv(", ", ref_parts) + ".\n\n";
						var idx = 0;
						foreach (var ex in this.exec_runs) {
							idx++;
							var title = "Result summary " + idx.to_string();
							ex.summary.update_header(5, title);
							ret += ex.summary.to_markdown_with_content().strip() + "\n\n";
						}
					}
					continue;
				default:
					break;
			}
			if (!this.task_data.has_key(key)) {
				continue;
			}
			ret += "- **" + key + "** " + this.task_data.get(key).to_markdown() + "\n";
		}
		if (phase == MarkdownPhase.REFINE_COMPLETED) {
			return ret;
		}
		// Include ## Tool Calls only when there are tools (omit empty section in prompt).
		if (this.tools.size == 0) {
			return ret;
		}
		ret += "\n## Tool Calls\n\n";
		foreach (var tool in this.tools) {
			var obj = new Json.Object();
			obj.set_string_member("name", tool.name);
			if (tool.tool_call != null && tool.tool_call.id != "") {
				obj.set_string_member("id", tool.tool_call.id);
			}
			if (tool.arguments != null) {
				obj.set_object_member("arguments", tool.arguments);
			}
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(obj);
			var gen = new Json.Generator();
			gen.set_root(node);
			ret += "```json\n" + gen.to_data(null) + "\n```\n\n";
		}
		return ret;
	}


	/**
	 * Line + unfenced body. Use for reference `#anchor`.
	 *
	 * @param line heading or label line
	 * @param body unfenced body content
	 * @return line + body, or "" if body empty
	 */
	internal string header_raw(string line, string body)
	{
		if (body == "") {
			return "";
		}
		return line + "\n\n" + body + "\n\n";
	}

	/**
	 * Line + fenced body; content and language from file.
	 * Use for reference file path. Exception: we do output the header
	 * (and empty block if needed) when content is empty.
	 *
	 * @param line heading or label line
	 * @param file file to read content and language from
	 * @return fenced block with line + content
	 */
	internal string header_file(string line, OLLMfiles.File file)
	{
		var content = file.get_contents(0);
		var fence = (content.index_of("\n```") >= 0 || content.has_prefix("```")) ? "~~~~" : "```";
		return line + "\n\n"
			+ fence
			+ (file.language != "" ? file.language + "\n" : "\n")
			+ content + "\n"
			+ fence + "\n\n";
	}

	/**
	 * Line + fenced body with type (e.g. "json", "text").
	 * Use for tool call/output.
	 *
	 * @param line heading or label line
	 * @param body body content to fence
	 * @param type optional language/info string (e.g. "json", "text")
	 * @return fenced block, or "" if body empty
	 */
	internal string header_fenced(string line, string body, string type = "")
	{
		if (body == "") {
			return "";
		}
		var fence = (body.index_of("\n```") >= 0 || body.has_prefix("```")) ? "~~~~" : "```";
		return line + "\n\n"
			+ fence
			+ (type != "" ? type + "\n" : "\n")
			+ body + "\n"
			+ fence + "\n\n";
	}

	/**
	 * Resolved content for a single reference link. Uses link.scheme (file, task,
	 * http(s), or path == "" for `#anchor`). File: project manager or
	 * File.new_fake, create_buffer, header_file. Other schemes:
	 * runner.reference_content(link).
	 *
	 * @param link the reference link (scheme, path, href, title
	 * already parsed)
	 * @return fenced or file block for prompt, or "" if unresolved/empty
	 */
	internal string link_content(Markdown.Document.Format link)
	{
		var name = link.title != "" ? link.title : (link.href != "" ? link.href : "unnamed reference");
		if (link.path == "") {
			var content = this.runner.reference_content(link);
			if (content != "") {
				return this.header_fenced(
					"### Reference contents for " + name,
					content,
					"markdown");
			}
			return "";
		}
		if (link.scheme == "http" || link.scheme == "https") {
			return "";
		}
		if (link.scheme == "task") {
			var content = this.runner.reference_content(link);
			if (content != "") {
				return this.header_fenced(
					"### Reference contents for " + name,
					content,
					"markdown");
			}
			return "";
		}
		if (link.scheme != "file") {
			return "";
		}
		var project = this.runner.sr_factory.project_manager.active_project;
		var resolved_path = link.is_relative
			? (project == null ? "" : link.abspath(project.path))
			: link.path;
		if (resolved_path == "") {
			return "";
		}
		var found = this.runner.sr_factory.project_manager.get_file_from_active_project(resolved_path);
		if (found == null) {
			found = new OLLMfiles.File.new_fake(this.runner.sr_factory.project_manager, resolved_path);
		}
		this.runner.sr_factory.project_manager.buffer_provider.create_buffer(found);
		return this.header_file(
			"### Reference contents for " + name,
			found);
	}

	/**
	 * Resolved reference block for this task: loop reference_targets; for each,
	 * get content via link_content(). When there are no references, returns "".
	 * When there are references, returns "## Reference Contents" plus each block.
	 */
	private string reference_contents()
	{
		string[] parts = {};
		foreach (var link in this.reference_targets) {
			GLib.debug("reference_contents: resolving link scheme=%s path=%s href=%s hash=%s", 
				link.scheme, link.path, link.href, link.hash);
			var block = this.link_content(link);
			if (block != "") {
				parts += block;
			}
		}
		if (parts.length == 0) {
			return "";
		}
		return "## Reference Contents\n\n" + string.joinv("", parts);
	}

	/**
	 * Add all reference_targets to the given Tool.
	 * Used by add_exec_runs_for_tools() and by the combined branch in
	 * build_exec_runs().
	 *
	 * @param ex the Tool (exec run) to add references to
	 */
	private void add_all_references_to(Tool ex)
	{
		foreach (var link in this.reference_targets) {
			ex.references.add(link);
		}
	}

	/**
	 * Scenario 1: one Tool per tool; reuse each from this.tools, set id, add all references,
	 * add to exec_runs.
	 */
	private void add_exec_runs_for_tools()
	{
		var idx = 0;
		foreach (var ex in this.tools) {
			ex.id = "tool-%d".printf(idx++);
			this.add_all_references_to(ex);
			this.exec_runs.add(ex);
		}
	}

	/**
	 * Scenario 2: one Tool per reference; each with references =
	 * single-element list.
	 * If no refs, one Tool with id "exec".
	 */
	private void add_exec_runs_for_references()
	{
		var factory = (OLLMchat.Agent.Factory) this.runner.sr_factory;
		var idx = 0;
		foreach (var link in this.reference_targets) {
			var ex = new Tool(factory, this.session, this, "ref-%d".printf(idx++));
			ex.references.add(link);
			this.exec_runs.add(ex);
		}
		if (this.exec_runs.size == 0) {
			var ex = new Tool(factory, this.session, this, "exec");
			this.exec_runs.add(ex);
		}
	}

	/**
	 * Populate exec_runs. Three scenarios only: (1) tools when run →
	 * one Tool per tool; (2) refs without tools → one per ref;
	 * (3) combined → one run with all refs.
	 * Does not run them. Return early per branch.
	 */
	public void build_exec_runs()
	{
		this.exec_runs.clear();
		var definition = this.skill_manager.fetch(this);
		var execute_combined = definition.header.has_key("execute-combined") &&
			definition.header.get("execute-combined").strip() != "";
		if (this.tools.size > 0) {
			this.add_exec_runs_for_tools();
			return;
		}
		if (execute_combined) {
			var factory = (OLLMchat.Agent.Factory) this.runner.sr_factory;
			var ex = new Tool(factory, this.session, this, "exec");
			this.add_all_references_to(ex);
			this.exec_runs.add(ex);
			return;
		}
		this.add_exec_runs_for_references();
	}

	/**
	 * Run all Tool exec runs (tool if needed, then LLM). Summaries stay on each Tool.
	 * Documents stay on each Tool (ex.document).
	 */
	public async void run_exec() throws GLib.Error
	{
		foreach (var ex in this.exec_runs) {
			yield ex.run();
		}
		this.exec_done = true;
	}
}

}
