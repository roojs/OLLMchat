/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Emulates: open file → Accept three visible hunks → file fully approved, no second wave.
 * Stub server: full approve on last hunk + pending delta (reviewed=1 removal).
 */

public class StackedReviewScenarioTest : RpcTestAppBase, OLLMrpc.MockDispatch
{
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
		OLLMfiles.rpc_register();
		OLLMrpc.Request.register_mock(this);
		this.file_path = this.project_path + "/stacked.txt";
		this.bodies.set(this.file_path, "one\ntwo\nthree\nfour\n");

		var head_parts = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
		head_parts.add(this.hunk(3, 101, "three", "THREE"));
		head_parts.add(this.hunk(3, 102, "two", "TWO"));
		head_parts.add(this.hunk(3, 103, "one", "ONE"));
		this.parts_by_hist.set(3, head_parts);
		var older = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
		older.add(this.hunk(2, 201, "old", "OLD"));
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
			args = OLLMrpc.args("is", 1, "stacked-review-scenario")
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

		for (var step = 0; step < 3; step++) {
			command_line.print("step accept hunk %d of 3\n", step + 1);
			var part = this.bar.parts.get(step);
			yield this.accept_part(part.id);
			yield this.settle();
		}

		command_line.print("after third accept: queue=%d parts=%d approve_id=%lld\n",
			this.bar.queue.size,
			this.bar.parts.size,
			this.bar.queue.size > 0 ? this.bar.queue.get(0).approve_id : (int64) 0);
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
		this.listen.stop();
	}

	private async void accept_part(int64 part_id)
	{
		OLLMrpc.Response response;
		try {
			response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "FileDiffPart.apply",
				args = OLLMrpc.args("xi", part_id, 1)
			});
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
			return;
		}
		if (response.error != null) {
			GLib.warning("%s", response.error.message);
			return;
		}
		var chunk_open = false;
		foreach (var part in this.bar.parts) {
			if (part.id == part_id) {
				part.accepted = 1;
			}
			if (part.accepted == 0) {
				chunk_open = true;
			}
		}
		if (!chunk_open) {
			yield this.manager.review_files.refresh();
			if (this.editor.current_file != null &&
				this.manager.review_files.file_map.has_key(this.editor.current_file.path)) {
				yield this.editor.show_pending_diff(this.editor.current_file);
			}
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
		string removed,
		string added
	) {
		return new OLLMfiles.FileDiffPart() {
			id = part_id,
			file_history_id = history_id,
			hunk_remove = removed,
			hunk_add = added,
			old_line_start = 1,
			old_line_end = 1,
			new_line_start = 1,
			new_line_end = 1
		};
	}
}

int main(string[] args)
{
	return new StackedReviewScenarioTest().run(args);
}