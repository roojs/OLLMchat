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

namespace OLLMcoder.Action
{

/**
 * Base for task execution runners (lifted from {@link Task.Details.run_exec} /
 * {@link Task.Details.run_post_exec}). Not wired in yet — see plan 7.16.1.
 */
public abstract class Base
{
	protected Task.Details task;

	protected Base (Task.Details task)
	{
		this.task = task;
	}

	public abstract async void run () throws GLib.Error;

	/**
	 * Parse one executor response into an execution run.
	 *
	 * Shared by live/replay callers through {@link Task.ResultParser.exec_extract};
	 * write-specific Change details handling lives in {@link WriteExec.extract_writes}.
	 */
	public static bool extract_exec(Task.ResultParser parser, Task.Tool ex)
	{
		if (!parser.has_heading("result-summary")) {
			parser.add_issue("\n" + "This task's executor output must include a \"Result summary\" section (required). " +
				"It was missing or not found in the response. " +
				"Produce ## Result summary (what was found or produced; whether needs are met or gaps remain).");
			return false;
		}
		ex.summary = parser.heading("result-summary");
		ex.document = parser.parsed_document;
		var sum_render = new Markdown.Document.Render();
		sum_render.parse(ex.summary.to_markdown_with_content());
		if (ex.parent.skill.tools.contains("write_file") && !WriteExec.extract_writes(parser, ex)) {
			return false;
		}
		var vl_sum = new Task.ValidateLink(ex.parent.runner, ex.parent, Task.PhaseEnum.EXECUTION) {
			writes = ex.writes,
			document = sum_render.document
		};
		vl_sum.validate_all(sum_render.document.links);
		if (vl_sum.issues != "") {
			parser.add_issue(vl_sum.issues);
			return false;
		}
		foreach (var link in sum_render.document.links) {
			if (link.path != "" || link.hash == "") {
				continue;
			}
			foreach (var wc in ex.writes) {
				if (!wc.document.headings.has_key(link.hash)) {
					continue;
				}
				link.up_relpath(wc.file_path.strip());
				break;
			}
		}
		if (sum_render.document.headings.has_key("result-summary")) {
			ex.summary = sum_render.document.headings.get("result-summary");
		}
		/* Full executor tree stays in parser.parsed_document (Path 2 still uses parsed_document.to_markdown()).
		   ex.document still aliases parser.parsed_document until Tool.run replaces ex.document with a new summary-only Document (§5.7a). */
		if (!ex.parent.skill.tools.contains("write_file") || ex.writes.size > 0) {
			return true;
		}
		var md = parser.parsed_document.to_markdown().strip();
		if (md.down().contains("**no changes needed**")) {
			return true;
		}
		parser.add_issue("\nWrite executor output must include a recognizable Change details section, or Path 2 (full markdown must contain **no changes needed**).");
		return false;
	}
}

}
