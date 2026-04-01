/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library. If not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMcoder.Task
{

/**
 * Reference-link validation for task references (used from [[ResultParser]] and similar).
 *
 * @param runner graph for task refs, project, user request headings
 * @param details task being validated (slug, step index, output document)
 * @param stage markdown phase (LIST, REFINEMENT, POST_EXEC, …)
 */
public class ValidateLink : GLib.Object
{
	OLLMcoder.Skill.Runner runner;
	Details details;
	MarkdownPhase stage;

	/**
	 * Change-detail sections used to resolve fragment links (hash targets).
	 * In exec_extract, assign the same list as the Tool's writes; may be empty.
	 */
	public Gee.ArrayList<WriteChange> writes {
		get; set; default = new Gee.ArrayList<WriteChange> ();
	}

	/**
	 * Parsed Result summary (or synthesis slice) for fragment fallback when writes do not match.
	 * Default empty until set by ResultParser before validate_all.
	 */
	public Markdown.Document.Document document {
		get; set; default = new Markdown.Document.Document ();
	}

	/**
	 * Cumulative validation messages. [[validate]] / [[validate_all]] append only; use a new [[ValidateLink]] for a clean buffer.
	 */
	public string issues { get; private set; default = ""; }

	public ValidateLink (
			OLLMcoder.Skill.Runner runner,
			Details details,
			MarkdownPhase stage)
	{
		this.runner = runner;
		this.details = details;
		this.stage = stage;
	}

	/**
	 * Whether link.hash matches a heading in any WriteChange body or in this.document.
	 *
	 * Only considers bare fragment links (empty path and non-empty hash). If the model
	 * emits path-plus-hash links, extend this helper once that shape appears in executor output.
	 *
	 * @param link parsed link (fragment-style: path empty, hash set)
	 * @return true if the anchor resolves in writes or document
	 */
	public bool check_writes (Markdown.Document.Format link)
	{
		if (link.path != "" || link.hash == "") {
			return false;
		}
		foreach (var wc in this.writes) {
			if (wc.document.headings.has_key (link.hash)) {
				return true;
			}
		}
		return this.document.headings.has_key (link.hash);
	}

	/**
	 * Validate one link; appends lines (each prefixed with \\n) to [[issues]].
	 */
	public void validate (Markdown.Document.Format link)
	{
		if (link.path == "") {
			if (this.runner.user_request != null &&
					this.runner.user_request.headings.has_key (link.hash)) {
				return;
			}
			switch (this.stage) {
				case MarkdownPhase.EXECUTION:
				case MarkdownPhase.POST_EXEC:
					if (this.details.out_doc.headings.has_key (link.hash)) {
						return;
					}
					if (this.check_writes (link)) {
						return;
					}
					break;
				default:
					break;
			}
			this.issues += "\n" + "Invalid reference target \"" + link.href +
				"\": unknown anchor \"" + link.hash + "\".";
			return;
		}
		if (link.scheme == "http" || link.scheme == "https") {
			this.http (link.href);
			return;
		}
		if (link.path != "" && link.scheme == "file") {
			this.file (link);
			return;
		}
		if (link.scheme == "task") {
			this.task (link);
			return;
		}
		this.issues += "\n" + "Invalid reference target \"" + link.href + "\". " +
			"Use only: #anchor (document sections), task://taskname.md, http(s) URL, " +
			"or absolute file path (must exist).";
	}

	/**
	 * Validate every link in ''links''; appends to [[issues]] (same shape as task reference errors).
	 */
	public void validate_all (Gee.Iterable<Markdown.Document.Format> links)
	{
		foreach (var link in links) {
			this.validate (link);
		}
	}

	void http (string href)
	{
		switch (this.stage) {
			case MarkdownPhase.LIST:
			case MarkdownPhase.EXECUTION:
			case MarkdownPhase.POST_EXEC:
				return;
			case MarkdownPhase.REFINEMENT:
			default:
				this.issues += "\n" +
					"References must not contain http(s) URLs. Do not put URLs in References " +
					"- create a tool call (e.g. web_fetch) in ## Tool Calls to fetch the content instead.";
				return;
		}
	}

	void file (Markdown.Document.Format link)
	{
		var project = this.runner.sr_factory.project_manager.active_project;
		if (project == null) {
			this.issues += "\n" + "Invalid reference target \"" + link.href +
				"\": file references require an active project.";
			return;
		}
		var resolved_path = link.path;
		if (link.is_relative) {
			resolved_path = link.abspath (project.path);
		}
		if (resolved_path == "") {
			return;
		}
		if (project.project_files.child_map.has_key (
				resolved_path.has_suffix ("/") ?
					resolved_path.substring (0, resolved_path.length - 1) :
					resolved_path)) {
			return;
		}
		if (project.project_files.folder_map.has_key (
				resolved_path.has_suffix ("/") ?
					resolved_path.substring (0, resolved_path.length - 1) :
					resolved_path)) {
			switch (this.stage) {
				case MarkdownPhase.REFINEMENT:
				case MarkdownPhase.EXECUTION:
				case MarkdownPhase.POST_EXEC:
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": path is a directory; use a file path, not a folder.";
					return;
				case MarkdownPhase.LIST:
				default:
					return;
			}
		}
		var under_project = GLib.File.new_for_path (resolved_path);
		var project_root = GLib.File.new_for_path (project.path);
		if (link.is_relative &&
				!under_project.has_prefix (project_root) &&
				!under_project.equal (project_root)) {
			this.issues += "\n" + "Invalid reference target \"" + link.href +
				"\": path is outside project folder.";
			return;
		}
		var resolved_file = GLib.File.new_for_path (resolved_path);
		if (!resolved_file.query_exists ()) {
			this.issues += "\n" + "Invalid reference target \"" + link.href +
				"\": file does not exist (resolved from project folder).";
			return;
		}
		if (resolved_file.query_file_type (GLib.FileQueryInfoFlags.NONE) !=
				GLib.FileType.DIRECTORY) {
			return;
		}
		switch (this.stage) {
			case MarkdownPhase.REFINEMENT:
			case MarkdownPhase.EXECUTION:
			case MarkdownPhase.POST_EXEC:
				this.issues += "\n" + "Invalid reference target \"" + link.href +
					"\": path is a directory; use a file path, not a folder.";
				return;
			case MarkdownPhase.LIST:
			default:
				return;
		}
	}

	void task (Markdown.Document.Format link)
	{
		if (link.path.strip ().contains ("/")) {
			this.issues += "\n" + "Invalid reference target \"" + link.href +
				"\": task path must not contain '/'.";
			return;
		}
		var slug = (link.path.strip ().has_suffix (".md") ?
			link.path.strip ().substring (0, link.path.strip ().length - 3) :
			link.path.strip ()).strip ();
		if (slug == "") {
			this.issues += "\n" + "Invalid reference target \"" + link.href +
				"\": task path is empty.";
			return;
		}
		switch (this.stage) {
			case MarkdownPhase.EXECUTION:
			case MarkdownPhase.POST_EXEC:
				if (slug == this.details.slug ()) {
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": do not use task:// links to this task in your output; " +
						"use ## section headings only.";
					return;
				}
				if (!this.runner.completed.slugs.has_key (slug)) {
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": no completed task for \"" + slug + "\".";
					return;
				}
				var other_task = this.runner.completed.slugs.get (slug);
				if (link.hash != "" && !other_task.out_doc.headings.has_key (link.hash)) {
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": task \"" + slug + "\" has no section \"" + link.hash +
						"\". Use `task://" + slug + ".md` with no suffix after `.md` for the full output.";
				}
				return;
			case MarkdownPhase.REFINEMENT:
				var completed_ref = this.runner.completed.slugs.get (slug);
				if (completed_ref == null) {
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": no completed task for \"" + slug +
						"\" (references must be to completed tasks only).";
					return;
				}
				if (link.hash != "" && !completed_ref.out_doc.headings.has_key (link.hash)) {
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": task \"" + slug + "\" has no section \"" + link.hash +
						"\". Use `task://" + slug + ".md` with no suffix after `.md` for the full output.";
				}
				return;
			case MarkdownPhase.LIST:
			default:
				Details? ref_task = null;
				var ref_is_completed = this.runner.completed.slugs.has_key (slug);
				if (ref_is_completed) {
					ref_task = this.runner.completed.slugs.get (slug);
				} else {
					ref_task = this.runner.pending.slugs.get (slug);
				}
				if (ref_task == null) {
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": no task for \"" + slug + "\".";
					return;
				}
				if (this.details.step_index != 0) {
					return;
				}
				if (ref_task.exec_done && link.hash != "" &&
						!ref_task.out_doc.headings.has_key (link.hash)) {
					this.issues += "\n" + "Invalid reference target \"" + link.href +
						"\": task \"" + slug + "\" has no section \"" + link.hash +
						"\". Use `task://" + slug + ".md` with no suffix after `.md` for the full output.";
				}
				if (!ref_is_completed && this.details.step_index >= 0 && ref_task.step_index >= 0 &&
						ref_task.step_index >= this.details.step_index) {
					this.issues += "\n" + "Reference target \"" + link.href +
						"\" refers to a task in the same or later section. " +
						"A task may only reference the output of a task from an earlier section. " +
						"I suggest you split this task into its own section.";
				}
				return;
		}
	}
}

}
