/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Drives the real SourceView and review bar through a stub file server.
 */

/**
 * Editor review flow against the real widgets.
 *
 * A stub answers the file-server calls. The test opens a project that
 * already has a pending file, then a file that is not pending, then
 * finishes that pending file, then delivers a change notification.
 */
public class ReviewFlowTest : RpcTestAppBase, OLLMrpc.MockDispatch
{
	private OLLMfiles.ProjectManager manager;
	private OLLMcoder.SourceView editor;
	private OLLMcoder.Diff.ReviewBar bar;
	private OLLMrpc.Transport.SocketListen listen;
	private Gee.ArrayList<OLLMfiles.FileWithHistory> pending =
		new Gee.ArrayList<OLLMfiles.FileWithHistory>();
	private Gee.ArrayList<OLLMfiles.FileDiffPart> parts =
		new Gee.ArrayList<OLLMfiles.FileDiffPart>();
	private Gee.HashMap<string, string> bodies =
		new Gee.HashMap<string, string>();
	private Gee.ArrayList<string> calls = new Gee.ArrayList<string>();
	private int replies = 0;
	private string project_path = "/tmp/ollm-review-flow";

	public ReviewFlowTest()
	{
		base("com.roojs.ollmchat.test-review-flow");
	}

	protected override string get_app_name()
	{
		return "test-review-flow";
	}

	protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
	{
		this.fail(command_line, "run_test owns this flow");
	}

