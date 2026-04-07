/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * LGPL-3 — see COPYING in repository.
 */

/*
 * Callers validate links (ValidateLink / Details) before preload and resolve.
 * Do not add validation, GLib.assert, or GLib.error in resolve — preload fills
 * buffers, http_cache, and parsed trees where needed; resolve reads that state only.
 *
 * preload_file, preload_http, and preload_links are async (disk IO, Tree.parse, HTTP).
 * Call them before resolve for the same link set. resolve and the per-scheme helpers
 * are synchronous.
 */

namespace OLLMcoder.Task
{

/**
 * Turns validated task reference links into fenced markdown blocks for prompts:
 * task docs, #anchors in the user request, http(s) from cache, and file excerpts
 * (line range, full file, or AST path after [[preload_links]] parsed the tree).
 * Used from [[Details.reference_contents]], refine(), and [[Tool.run]] after preload.
 */
public class ResolveLink : GLib.Object
{
	OLLMcoder.Skill.Runner runner;
	Details details;
	PhaseEnum stage;

	/**
	 * Buffers, tree cache, and project files — same object as
	 * runner.sr_factory.project_manager on the [[runner]] passed to the constructor.
	 */
	public OLLMfiles.ProjectManager project_manager { get; private set; }

	public ResolveLink (
			OLLMcoder.Skill.Runner runner,
			Details details,
			PhaseEnum stage)
	{
		this.runner = runner;
		this.details = details;
		this.stage = stage;
		this.project_manager = runner.sr_factory.project_manager;
	}

	/**
	 * Build one reference block (header + body). Synchronous; call [[preload_links]]
	 * (and any narrower preload) first so file buffers, trees, and runner.http_cache are ready.
	 */
	public string resolve (Markdown.Document.Format link)
	{
		if (link.path == "") {
			return this.anchor (link);
		}
		switch (link.scheme) {
			case "http":
			case "https":
				return this.http (link);
			case "task":
				return this.task (link);
			case "file":
				return this.file (link);
			default:
				GLib.assert_not_reached ();
		}
	}

	string task (Markdown.Document.Format link)
	{
		GLib.debug ("path=%s hash=%s", link.path, link.hash);
		var slug = link.path.has_suffix (".md")
			? link.path.substring (0, link.path.length - 3) : link.path;
		var task = this.runner.completed.slugs.has_key (slug)
			? this.runner.completed.slugs.get (slug) : this.runner.pending.slugs.get (slug);
		var doc = task.out_doc;
		if (link.hash == "") {
			if (this.stage == PhaseEnum.REFINEMENT) {
				var inner = doc.headings.get ("result-summary").to_markdown_with_content ();
				var fence = (inner.index_of ("\n```") >= 0 || inner.has_prefix ("```")) ? "~~~~" : "```";
				var body = fence + "markdown\n" + inner + "\n" + fence + "\n";
				return this.details.header_fenced (this.reference_title (link), body, "markdown");
			}
			return this.details.header_fenced (
				this.reference_title (link),
				doc.to_markdown (),
				"markdown");
		}
		var section_md = doc.headings.get (link.hash).to_markdown_with_content ();
		if (this.stage == PhaseEnum.REFINEMENT) {
			string[] lines = section_md.split ("\n");
			if (lines.length <= 20) {
				return this.details.header_fenced (
					this.reference_title (link),
					section_md,
					"markdown");
			}
			var abbrev = string.joinv ("\n", lines[0:20])
				+ "\n\n**This has been abbreviated.** The full content has "
				+ lines.length.to_string () + " lines.\n";
			return this.details.header_fenced (this.reference_title (link), abbrev, "markdown");
		}
		return this.details.header_fenced (this.reference_title (link), section_md, "markdown");
	}

	string anchor (Markdown.Document.Format link)
	{
		var block = this.runner.user_request.headings.get (link.hash);
		var anchor_md = block.to_markdown_with_content ();
		if (this.stage == PhaseEnum.REFINEMENT) {
			string[] lines = anchor_md.split ("\n");
			if (lines.length <= 20) {
				return this.details.header_fenced (
					this.reference_title (link),
					anchor_md,
					"markdown");
			}
			var abbrev = string.joinv ("\n", lines[0:20])
				+ "\n\n**This has been abbreviated.** The full content has "
				+ lines.length.to_string () + " lines.\n";
			return this.details.header_fenced (this.reference_title (link), abbrev, "markdown");
		}
		return this.details.header_fenced (this.reference_title (link), anchor_md, "markdown");
	}

