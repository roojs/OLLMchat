/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Emulates: open file → Accept three visible hunks → file fully approved, no second wave.
 * Stub server: full approve on last hunk + pending delta (reviewed=1 removal).
 * ``--visual`` — Tier C window; click Accept on each hunk, then close.
 */

public class StackedReviewScenarioTest : RpcTestAppBase, OLLMrpc.MockDispatch
{
	private static bool opt_visual = false;
	private OLLMfiles.ProjectManager manager;
	private OLLMcoder.SourceView editor;
	private OLLMcoder.Diff.ReviewBar bar;
	private OLLMrpc.Transport.SocketListen listen;
	private Gee.ArrayList<OLLMfiles.FileWithHistory> pending =
		new Gee.ArrayList<OLLMfiles.FileWithHistory>();
	private Gee.HashMap<int, Gee.ArrayList<OLLMfiles.FileDiffPart>> parts_by_hist =
		new Gee.HashMap<int, Gee.ArrayList<OLLMfiles.FileDiffPart>>();
	private Gee.HashMap<string, string> bodies =
		new Gee.HashMap<string, string>();
	private int replies = 0;
	private string project_path = "/tmp/ollm-stacked-review-scenario";
	private string file_path;
	private bool head_chunk_closed;
	private Gee.ArrayList<OLLMfiles.FileWithHistory> pending_deltas =
		new Gee.ArrayList<OLLMfiles.FileWithHistory>();
	private int64 pending_marker = 10;
	private bool visual_close;
	private Gtk.Window visual_host;

	public StackedReviewScenarioTest()
	{
		base("com.roojs.ollmchat.test-stacked-review-scenario");
	}

	protected override string get_app_name()
	{
		return "test-stacked-review-scenario";
	}

	protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
	{
		this.fail(command_line, "run_test owns this flow");
	}

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var base_opts = new OptionEntry[4];
		base_opts[0] = base_options[0];
		base_opts[1] = base_options[1];
		base_opts[2] = { "visual", 0, 0, OptionArg.NONE, ref opt_visual,
			"Open editor window; manual Accept (Tier C sign-off)", null };
		base_opts[3] = { null };
		opt_context.add_main_entries(base_opts, null);
		return opt_context;
	}

	public bool dispatch(OLLMrpc.Request request)
	{
		this.replies++;
		switch (request.method) {
			case "RPC-Daemon.hello":
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", new OLLMrpc.Daemon() {
						ready = true,
						server = "stacked-review-scenario"
					})
				});
				break;

			case "ProjectManager.rpc_activate_project":
				request.reply(new OLLMrpc.Response());
				break;

			case "Folder.fetch_pending_approvals":
				if (this.pending_deltas.size > 0) {
					var deltas = new Gee.ArrayList<GLib.Object>();
					foreach (var row in this.pending_deltas) {
						deltas.add(row);
					}
					this.pending_deltas.clear();
					this.pending_marker++;
					request.reply(new OLLMrpc.Response() {
						retval = OLLMrpc.val("o", deltas),
						msg = this.pending_marker.to_string()
					});
					break;
				}
				if (this.pending.size < 1) {
					request.reply(new OLLMrpc.Response() {
						msg = this.pending_marker.to_string()
					});
					break;
				}
				var rows = new Gee.ArrayList<GLib.Object>();
				foreach (var row in this.pending) {
					rows.add(row);
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", rows),
					msg = this.pending_marker.to_string()
				});
				break;

			case "File.read":
				var read_path = request.args.get(0).get_string();
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", new OLLMfiles.File(this.manager) {
						path = read_path,
						is_text = true
					}),
					msg = this.bodies.get(read_path)
				});
				break;

			case "File.fetch":
				var fetch_path = request.args.get(1).get_string();
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", new OLLMfiles.File(this.manager) {
						path = fetch_path,
						is_text = true
					})
				});
				break;

			case "File.changed.check":
				request.reply(new OLLMrpc.Response() {
					msg = "0"
				});
				break;

			case "FileHistory.parts":
				var history_id = (int) request.args.get(0).get_int64();
				if (!this.parts_by_hist.has_key(history_id)) {
					request.reply(new OLLMrpc.Response());
					break;
				}
				var matched = this.parts_by_hist.get(history_id);
				if (matched.size < 1) {
					request.reply(new OLLMrpc.Response());
					break;
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", matched)
				});
				break;

			case "FileDiffPart.apply":
				var part_id = request.args.get(0).get_int64();
				var action = request.args.get(1).get_int();
				OLLMfiles.FileDiffPart? hit = null;
				foreach (var list in this.parts_by_hist.values) {
					foreach (var part in list) {
						if (part.id == part_id) {
							hit = part;
						}
					}
				}
				if (hit == null) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("unknown part")
					});
					break;
				}
				hit.accepted = action == 0 ? 0 : action;
				var chunk_open = false;
				foreach (var part in this.parts_by_hist.get((int) hit.file_history_id)) {
					if (part.accepted == 0) {
						chunk_open = true;
					}
				}
				if (!chunk_open && action == 1) {
					this.on_head_chunk_closed((int) hit.file_history_id);
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", hit)
				});
				break;

			default:
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("unhandled " + request.method)
				});
				break;
		}
		return true;
	}

	private void on_head_chunk_closed(int head_id)
	{
		this.head_chunk_closed = true;
		if (head_id != 3) {
			return;
		}
		if (this.pending.size > 0) {
			var row = this.pending.get(0);
			this.pending_deltas.add(new OLLMfiles.FileWithHistory() {
				id = row.id,
				path = row.path,
				last_change_type = row.last_change_type,
				reviewed = 1
			});
		}
		this.pending.clear();
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		Gtk.init();
		this.install_review_css();
		OLLMfiles.rpc_register();
		OLLMrpc.Request.register_mock(this);
		this.file_path = this.project_path + "/stacked.txt";
		this.bodies.set(this.file_path, "one\ntwo\nthree\nfour\n");

		var head_parts = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
		head_parts.add(this.hunk(3, 103, 1, "one", "ONE"));
		head_parts.add(this.hunk(3, 102, 2, "two", "TWO"));
		head_parts.add(this.hunk(3, 101, 3, "three", "THREE"));
		this.parts_by_hist.set(3, head_parts);
		var older = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
		older.add(this.hunk(2, 201, 1, "old", "OLD"));
		this.parts_by_hist.set(2, older);

		this.pending.add(new OLLMfiles.FileWithHistory() {
			id = 1,
			path = this.file_path,
			last_change_type = "modified",
			approve_id = 3
		});

		var sock = GLib.Path.build_filename(GLib.Environment.get_tmp_dir(),
			"ollm-stacked-review-scenario-"
				+ GLib.get_monotonic_time().to_string() + ".sock");
		this.listen = new OLLMrpc.Transport.SocketListen(sock);
		this.check(command_line, this.listen.start(), "stub socket did not listen");
		this.manager = new OLLMfiles.ProjectManager();
		var rpc = new OLLMrpc.Client("", "stacked-review-scenario.pid", sock);
		this.manager.replace_rpc(rpc);
		this.manager.buffer_provider = new OLLMcoder.BufferProvider();
		var connected = yield rpc.connect(new OLLMrpc.Request() {
			method = "RPC-Daemon.hello",
			args = OLLMrpc.args("iss", 1, "stacked-review-scenario", OLLMchat.VERSION)
		});
		this.check(command_line, connected, "connect failed " + rpc.connect_error);
		this.editor = new OLLMcoder.SourceView(this.manager);
		var child = this.editor.get_first_child();
		while (child != null) {
			if (child is OLLMcoder.Diff.ReviewBar) {
				this.bar = (OLLMcoder.Diff.ReviewBar) child;
			}
			child = child.get_next_sibling();
		}
		this.check(command_line, this.bar != null, "review bar missing");
		this.visual_host = new Gtk.Window() {
			visible = false,
			default_width = 1,
			default_height = 1,
		};
		this.visual_host.set_child(this.editor);
		this.visual_host.show();
		this.check(command_line, this.review_css_loaded(),
			"review CSS missing (bar bands render black)");

		var project = new OLLMfiles.Folder(this.manager) {
			path = this.project_path,
			is_project = true
		};
		yield this.manager.activate_project(project, true);
		yield this.manager.review_files.refresh();
		yield this.settle();

		command_line.print("step open file (three hunks on newest saved edit)\n");
		yield this.editor.open_file(new OLLMfiles.File(this.manager) {
			path = this.file_path,
			is_text = true
		});
		yield this.settle();
		this.check(command_line, this.bar.parts.size == 3,
			"expected three hunks on open");

		if (opt_visual) {
			var window = new Gtk.Window() {
				title = "Stacked review sign-off (Tier C)",
				default_width = 960,
				default_height = 720
			};
			this.visual_host.set_child(null);
			window.set_child(this.editor);
			window.close_request.connect(() => {
				this.visual_close = true;
				return false;
			});
			window.present();
			command_line.print(
				"Tier C: Accept each of the 3 hunks in the bar; "
					+ "queue should clear (\"Changes accepted\"), then close the window.\n");
			yield this.wait_until_visual_close();
		}
		if (!opt_visual) {
			for (var step = 0; step < 3; step++) {
				command_line.print("step accept hunk %d of 3\n", step + 1);
				yield this.accept_via_review_bar();
				this.check_after_accept_step(command_line, step + 1);
			}
		}

		this.check_stacked_outcome(command_line);
		this.listen.stop();
	}

	private void check_stacked_outcome(ApplicationCommandLine command_line) throws Error
	{
		command_line.print(
			"after last accept: queue=%d parts=%d\n",
			this.bar.queue.size,
			this.bar.parts.size);
		this.check(command_line, this.editor.current_file != null,
			"tab closed");
		this.check(command_line, this.bar.visible,
			"review bar hidden");
		this.check(command_line, this.bar.queue.size == 0,
			"file still on needs-review list after last visible accept");
		var second_wave = this.bar.parts.size > 0
			&& this.bar.parts.get(0).file_history_id != 3;
		this.check(command_line, !second_wave,
			"second diff wave loaded for same file");
		this.print_highlight_audit(command_line, "after 3 accepts");
		this.check(command_line, this.count_highlighted_lines() == 0,
			"source view still has diff highlights after 3 accepts");
		this.check_buffer_unchanged_lines(command_line, "after last accept");
	}

	private void check_after_accept_step(
		ApplicationCommandLine command_line,
		int step
	) throws Error
	{
		this.check(command_line, this.accepted_part_count() == step,
			"accepted hunk count after step %d".printf(step));
		for (var i = 0; i < this.bar.parts.size; i++) {
			var part = this.bar.parts.get(i);
			var line = part.new_line_start - 1;
			if (part.accepted != 0) {
				this.check(command_line, !this.line_has_diff_chrome(line),
					"hunk %lld line %d still highlighted after step %d".printf(
						part.id, line + 1, step));
				continue;
			}
			this.check(command_line, this.line_has_diff_chrome(line),
				"hunk %lld line %d missing diff after step %d".printf(
					part.id, line + 1, step));
		}
		this.print_highlight_audit(command_line,
			"after accept step %d".printf(step));
	}

	private void check_buffer_unchanged_lines(
		ApplicationCommandLine command_line,
		string where
	) throws Error
	{
		var gtk_buf = this.editor.source_view.buffer as GtkSource.Buffer;
		var lines = gtk_buf.text.split("\n");
		this.check(command_line, lines.length >= 4, where + " line count");
		this.check(command_line, lines[0] == "one", where + " line 1");
		this.check(command_line, lines[1] == "two", where + " line 2");
		this.check(command_line, lines[2] == "three", where + " line 3");
		this.check(command_line, lines[3] == "four", where + " line 4");
	}

	private int accepted_part_count()
	{
		var n = 0;
		foreach (var part in this.bar.parts) {
			if (part.accepted != 0) {
				n++;
			}
		}
		return n;
	}

	private void print_highlight_audit(
		ApplicationCommandLine command_line,
		string when
	)
	{
		var gtk_buf = this.editor.source_view.buffer as GtkSource.Buffer;
		var lines = gtk_buf.get_line_count();
		command_line.print("highlight audit (%s):\n", when);
		for (var line = 0; line < lines; line++) {
			command_line.print("  line %d: %s\n",
				line + 1, this.line_highlight_summary(line));
		}
	}

	private string line_highlight_summary(int line)
	{
		if (!this.line_has_diff_chrome(line)) {
			return "clean";
		}
		return this.line_diff_chrome_detail(line);
	}

	private string line_diff_chrome_detail(int line)
	{
		var gtk_buf = this.editor.source_view.buffer as GtkSource.Buffer;
		var bits = new string[] {};
		var remove_tag = gtk_buf.tag_table.lookup("diff-remove");
		var add_tag = gtk_buf.tag_table.lookup("diff-add");
		var add_active = gtk_buf.tag_table.lookup("diff-add-active");
		var remove_active = gtk_buf.tag_table.lookup("diff-remove-active");
		Gtk.TextIter iter;
		gtk_buf.get_iter_at_line(out iter, line);
		if (!iter.ends_line()) {
			iter.forward_to_line_end();
		}
		if (remove_tag != null && iter.has_tag(remove_tag)) {
			bits += "tag:diff-remove";
		}
		if (add_tag != null && iter.has_tag(add_tag)) {
			bits += "tag:diff-add";
		}
		if (remove_active != null && iter.has_tag(remove_active)) {
			bits += "tag:diff-remove-active";
		}
		if (add_active != null && iter.has_tag(add_active)) {
			bits += "tag:diff-add-active";
		}
		foreach (var mark in gtk_buf.get_source_marks_at_line(line, null)) {
			bits += "mark:" + mark.category;
		}
		if (bits.length == 0) {
			return "chrome?";
		}
		return string.joinv(", ", bits);
	}

	private bool line_has_diff_chrome(int line)
	{
		var gtk_buf = this.editor.source_view.buffer as GtkSource.Buffer;
		if (line < 0 || line >= gtk_buf.get_line_count()) {
			return false;
		}
		var remove_tag = gtk_buf.tag_table.lookup("diff-remove");
		var add_tag = gtk_buf.tag_table.lookup("diff-add");
		var add_active = gtk_buf.tag_table.lookup("diff-add-active");
		var remove_active = gtk_buf.tag_table.lookup("diff-remove-active");
		Gtk.TextIter iter;
		gtk_buf.get_iter_at_line(out iter, line);
		if (!iter.ends_line()) {
			iter.forward_to_line_end();
		}
		if (remove_tag != null && iter.has_tag(remove_tag)) {
			return true;
		}
		if (add_tag != null && iter.has_tag(add_tag)) {
			return true;
		}
		if (remove_active != null && iter.has_tag(remove_active)) {
			return true;
		}
		if (add_active != null && iter.has_tag(add_active)) {
			return true;
		}
		foreach (var mark in gtk_buf.get_source_marks_at_line(line, null)) {
			if (mark.category.has_prefix("diff-")) {
				return true;
			}
		}
		return false;
	}

	private int count_highlighted_lines()
	{
		var gtk_buf = this.editor.source_view.buffer as GtkSource.Buffer;
		var n = 0;
		for (var line = 0; line < gtk_buf.get_line_count(); line++) {
			if (!this.line_has_diff_chrome(line)) {
				continue;
			}
			n++;
		}
		return n;
	}

	private void install_review_css() throws Error
	{
		var css_provider = new Gtk.CssProvider();
		try {
			css_provider.load_from_resource("/ollmchat/style.css");
		} catch (GLib.Error e) {
			throw new GLib.IOError.FAILED(
				"load /ollmchat/style.css: %s", e.message);
		}
		Gtk.StyleContext.add_provider_for_display(
			Gdk.Display.get_default(),
			css_provider,
			Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
	}

	private bool review_css_loaded()
	{
		var child = this.bar.get_first_child();
		while (child != null) {
			if (child is Gtk.Label) {
				var label = (Gtk.Label) child;
				if (label.has_css_class("oc-diff-add")
					|| label.has_css_class("oc-diff-add-band")) {
					var rgba = label.get_color();
					return rgba.green > 0.85;
				}
			}
			child = child.get_next_sibling();
		}
		var fallback = new Gtk.Label("") {
			css_classes = { "oc-diff-add" },
		};
		this.visual_host.set_child(fallback);
		var rgba = fallback.get_color();
		this.visual_host.set_child(this.editor);
		return rgba.green > 0.85;
	}

	private async void accept_via_review_bar() throws Error
	{
		var before = this.accepted_part_count();
		var accept = this.find_accept_button(this.bar);
		if (accept != null) {
			accept.activate();
			yield this.wait_accept_done(before);
			return;
		}
		for (var i = 0; i < this.bar.parts.size; i++) {
			if (this.bar.parts.get(i).accepted != 0) {
				continue;
			}
			yield this.accept_via_rpc(this.bar.parts.get(i).id);
			return;
		}
		throw new GLib.IOError.FAILED("no pending hunk to accept");
	}

	private async void wait_accept_done(int accepted_before) throws Error
	{
		var deadline = GLib.get_monotonic_time() + 5 * 1000000;
		while (GLib.get_monotonic_time() < deadline) {
			if (this.accepted_part_count() <= accepted_before) {
				yield this.settle();
				continue;
			}
			yield this.settle();
			yield this.wait_parts_repaint_quiet();
			return;
		}
		throw new GLib.IOError.FAILED("accept did not finish");
	}

	private async void wait_parts_repaint_quiet() throws Error
	{
		var deadline = GLib.get_monotonic_time() + 3 * 1000000;
		while (GLib.get_monotonic_time() < deadline) {
			var ok = true;
			for (var i = 0; i < this.bar.parts.size; i++) {
				var part = this.bar.parts.get(i);
				if (part.accepted == 0) {
					continue;
				}
				if (this.line_has_diff_chrome(part.new_line_start - 1)) {
					ok = false;
					break;
				}
			}
			if (ok) {
				return;
			}
			yield this.settle();
		}
		throw new GLib.IOError.FAILED("accepted hunks still highlighted after repaint");
	}

	private async void accept_via_rpc(int64 part_id) throws Error
	{
		OLLMrpc.Response response = yield this.manager.rpc.call(
			new OLLMrpc.Request() {
				method = "FileDiffPart.apply",
				args = OLLMrpc.args("xi", part_id, 1)
			});
		if (response.error != null) {
			throw new GLib.IOError.FAILED("%s", response.error.message);
		}
		for (var i = 0; i < this.bar.parts.size; i++) {
			if (this.bar.parts.get(i).id != part_id) {
				continue;
			}
			this.bar.parts.set(
				i, (OLLMfiles.FileDiffPart) response.retval.get_object());
		}
		var chunk_open = false;
		foreach (var part in this.bar.parts) {
			if (part.accepted == 0) {
				chunk_open = true;
			}
		}
		var file = this.editor.current_file;
		if (file != null && chunk_open) {
			yield this.editor.show_pending_diff(file);
		}
		if (!chunk_open) {
			yield this.manager.review_files.refresh();
		}
		yield this.settle();
	}

	private Gtk.Button? find_accept_button(Gtk.Widget root)
	{
		if (root is Gtk.Button) {
			var btn = (Gtk.Button) root;
			if (this.button_is_accept(btn)) {
				return btn;
			}
		}
		var child = root.get_first_child();
		while (child != null) {
			var hit = this.find_accept_button(child);
			if (hit != null) {
				return hit;
			}
			child = child.get_next_sibling();
		}
		return null;
	}

	private bool button_is_accept(Gtk.Button btn)
	{
		if (btn.has_css_class("suggested-action")) {
			return true;
		}
		var label = btn.get_label();
		if (label != null && label == "Accept") {
			return true;
		}
		var child = btn.get_first_child();
		while (child != null) {
			if (child is Gtk.Label && ((Gtk.Label) child).get_label() == "Accept") {
				return true;
			}
			child = child.get_next_sibling();
		}
		return false;
	}

	private async void wait_until_visual_close()
	{
		while (!this.visual_close) {
			GLib.Timeout.add(200, () => {
				this.wait_until_visual_close.callback();
				return false;
			});
			yield;
		}
	}

	private async void settle()
	{
		var mark = this.replies;
		var quiet = 0;
		var deadline = GLib.get_monotonic_time() + 3 * 1000000;
		while (GLib.get_monotonic_time() < deadline && quiet < 8) {
			GLib.Idle.add(this.settle.callback);
			yield;
			if (this.replies != mark) {
				mark = this.replies;
				quiet = 0;
				continue;
			}
			quiet++;
		}
	}

	private OLLMfiles.FileDiffPart hunk(
		int64 history_id,
		int64 part_id,
		int line,
		string removed,
		string added
	) {
		return new OLLMfiles.FileDiffPart() {
			id = part_id,
			file_history_id = history_id,
			hunk_remove = removed,
			hunk_add = added,
			old_line_start = line,
			old_line_end = line,
			new_line_start = line,
			new_line_end = line
		};
	}
}

int main(string[] args)
{
	return new StackedReviewScenarioTest().run(args);
}