	/**
	 * Answer one file-server call from the scripted queue.
	 *
	 * @param request inbound call on the stub socket
	 * @return true after a reply
	 */
	public bool dispatch(OLLMrpc.Request request)
	{
		this.calls.add(request.method);
		switch (request.method) {
			case "RPC-Daemon.hello":
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", new OLLMrpc.Daemon() {
						ready = true,
						server = "review-flow"
					})
				});
				break;

			case "ProjectManager.rpc_activate_project":
				request.reply(new OLLMrpc.Response());
				break;

			case "Folder.fetch_pending_approvals":
				if (this.pending.size < 1) {
					request.reply(new OLLMrpc.Response() {
						msg = "10"
					});
					break;
				}
				var rows = new Gee.ArrayList<GLib.Object>();
				foreach (var row in this.pending) {
					rows.add(row);
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", rows),
					msg = "10"
				});
				break;

			case "File.read":
				var read_path = request.args.get(0).get_string();
				if (!this.bodies.has_key(read_path)) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("no body " + read_path)
					});
					break;
				}
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
				var history_id = request.args.get(0).get_int64();
				var matched = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
				foreach (var part in this.parts) {
					if (part.file_history_id != history_id) {
						continue;
					}
					matched.add(part);
				}
				if (matched.size < 1) {
					request.reply(new OLLMrpc.Response());
					break;
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", matched)
				});
				break;

			default:
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("unhandled " + request.method)
				});
				break;
		}
		this.replies++;
		return true;
	}

	protected override async void run_test(
		ApplicationCommandLine command_line,
		string[] remaining_args
	) throws Error
	{
		Gtk.init();
		OLLMfiles.rpc_register();
		OLLMrpc.Request.register_mock(this);
		var sock = GLib.Path.build_filename(GLib.Environment.get_tmp_dir(),
			"ollm-review-flow-" + GLib.get_monotonic_time().to_string() + ".sock");
		this.listen = new OLLMrpc.Transport.SocketListen(sock);
		this.check(command_line, this.listen.start(), "stub socket did not listen");
		this.manager = new OLLMfiles.ProjectManager();
		var rpc = new OLLMrpc.Client("", "review-flow.pid", sock);
		this.manager.replace_rpc(rpc);
		this.manager.buffer_provider = new OLLMcoder.BufferProvider();
		var connected = yield rpc.connect(new OLLMrpc.Request() {
			method = "RPC-Daemon.hello",
			args = OLLMrpc.args("is", 1, "review-flow")
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

		var pending_a = this.project_path + "/pending-a.vala";
		var pending_b = this.project_path + "/pending-b.vala";
		var pending_c = this.project_path + "/pending-c.vala";
		var readme_path = this.project_path + "/README.md";
		this.bodies.set(pending_a, "old line\n");
		this.bodies.set(pending_b, "bee line\n");
		this.bodies.set(pending_c, "cee line\n");
		this.bodies.set(readme_path, "readme body\n");
		this.pending.add(new OLLMfiles.FileWithHistory() {
			id = 1,
			path = pending_a,
			last_change_type = "modified",
			approve_id = 1,
			reject_id = 1
		});
		this.parts.add(this.hunk(1, "old line", "new line"));
		var project = new OLLMfiles.Folder(this.manager) {
			path = this.project_path,
			is_project = true
		};
		yield this.manager.activate_project(project, true);
		yield this.settle();
		command_line.print("activate %s\n", this.snapshot());
		this.check(command_line, this.editor.current_file == null,
			"activate opened a file " + this.snapshot());
		this.check(command_line, this.bar.visible && this.bar.parts.size == 0,
			"activate bar " + this.snapshot());
		this.check(command_line, this.accept_state() == "false",
			"activate accept shown " + this.snapshot());

		this.pending.clear();
		yield this.editor.open_file(new OLLMfiles.File(this.manager) {
			path = readme_path,
			is_text = true
		});
		yield this.settle();
		command_line.print("readme %s\n", this.snapshot());
		this.check(command_line, this.editor.current_file != null &&
			this.editor.current_file.path == readme_path,
			"readme stolen " + this.snapshot());
		this.check(command_line, this.editor.source_view.buffer.text.contains("readme body"),
			"readme buffer " + this.snapshot());
		this.check(command_line, this.bar.visible && this.bar.parts.size == 0 &&
			this.bar.queue.size == 1 &&
			this.bar.queue.get(0).path == pending_a,
			"readme bar " + this.snapshot());
		this.check(command_line, this.accept_state() == "false",
			"readme accept shown " + this.snapshot());

		yield this.editor.open_file(new OLLMfiles.File(this.manager) {
			path = pending_a,
			is_text = true
		});
		yield this.settle();
		command_line.print("pending-a %s\n", this.snapshot());
		this.check(command_line, this.editor.current_file != null &&
			this.editor.current_file.path == pending_a,
			"pending-a not open " + this.snapshot());
		this.check(command_line, this.bar.visible && this.accept_state() == "true" &&
			this.bar.parts.size == 1,
			"pending-a bar " + this.snapshot());

		this.pending.add(new OLLMfiles.FileWithHistory() {
			id = 1,
			path = pending_a,
			last_change_type = "modified",
			approve_id = 1,
			reviewed = 1
		});
		this.pending.add(new OLLMfiles.FileWithHistory() {
			id = 2,
			path = pending_b,
			last_change_type = "modified",
			approve_id = 2,
			reject_id = 2
		});
		this.parts.add(this.hunk(2, "bee line", "bee new"));
		yield this.manager.review_files.refresh();
		yield this.settle();
		command_line.print("advance %s\n", this.snapshot());
		this.check(command_line, this.editor.current_file != null &&
			this.editor.current_file.path == pending_b,
			"advance missed b " + this.snapshot());
		this.check(command_line, this.bar.visible && this.bar.parts.size == 1 &&
			this.bar.parts.get(0).file_history_id == 2,
			"advance bar " + this.snapshot());

		this.pending.clear();
		this.pending.add(new OLLMfiles.FileWithHistory() {
			id = 2,
			path = pending_b,
			last_change_type = "modified",
			approve_id = 2,
			reviewed = 1
		});
		yield this.manager.review_files.refresh();
		yield this.settle();
		command_line.print("close %s\n", this.snapshot());
		this.check(command_line, this.editor.current_file == null,
			"last file stayed open " + this.snapshot());
		this.check(command_line, !this.bar.visible,
			"bar stayed after the queue emptied " + this.snapshot());

		this.pending.clear();
		yield this.editor.open_file(new OLLMfiles.File(this.manager) {
			path = readme_path,
			is_text = true
		});
		yield this.settle();
		command_line.print("readme-again %s\n", this.snapshot());
		this.check(command_line, this.editor.current_file != null &&
			this.editor.current_file.path == readme_path,
			"empty queue stole readme " + this.snapshot());

		this.pending.add(new OLLMfiles.FileWithHistory() {
			id = 3,
			path = pending_c,
			last_change_type = "added",
			approve_id = 3,
			reject_id = 3
		});
		this.parts.add(this.hunk(3, "", "cee line"));
		this.listen.broadcast(new OLLMrpc.Notification() {
			method = "event.project.invalidate_cache",
			message = this.project_path
		});
		yield this.settle();
		command_line.print("notify %s\n", this.snapshot());
		this.check(command_line, this.editor.current_file != null &&
			this.editor.current_file.path == pending_c,
			"notification did not open c " + this.snapshot());
		this.check(command_line, this.bar.visible && this.bar.parts.size == 1 &&
			this.bar.parts.get(0).file_history_id == 3,
			"notification bar " + this.snapshot());
		this.listen.stop();
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

	private string accept_state()
	{
		var walk = new Gee.ArrayList<Gtk.Widget>();
		walk.add(this.bar);
		walk.add(this.bar.review_overlay);
		while (walk.size > 0) {
			var node = walk.get(0);
			walk.remove_at(0);
			var button = node as Gtk.Button;
			if (button != null && button.label == "Accept") {
				return button.visible.to_string();
			}
			var child = node.get_first_child();
			while (child != null) {
				walk.add(child);
				child = child.get_next_sibling();
			}
		}
		return "missing";
	}

	private string snapshot()
	{
		var path = "null";
		if (this.editor.current_file != null) {
			path = this.editor.current_file.path;
		}
		var history = "0";
		if (this.bar.parts.size > 0) {
			history = this.bar.parts.get(0).file_history_id.to_string();
		}
		return "path=%s bar=%s parts=%d history=%s accept=%s queue=%d".printf(
			path, this.bar.visible.to_string(), this.bar.parts.size, history,
			this.accept_state(), this.bar.queue.size);
	}

	private OLLMfiles.FileDiffPart hunk(int64 history_id, string removed, string added)
	{
		return new OLLMfiles.FileDiffPart() {
			id = history_id,
			file_history_id = history_id,
			hunk_remove = removed,
			hunk_add = added,
			old_line_start = 1,
			old_line_end = removed == "" ? 0 : 1,
			new_line_start = 1,
			new_line_end = added == "" ? 0 : 1
		};
	}
}

int main(string[] args)
{
	return new ReviewFlowTest().run(args);
}