	/**
	 * HTTP(s): markdown body from runner.http_cache (filled by [[preload_http]] using
	 * the session web_fetch tool). Returns "" unless PhaseEnum is EXECUTION.
	 */
	string http (Markdown.Document.Format link)
	{
		if (this.stage != PhaseEnum.EXECUTION) {
			return "";
		}
		var key = link.href != "" ? link.href : link.path;
		return this.details.header_fenced (
			this.reference_title (link),
			this.runner.http_cache.get (key),
			"markdown");
	}

	string reference_title (Markdown.Document.Format link)
	{
		var name = link.title != ""
			? link.title
			: (link.href != "" ? link.href : "unnamed reference");
		var ref_url = link.href != "" ? link.href : link.path;
		var title = "### Reference contents for " + name;
		if (ref_url != "" && ref_url != name) {
			title += " — " + ref_url;
		}
		return title;
	}

	/**
	 * Cached regex for #L12-L34-style line-range fragments; AST path hashes do not match this.
	 *
	 * LLM / maintainer note: **Do not** wrap `new GLib.Regex` in try/catch, and **do not** add
	 * `throws GLib.Error` (or `RegexError`) to `resolve`, `file`, `file_ast`, or `reference_contents`
	 * to “fix” the Vala warning. The pattern is a fixed literal; compile failure cannot happen in
	 * normal use. We intentionally ignore the `unhandled error GLib.RegexError` warning.
	 */
	private static GLib.Regex? line_regex_cache;

	private GLib.Regex line_regex ()
	{
		if (line_regex_cache == null) {
			line_regex_cache = new GLib.Regex (
				"^[Ll](\\d+)-[Ll](\\d+)$",
				GLib.RegexCompileFlags.OPTIMIZE | GLib.RegexCompileFlags.CASELESS);
		}
		return line_regex_cache;
	}

	/**
	 * Resolve path, create the buffer if needed, and read_async so [[resolve]] / [[file]]
	 * can read full file or line ranges from the buffer.
	 */
	public async void preload_file (Markdown.Document.Format link)
	{
		link.resolve (this.project_manager.active_project.path);
		if (link.scheme == "file" && link.is_dir (this.project_manager.active_project.path)) {
			return;
		}
		var resolved_path = link.is_relative
			? link.abspath (this.project_manager.active_project.path)
			: link.path;
		var found = this.project_manager.get_file_from_active_project (resolved_path);
		if (found == null) {
			found = new OLLMfiles.File.new_fake (this.project_manager, resolved_path);
		}
		this.project_manager.buffer_provider.create_buffer (found);
		try {
			yield found.buffer.read_async ();
		} catch (GLib.Error e) {
			GLib.debug ("%s: %s", found.path, e.message);
		}
	}

	/**
	 * For http(s) links: if the URL key is missing from runner.http_cache, run the
	 * session web_fetch tool (markdown format) and store the body under that key;
	 * no-op when already cached; empty key stores an error message instead of fetching.
	 */
	private async void preload_http (Markdown.Document.Format link)
	{
		if (link.scheme != "http" && link.scheme != "https") {
			return;
		}
		var key = link.href != "" ? link.href : link.path;
		if (this.runner.http_cache.has_key (key)) {
			return;
		}
		if (key == "") {
			this.runner.http_cache.set (key,
				"ERROR: Reference URL is empty; cannot prefetch.");
			return;
		}
		var tool_impl = this.runner.session.manager.tools.get ("web_fetch");
		var args = new Json.Object ();
		args.set_string_member ("url", key);
		args.set_string_member ("format", "markdown");
		var fn = new OLLMchat.Response.CallFunction.with_values ("web_fetch", args);
		var call = new OLLMchat.Response.ToolCall.with_values ("http-fake-id", fn);
		var md = yield tool_impl.execute (this.details.chat (), call, true);
		this.runner.http_cache.set (key, md);
	}

