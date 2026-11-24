/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Stacked review — sync after full approve: tab + bar stay (Tier B).
 */

public class StackedReviewWidgetTest : RpcTestAppBase
{
	private OLLMfiles.ProjectManager manager;
	private OLLMcoder.SourceView editor;
	private OLLMcoder.Diff.ReviewBar bar;
	private string project_path = "/tmp/ollm-stacked-review-widget";
	private string file_path;

	public StackedReviewWidgetTest()
	{
		base("com.roojs.ollmchat.test-stacked-review-widget");
	}

	protected override string get_app_name()
	{
		return "test-stacked-review-widget";
	}

	protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
	{
		this.fail(command_line, "run_test owns this flow");
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		Gtk.init();
		OLLMfiles.rpc_register();
		this.file_path = this.project_path + "/stacked.txt";
		this.manager = new OLLMfiles.ProjectManager();
		this.manager.buffer_provider = new OLLMcoder.BufferProvider();
		this.editor = new OLLMcoder.SourceView(this.manager);
		var child = this.editor.get_first_child();
		while (child != null) {
			if (child is OLLMcoder.Diff.ReviewBar) {
				this.bar = (OLLMcoder.Diff.ReviewBar) child;
			}
			child = child.get_next_sibling();
		}
		this.check(command_line, this.bar != null, "review bar missing");

		var file = new OLLMfiles.File(this.manager) {
			path = this.file_path,
			is_text = true
		};
		if (file.buffer == null) {
			this.manager.buffer_provider.create_buffer(file);
		}
		((Gtk.TextBuffer) file.buffer).set_text("alpha\nbeta\ngamma\ndelta\n", -1);
		yield this.editor.open_file(file);

		var parts = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
		parts.add(new OLLMfiles.FileDiffPart() {
			id = 1,
			file_history_id = 3,
			accepted = 1,
			hunk_remove = "beta",
			hunk_add = "beta\n",
			old_line_start = 2,
			old_line_end = 2,
			new_line_start = 2,
			new_line_end = 2
		});
		parts.add(new OLLMfiles.FileDiffPart() {
			id = 2,
			file_history_id = 3,
			accepted = 1,
			hunk_remove = "gamma",
			hunk_add = "gamma\n",
			old_line_start = 3,
			old_line_end = 3,
			new_line_start = 3,
			new_line_end = 3
		});
		this.bar.parts = parts;
		this.bar.update_diff(parts, 0);

		var pending_rows = new Gee.ArrayList<OLLMfiles.FileWithHistory>();
		pending_rows.add(new OLLMfiles.FileWithHistory() {
			path = this.file_path,
			approve_id = 3
		});
		this.bar.sync_pending(pending_rows, file);
		this.check(command_line, this.bar.queue.size == 1,
			"queue while pending");

		var open_file = this.editor.current_file;
		this.check(command_line, open_file != null, "no open file");

		var empty = new Gee.ArrayList<OLLMfiles.FileWithHistory>();
		this.bar.sync_pending(empty, open_file);

		var nav_label = this.nav_button_label();
		command_line.print("stacked-widget queue=%d bar=%s nav=%s\n",
			this.bar.queue.size,
			this.bar.visible.to_string(),
			nav_label);

		this.check(command_line, this.editor.current_file != null &&
			this.editor.current_file.path == this.file_path,
			"editor file cleared after sync");
		this.check(command_line, this.bar.visible,
			"bar hidden");
		this.check(command_line, this.bar.queue.size == 0,
			"queue not empty after approve");
		this.check(command_line, nav_label == "Changes accepted",
			"bar label");
	}

	private string nav_button_label()
	{
		var walk = new Gee.ArrayList<Gtk.Widget>();
		walk.add(this.bar);
		if (this.bar.review_overlay != null) {
			walk.add(this.bar.review_overlay);
		}
		while (walk.size > 0) {
			var node = walk.get(0);
			walk.remove_at(0);
			var btn = node as Gtk.Button;
			if (btn != null) {
				var text = btn.label;
				if (text != null && text.contains("Changes accepted")) {
					return text;
				}
			}
			var ch = node.get_first_child();
			while (ch != null) {
				walk.add(ch);
				ch = ch.get_next_sibling();
			}
		}
		return "";
	}
}

int main(string[] args)
{
	return new StackedReviewWidgetTest().run(args);
}