	/**
	 * Warm state for a batch of links: [[preload_http]] for http(s); for file,
	 * [[preload_file]] then, when hash is non-empty and not a #L line-range,
	 * tree_factory + tree.parse so [[file_ast]] can resolve AST path fragments.
	 */
	public async void preload_links (Gee.Collection<Markdown.Document.Format> links)
	{
		foreach (var link in links) {
			if (link.scheme == "http" || link.scheme == "https") {
				yield this.preload_http (link);
				continue;
			}
			if (link.scheme != "file") {
				continue;
			}
			link.resolve (this.project_manager.active_project.path);
			if (link.is_dir (this.project_manager.active_project.path)) {
				continue;
			}
			yield this.preload_file (link);
			GLib.MatchInfo mi_lr;
			if (link.hash == "" || this.line_regex ().match (link.hash, 0, out mi_lr)) {
				continue;
			}
			var resolved_path = link.is_relative
				? link.abspath (this.project_manager.active_project.path)
				: link.path;
			var found = this.project_manager.get_file_from_active_project (resolved_path);
			if (found == null) {
				found = new OLLMfiles.File.new_fake (this.project_manager, resolved_path);
			}
			var tree = this.project_manager.tree_factory (found);
			try {
				yield tree.parse ();
			} catch (GLib.Error e) {
				GLib.debug ("tree.parse %s: %s", found.path, e.message);
			}
		}
	}

	/**
	 * file: scheme — full file, #Lstart-Lend line slice, or [[file_ast]] for other hashes.
	 * Expects buffer (and tree when not a line-range) from preload.
	 */
	string file (Markdown.Document.Format link)
	{
		link.resolve (this.project_manager.active_project.path);
		if (link.scheme == "file" && link.is_dir (this.project_manager.active_project.path)) {
			return "";
		}
		var resolved_path = link.is_relative
			? link.abspath (this.project_manager.active_project.path)
			: link.path;
		var found = this.project_manager.get_file_from_active_project (resolved_path);
		if (found == null) {
			found = new OLLMfiles.File.new_fake (this.project_manager, resolved_path);
		}
		var title = this.reference_title (link);

		if (link.hash == "") {
			var stage = this.stage;
			var content = stage == PhaseEnum.REFINEMENT
				? found.contents (1, 20)
				: found.contents (-1, -1);
			if (stage == PhaseEnum.REFINEMENT && found.line_count () > 20) {
				content += "\n\n**This has been abbreviated.** The full content has "
					+ found.line_count ().to_string () + " lines.\n";
			}
			return this.file_fence_block (title, found, content);
		}

		GLib.MatchInfo mi;
		if (this.line_regex ().match (link.hash, 0, out mi)) {
			var start = int.parse (mi.fetch (1));
			var end = int.parse (mi.fetch (2));
			var stage = this.stage;
			var content = stage == PhaseEnum.REFINEMENT
				? found.contents (int.max (start, 1), int.min (end, start + 29))
				: found.contents (start, end);
			if (stage == PhaseEnum.REFINEMENT && end > start + 29) {
				content += "\n\n**This has been abbreviated.** The full content has "
					+ found.line_count ().to_string () + " lines.\n";
			}
			return this.file_fence_block (title, found, content);
		}

		return this.file_ast (link, found);
	}

	/**
	 * AST path fragment: tree from tree_factory(found) must already be parsed; lookup_path
	 * maps link.hash to buffer offsets, then text is taken from the file buffer (refinement
	 * may abbreviate long excerpts).
	 */
	string file_ast (Markdown.Document.Format link, OLLMfiles.File found)
	{
		var tree = this.project_manager.tree_factory (found);
		int start_line, end_line, comment_start;
		tree.lookup_path (link.hash, out start_line, out end_line, out comment_start);
		string content = found.buffer.get_text (comment_start - 1, end_line - 2);
		if (this.stage == PhaseEnum.REFINEMENT) {
			string[] lines = content.split ("\n");
			if (lines.length > 29) {
				content = string.joinv ("\n", lines[0:29])
					+ "\n\n**This has been abbreviated.**\n";
			}
		}
		return this.file_fence_block (
			this.reference_title (link),
			found,
			content);
	}

	string file_fence_block (string line, OLLMfiles.File file, string content)
	{
		var fence = (content.index_of ("\n```") >= 0 || content.has_prefix ("```")) ? "~~~~" : "```";
		return line + "\n\n"
			+ fence
			+ (file.language != "" ? file.language + "\n" : "\n")
			+ content + "\n"
			+ fence + "\n\n";
	}
}

}
