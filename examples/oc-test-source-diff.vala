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

#if ANDROID_SOURCE_DIFF
[CCode (cheader_filename = "android-gio-tls.h")]
extern bool ollmapp_configure_android_gio_tls_modules();
#endif

/**
 * Smoke: {@link TestAppBase} window showing {@link OLLMcoder.SourceView} inline diff
 * and {@link OLLMcoder.Diff.ReviewBar} Phase A mock review chrome.
 *
 * Usage: oc-test-source-diff [OPTIONS] <baseline> <current> [<baseline> <current> ...]
 * text1 = baseline (V_backup), text2 = current (V_disk).
 */
class TestSourceDiff : TestAppBase
{
	private static bool opt_mock_inactive = false;
	private static bool opt_selectors = false;
	private static bool opt_phone = false;
	private static bool opt_tablet = false;
	private static bool opt_test_flow = false;

	private Gtk.Window window;
	private Gtk.Box root_box;
	private Gtk.Overlay editor_overlay;
	private OLLMcoder.SourceView source_view;
	private OLLMcoder.Diff.ReviewBar review_bar;
	private string[] pair_baselines = {};
	private string[] pair_currents = {};
	private string[] pair_titles = {};
	private int current_file_index = 0;
	private int highlight_line = -2;
	private Gtk.Label add_swatch;
	private Gtk.Label remove_swatch;
	private Gtk.Label add_active_swatch;
	private Gtk.Label remove_active_swatch;
	private Gtk.Box selector_row;
	private SelectorPull selector_pull;
	private CoderView coder;
	private OLLMfiles.ProjectManager project_manager;
	private bool has_selector = false;
	private bool show_pull = false;

	protected override string help { get; set; default = """
Usage: {ARG} [OPTIONS] <baseline> <current> [<baseline> <current> ...]

Opens a window with SourceView.show_diff of the file pair(s) plus footer review bar.
Pass two or more baseline/current pairs to exercise real file prev/next in the footer.

Arguments:
  baseline_file              Old / backup text (Differ text1)
  current_file               New / disk text (Differ text2)
  ...                        Optional further baseline/current pairs

Options:
  --mock-inactive            Show "N changes pending review" instead of hunk bands
  --selectors                Selector subtest. Loads projects and files from filesd.
                             File pairs are optional in this mode.
  --phone                    Selector subtest, phone pull-over and file-name label
  --tablet                   Selector subtest, tablet pull-over and relative path
  --test-flow                Selector test flow. After the window is shown,
                             open the first project, press the type buttons,
                             and quit when that check finishes

Click a red or green line to make that hunk the deep color. Click unchanged
text to clear it and hide Accept and Reject. Shades are .oc-diff-add,
.oc-diff-remove, .oc-diff-add-active, and .oc-diff-remove-active in
resources/style.css (`color` is the line background).

Examples:
  {ARG} tests/source-diff/review-smoke-baseline.txt tests/source-diff/review-smoke-current.txt
  {ARG} tests/source-diff/review-smoke-baseline.txt tests/source-diff/review-smoke-current.txt \\
      tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt
  {ARG} --mock-inactive \\
      tests/source-diff/review-smoke-baseline.txt tests/source-diff/review-smoke-current.txt \\
      tests/source-diff/hello-baseline.txt tests/source-diff/hello-current.txt
  {ARG} --selectors
  {ARG} --test-flow
  {ARG} --phone
  {ARG} --tablet
"""; }

	public TestSourceDiff()
	{
		base("com.roojs.ollmchat.test-source-diff",
			GLib.ApplicationFlags.HANDLES_COMMAND_LINE |
			GLib.ApplicationFlags.NON_UNIQUE);
	}

	protected override string get_app_name()
	{
		return "oc-test-source-diff";
	}

	protected override OptionContext app_options()
	{
		var opt_context = new OptionContext(this.get_app_name());
		var opts = new OptionEntry[8];
		opts[0] = base_options[0];
		opts[1] = base_options[1];
		opts[2] = { "mock-inactive", 0, 0, OptionArg.NONE, ref opt_mock_inactive,
			"Show pending-review label instead of hunk bands", null };
		opts[3] = { "selectors", 0, 0, OptionArg.NONE, ref opt_selectors,
			"Selector subtest; load projects and files from filesd", null };
		opts[4] = { "phone", 0, 0, OptionArg.NONE, ref opt_phone,
			"Selector subtest with the phone pull-over", null };
		opts[5] = { "tablet", 0, 0, OptionArg.NONE, ref opt_tablet,
			"Selector subtest with the tablet pull-over", null };
		opts[6] = { "test-flow", 0, 0, OptionArg.NONE, ref opt_test_flow,
			"Selector test flow: open a project and check the type filter", null };
		opts[7] = { null };
		opt_context.add_main_entries(opts, null);
		return opt_context;
	}

	protected override string? validate_args(string[] args)
	{
#if ANDROID_SOURCE_DIFF
		if (!opt_tablet) {
			opt_phone = true;
		}
#endif
		if (opt_phone && opt_tablet) {
			return "ERROR: Pass only one of --phone or --tablet.\n";
		}
		if (opt_phone || opt_tablet || opt_test_flow) {
			opt_selectors = true;
		}
		if ((args.length - 1) % 2 != 0) {
			return "ERROR: File arguments must be baseline/current pairs (even count).\n";
		}
		if (!opt_selectors && (args.length < 3 || args[1] == "" || args[2] == "")) {
			return "ERROR: At least one baseline/current pair required.\nUsage: %s <baseline> <current> [...]\n".printf(args[0]);
		}
		return null;
	}

	/**
	 * Open the first project after the window is shown.
	 *
	 * Activates the first project row, then checks the type
	 * buttons. Nothing down shows every folder the ghost is
	 * showing, including an empty one. Code down hides folders
	 * with no code under them and turns documents off. Documents
	 * down does the same for documents. Selecting the project
	 * row loads its files, and clearing that selection drops
	 * them. The caller fails the run when the folder list stayed
	 * empty or a check failed.
	 *
	 * @param command_line Prints the project path and check lines
	 * @param loop Selector main loop to quit when the flow finishes
	 */
	private void test_flow(
		GLib.ApplicationCommandLine command_line,
		GLib.MainLoop loop
	) {
		var step = 0;
		GLib.Timeout.add(400, () => {
			if (step >= 200) {
				var files = this.coder.files.file_list.files;
				var scrolled = this.coder.files.folder_tree.get_first_child().get_next_sibling()
					as Gtk.ScrolledWindow;
				var selection = ((Gtk.ListView) scrolled.child).model as Gtk.SingleSelection;
				if ((selection.selected != Gtk.INVALID_LIST_POSITION || files.get_n_items() != 0) &&
					step < 210) {
					step++;
					return true;
				}
				if (selection.selected != Gtk.INVALID_LIST_POSITION || files.get_n_items() != 0) {
					command_line.printerr("deselect left files=%u selected=%u\n",
						files.get_n_items(), selection.selected);
					command_line.set_exit_status(1);
				}
				command_line.print("deselect files=%u selected=%u\n",
					files.get_n_items(), selection.selected);
				loop.quit();
				return false;
			}
			if (step >= 100) {
				var files = this.coder.files.file_list.files;
				if (!files.empty && files.get_n_items() == 0 && step < 160) {
					step++;
					return true;
				}
				if (!files.empty && files.get_n_items() == 0) {
					command_line.printerr("select loaded no files\n");
					command_line.set_exit_status(1);
					loop.quit();
					return false;
				}
				command_line.print("select files=%u\n", files.get_n_items());
				this.window.title = "oc-test-flow-deselect";
				this.window.present();
				var scrolled = this.coder.files.folder_tree.get_first_child().get_next_sibling()
					as Gtk.ScrolledWindow;
				var list = (Gtk.ListView) scrolled.child;
				var spot = Graphene.Point();
				spot.x = 80;
				spot.y = 12;
				var at = Graphene.Point();
				if (!list.compute_point(this.window, spot, out at)) {
					command_line.printerr("row point missing\n");
					command_line.set_exit_status(1);
					loop.quit();
					return false;
				}
				var click_at = ("xdotool search --name oc-test-flow-deselect " +
					"windowraise %%1 windowfocus %%1 sleep 0.05 " +
					"mousemove --window %%1 %d %d click 1").printf((int) at.x, (int) at.y);
				var click_status = 0;
				try {
					GLib.Process.spawn_command_line_sync(click_at, null, null, out click_status);
				} catch (GLib.Error e) {
					command_line.printerr("click failed %s\n", e.message);
					command_line.set_exit_status(1);
					loop.quit();
					return false;
				}
				if (click_status != 0) {
					command_line.printerr("click status %d\n", click_status);
					command_line.set_exit_status(1);
					loop.quit();
					return false;
				}
				command_line.print("click %d %d\n", (int) at.x, (int) at.y);
				step = 200;
				return true;
			}
			if (step == 0) {
				this.coder.projects.button.clicked();
				step = 1;
				return true;
			}
			if (step == 1) {
				var line = this.coder.projects.rows.get_row_at_index(0);
				var index = 0;
				while (line != null && !line.activatable) {
					index++;
					line = this.coder.projects.rows.get_row_at_index(index);
				}
				if (line == null) {
					command_line.printerr("no project row\n");
					command_line.set_exit_status(1);
					loop.quit();
					return false;
				}
				var picked = line.get_child().get_data<OLLMfiles.Folder>("folder");
				if (picked != null) {
					command_line.print("project %s\n", picked.path);
				}
				this.coder.projects.rows.row_activated(line);
				step = 2;
				return true;
			}
			step++;
			var count = this.coder.files.folder_tree.folders.flat.size;
			if ((count == 0 || this.coder.files.folder_tree.folders.loading) && step < 40) {
				return true;
			}
			command_line.print("folders=%u loading=%s\n", count,
				this.coder.files.folder_tree.folders.loading.to_string());
			if (count == 0 || this.coder.files.folder_tree.folders.loading) {
				command_line.set_exit_status(1);
				loop.quit();
				return false;
			}
			var scrolled = this.coder.files.folder_tree.get_first_child().get_next_sibling()
				as Gtk.ScrolledWindow;
			var selection = ((Gtk.ListView) scrolled.child).model as Gtk.SingleSelection;
			var shown = selection.model as Gtk.TreeListModel;
			var first = "";
			var previous = "";
			var saw = false;
			var n = shown.get_n_items();
			for (var i = 0; i < n; i++) {
				var row = (Gtk.TreeListRow) shown.get_item(i);
				if (row.depth != 0) {
					continue;
				}
				var name = ((OLLMfiles.Folder) row.item).path_basename;
				if (!saw) {
					first = name;
				}
				if (saw && previous.casefold().collate(name.casefold()) > 0) {
					command_line.printerr("unsorted %s then %s\n", previous, name);
					command_line.set_exit_status(1);
				}
				previous = name;
				saw = true;
			}
			if (!saw) {
				command_line.printerr("no root rows\n");
				command_line.set_exit_status(1);
			}
			command_line.print("order=%s .. %s\n", first, previous);
			if (this.coder.files.code.icon_name != "completion-snippet-symbolic") {
				command_line.printerr("code icon %s\n", this.coder.files.code.icon_name);
				command_line.set_exit_status(1);
			}
			if (this.coder.files.code.active || this.coder.files.documents.active) {
				command_line.printerr("type button started down\n");
				command_line.set_exit_status(1);
			}
			if (this.coder.files.folder_tree.kind != FileKind.ANY) {
				command_line.printerr("kind started as %s\n",
					this.coder.files.folder_tree.kind.to_string());
				command_line.set_exit_status(1);
			}
			/* Ghost starts hiding empty folders. Show them so the
			 * type buttons have an empty row to remove. */
			this.coder.files.folder_tree.ghost.clicked();
			var store = this.coder.files.folder_tree.folders;
			var code_kept = "";
			var code_dropped = "";
			var doc_kept = "";
			var doc_dropped = "";
			var empty_shown = "";
			var open_n = shown.get_n_items();
			for (var i = 0; i < open_n; i++) {
				var row = (Gtk.TreeListRow) shown.get_item(i);
				var folder = (OLLMfiles.Folder) row.item;
				if (folder.is_project) {
					continue;
				}
				if (folder.file_count == 0 && folder.folder_count == 0 && empty_shown == "") {
					empty_shown = folder.path;
				}
				var code_match = false;
				var doc_match = false;
				var pending = new Gee.ArrayList<OLLMfiles.Folder>();
				pending.add(folder);
				var at = 0;
				while (at < pending.size) {
					var next = pending.get(at);
					at++;
					if (next.code_count > 0) {
						code_match = true;
					}
					if (next.document_count > 0) {
						doc_match = true;
					}
					if (!store.segments.has_key(next.path)) {
						continue;
					}
					var child_at = 0;
					var children = store.segments.get(next.path);
					while (child_at < children.get_n_items()) {
						pending.add((OLLMfiles.Folder) children.get_item(child_at));
						child_at++;
					}
				}
				if (code_match && code_kept == "") {
					code_kept = folder.path;
				}
				if (!code_match && folder.file_count > 0 && code_dropped == "") {
					code_dropped = folder.path;
				}
				if (doc_match && doc_kept == "") {
					doc_kept = folder.path;
				}
				if (!doc_match && folder.file_count > 0 && doc_dropped == "") {
					doc_dropped = folder.path;
				}
			}
			command_line.print("type=off shown=%u\n", open_n);
			if (code_kept == "" || code_dropped == "" || doc_kept == "" || doc_dropped == "") {
				command_line.printerr("type sample code=%s without=%s doc=%s without=%s\n",
					code_kept, code_dropped, doc_kept, doc_dropped);
				command_line.set_exit_status(1);
				loop.quit();
				return false;
			}
			if (empty_shown == "") {
				command_line.printerr("no empty folder\n");
				command_line.set_exit_status(1);
				loop.quit();
				return false;
			}
			this.coder.files.code.clicked();
			var code_bad = "";
			var code_visible = new Gee.HashSet<string>();
			var code_n = shown.get_n_items();
			for (var i = 0; i < code_n; i++) {
				var row = (Gtk.TreeListRow) shown.get_item(i);
				var folder = (OLLMfiles.Folder) row.item;
				code_visible.add(folder.path);
				if (folder.is_project) {
					continue;
				}
				if (code_bad != "") {
					continue;
				}
				if (folder.file_count == 0 && folder.folder_count == 0) {
					code_bad = folder.path;
					continue;
				}
				var code_match = false;
				var pending = new Gee.ArrayList<OLLMfiles.Folder>();
				pending.add(folder);
				var at = 0;
				while (at < pending.size && !code_match) {
					var next = pending.get(at);
					at++;
					if (next.code_count > 0) {
						code_match = true;
						continue;
					}
					if (!store.segments.has_key(next.path)) {
						continue;
					}
					var child_at = 0;
					var children = store.segments.get(next.path);
					while (child_at < children.get_n_items()) {
						pending.add((OLLMfiles.Folder) children.get_item(child_at));
						child_at++;
					}
				}
				if (!code_match) {
					code_bad = folder.path;
				}
			}
			command_line.print("type=code shown=%u\n", code_n);
			if (!this.coder.files.code.active || this.coder.files.documents.active) {
				command_line.printerr("code press documents=%s code=%s\n",
					this.coder.files.documents.active.to_string(),
					this.coder.files.code.active.to_string());
				command_line.set_exit_status(1);
			}
			if (this.coder.files.folder_tree.kind != FileKind.CODE ||
				this.coder.files.file_list.kind != FileKind.CODE) {
				command_line.printerr("code kind %s %s\n",
					this.coder.files.folder_tree.kind.to_string(),
					this.coder.files.file_list.kind.to_string());
				command_line.set_exit_status(1);
			}
			if (!code_visible.contains(code_kept) || code_visible.contains(code_dropped) ||
				code_visible.contains(empty_shown) || code_bad != "") {
				command_line.printerr("code filter kept=%s dropped=%s empty=%s bad=%s\n",
					code_visible.contains(code_kept).to_string(),
					code_visible.contains(code_dropped).to_string(),
					code_visible.contains(empty_shown).to_string(), code_bad);
				command_line.set_exit_status(1);
			}
			this.coder.files.documents.clicked();
			var doc_bad = "";
			var doc_visible = new Gee.HashSet<string>();
			var doc_n = shown.get_n_items();
			for (var i = 0; i < doc_n; i++) {
				var row = (Gtk.TreeListRow) shown.get_item(i);
				var folder = (OLLMfiles.Folder) row.item;
				doc_visible.add(folder.path);
				if (folder.is_project) {
					continue;
				}
				if (doc_bad != "") {
					continue;
				}
				if (folder.file_count == 0 && folder.folder_count == 0) {
					doc_bad = folder.path;
					continue;
				}
				var doc_match = false;
				var pending = new Gee.ArrayList<OLLMfiles.Folder>();
				pending.add(folder);
				var at = 0;
				while (at < pending.size && !doc_match) {
					var next = pending.get(at);
					at++;
					if (next.document_count > 0) {
						doc_match = true;
						continue;
					}
					if (!store.segments.has_key(next.path)) {
						continue;
					}
					var child_at = 0;
					var children = store.segments.get(next.path);
					while (child_at < children.get_n_items()) {
						pending.add((OLLMfiles.Folder) children.get_item(child_at));
						child_at++;
					}
				}
				if (!doc_match) {
					doc_bad = folder.path;
				}
			}
			command_line.print("type=document shown=%u\n", doc_n);
			if (!this.coder.files.documents.active || this.coder.files.code.active) {
				command_line.printerr("document press documents=%s code=%s\n",
					this.coder.files.documents.active.to_string(),
					this.coder.files.code.active.to_string());
				command_line.set_exit_status(1);
			}
			if (this.coder.files.folder_tree.kind != FileKind.DOCUMENT ||
				this.coder.files.file_list.kind != FileKind.DOCUMENT) {
				command_line.printerr("document kind %s %s\n",
					this.coder.files.folder_tree.kind.to_string(),
					this.coder.files.file_list.kind.to_string());
				command_line.set_exit_status(1);
			}
			if (!doc_visible.contains(doc_kept) || doc_visible.contains(doc_dropped) ||
				doc_visible.contains(empty_shown) || doc_bad != "") {
				command_line.printerr("document filter kept=%s dropped=%s empty=%s bad=%s\n",
					doc_visible.contains(doc_kept).to_string(),
					doc_visible.contains(doc_dropped).to_string(),
					doc_visible.contains(empty_shown).to_string(), doc_bad);
				command_line.set_exit_status(1);
			}
			this.coder.files.documents.clicked();
			var cleared = new Gee.HashSet<string>();
			var cleared_n = shown.get_n_items();
			for (var i = 0; i < cleared_n; i++) {
				var row = (Gtk.TreeListRow) shown.get_item(i);
				cleared.add(((OLLMfiles.Folder) row.item).path);
			}
			command_line.print("type=off shown=%u\n", cleared_n);
			if (this.coder.files.documents.active || this.coder.files.code.active ||
				this.coder.files.folder_tree.kind != FileKind.ANY) {
				command_line.printerr("type stayed down kind=%s\n",
					this.coder.files.folder_tree.kind.to_string());
				command_line.set_exit_status(1);
			}
			if (!cleared.contains(code_dropped) || !cleared.contains(doc_dropped) ||
				!cleared.contains(empty_shown)) {
				command_line.printerr("cleared hid code=%s doc=%s empty=%s\n",
					cleared.contains(code_dropped).to_string(),
					cleared.contains(doc_dropped).to_string(),
					cleared.contains(empty_shown).to_string());
				command_line.set_exit_status(1);
			}
			this.window.title = "oc-test-flow-deselect";
			selection.selected = 0;
			step = 100;
			return true;
		});
	}

	protected override async void run_test(ApplicationCommandLine command_line, string[] args) throws Error
	{
#if ANDROID_SOURCE_DIFF
		var activity_ready = false;
		this.activate.connect(() => {
			activity_ready = true;
		});
#endif
		if (!Gtk.init_check()) {
			command_line.printerr("ERROR: Failed to initialize GTK (no display?)\n");
			throw new GLib.IOError.FAILED("Failed to initialize GTK");
		}
#if ANDROID_SOURCE_DIFF
		ollmapp_configure_android_gio_tls_modules();
#endif
		var css_provider = new Gtk.CssProvider();
		css_provider.load_from_resource("/ollmchat/style.css");
		Gtk.StyleContext.add_provider_for_display(
			Gdk.Display.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		var pair_count = (args.length - 1) / 2;
		for (var pi = 0; pi < pair_count; pi++) {
			var baseline_arg = args[1 + pi * 2];
			var current_arg = args[2 + pi * 2];
			var baseline_path = GLib.Path.is_absolute(baseline_arg)
				? baseline_arg
				: GLib.Path.build_filename(GLib.Environment.get_current_dir(), baseline_arg);
			var current_path = GLib.Path.is_absolute(current_arg)
				? current_arg
				: GLib.Path.build_filename(GLib.Environment.get_current_dir(), current_arg);
			var baseline = "";
			var current = "";
			GLib.FileUtils.get_contents(baseline_path, out baseline);
			GLib.FileUtils.get_contents(current_path, out current);
			this.pair_baselines += baseline;
			this.pair_currents += current;
			this.pair_titles += "%s → %s".printf(
				GLib.Path.get_basename(baseline_path),
				GLib.Path.get_basename(current_path));
		}
		if (opt_selectors) {
			OLLMfiles.rpc_register();
			var manager = new OLLMfiles.ProjectManager();
			this.project_manager = manager;
			var connected = false;
#if ANDROID_SOURCE_DIFF
			this.window = new Gtk.Window() {
				title = "Selectors",
				default_width = 400,
				default_height = 700,
			};
			var startup_status = new Gtk.Label("Connecting…") {
				margin_top = 8,
				halign = Gtk.Align.CENTER,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD,
				max_width_chars = 40,
			};
			var startup_spinner = new Gtk.Spinner() {
				halign = Gtk.Align.CENTER,
			};
			startup_spinner.start();
			var startup_panel = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				vexpand = true,
			};
			startup_panel.append(startup_spinner);
			startup_panel.append(startup_status);
			this.window.child = startup_panel;
			if (activity_ready) {
				this.window.present();
			}
			if (!activity_ready) {
				this.activate.connect(() => {
					this.window.present();
				});
			}
			OLLMchat.Settings.Config2.config_path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "ollmchat", "config.2.json");
			if (GLib.FileUtils.test(
				OLLMchat.Settings.Config2.config_path, GLib.FileTest.EXISTS)) {
				var saved = OLLMchat.Settings.Config2.load();
				var check = false;
				switch (saved.filesd_client.state) {
					case OLLMchat.Settings.FilesdClient.State.ENABLED:
					case OLLMchat.Settings.FilesdClient.State.LIVE:
					case OLLMchat.Settings.FilesdClient.State.SOCKET:
						check = saved.filesd_client.addresses != "";
						break;
					default:
						break;
				}
				if (check && GLib.Uuid.string_is_valid(saved.filesd_client.server_id)) {
					startup_status.label = "Checking desktop environment…";
					var tls = new OLLMrpc.Transport.Cert() {
						dir = GLib.Path.build_filename(
							GLib.Environment.get_user_data_dir(), "ollmchat",
							saved.filesd_client.server_id),
						cert_pem = "client.pem",
						key_pem = "client-key.pem",
						cn = "ollmchat-device",
					};
					tls.ensure();
					var lines = saved.filesd_client.addresses.split("\n");
					for (var i = 0; i < lines.length; i++) {
						var line = lines[i].strip();
						var colon = line.last_index_of(":");
						if (colon <= 0) {
							continue;
						}
						var port = 0;
						if (!int.try_parse(line.substring(colon + 1), out port)) {
							continue;
						}
						var host = line.substring(0, colon);
						var client = new GLib.SocketClient();
						client.timeout = 2;
						GLib.SocketConnection conn;
						try {
							conn = yield client.connect_to_host_async(
								host, (uint16) port, null);
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							continue;
						}
						try {
							conn.socket.blocking = true;
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							continue;
						}
						GLib.TlsClientConnection link;
						try {
							link = GLib.TlsClientConnection.@new(conn, null);
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							continue;
						}
						link.certificate = tls.certificate;
						link.database = tls.trust;
						link.accept_certificate.connect((peer_cert, errors) => {
							return peer_cert != null
								&& (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
						});
						try {
							link.handshake();
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							continue;
						}
						OLLMrpc.Bin.Stream bin;
						try {
							bin = new OLLMrpc.Bin.Stream(
								new GLib.DataInputStream(link.get_input_stream()),
								new GLib.DataOutputStream(link.get_output_stream())
							);
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							continue;
						}
						try {
							bin.write(new OLLMrpc.Request() {
								method = "RPC-Daemon.hello",
								args = OLLMrpc.args("is", 1, "oc-test-source-diff")
							});
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							continue;
						}
						OLLMrpc.Response? hello = null;
						var hello_wait = GLib.get_monotonic_time() + 10 * 1000000;
						while (hello == null) {
							try {
								hello = bin.parse() as OLLMrpc.Response;
							} catch (GLib.IOError e) {
								if (e.code != GLib.IOError.WOULD_BLOCK
									|| GLib.get_monotonic_time() >= hello_wait) {
									GLib.warning("%s", e.message);
									break;
								}
								var hello_poll = GLib.PollFD();
								hello_poll.fd = conn.socket.fd;
								hello_poll.events = GLib.IOCondition.IN;
								GLib.poll(new GLib.PollFD[] { hello_poll }, 200);
							} catch (GLib.Error e) {
								GLib.warning("%s", e.message);
								break;
							}
						}
						if (hello == null || hello.error != null) {
							continue;
						}
						saved.filesd_client.url =
							"tcp://" + host + ":" + port.to_string();
						var rpc = new OLLMrpc.Client("", "", saved.filesd_client.url);
						rpc.configure_tls.connect((connection) => {
							connection.certificate = tls.certificate;
							connection.database = tls.trust;
						});
						manager.replace_rpc(rpc);
						connected = yield rpc.connect(new OLLMrpc.Request() {
							method = "RPC-Daemon.hello",
							args = OLLMrpc.args("is", 1, "oc-test-source-diff")
						});
						if (!connected) {
							continue;
						}
						saved.filesd_client.state =
							OLLMchat.Settings.FilesdClient.State.LIVE;
						saved.save();
						break;
					}
				}
			}
			if (connected) {
				startup_status.label = "Opening…";
			}
#endif
#if !ANDROID_SOURCE_DIFF
			if (!connected) {
				connected = yield manager.rpc.connect(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "oc-test-source-diff")
				}, new OLLMrpc.ClientBoot());
			}
#endif
			if (!connected) {
				var msg = manager.rpc.connect_error;
				if (msg == "") {
					msg = "could not start or reach the filesystem daemon (ollmfilesd)";
				}
#if ANDROID_SOURCE_DIFF
				GLib.warning("file server: %s", msg);
#else
				throw new GLib.IOError.FAILED("%s", msg);
#endif
			}
			if (connected) {
				yield manager.rpc_load_projects_from_db();
			}
			var form = "desktop";
			if (opt_phone) {
				form = "phone";
			}
			if (opt_tablet) {
				form = "tablet";
			}
			this.show_pull = form != "desktop";
			if (this.pair_baselines.length == 0) {
				var coder = new CoderView(manager, form);
				this.selector_pull = coder.pull;
				this.coder = coder;
			}
			if (this.pair_baselines.length > 0) {
				this.selector_pull = new SelectorPull(form);
				this.selector_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
					valign = Gtk.Align.START,
					margin_start = 6,
					margin_end = 6,
					margin_top = 4,
					margin_bottom = 4,
				};
				var projects = new ProjectSelector(manager, form, this.selector_pull);
				var files = form == "desktop"
					? (FileNav) new FileOverlay(manager)
					: (FileNav) new FilePullout(manager, form, this.selector_pull);
				var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
					hexpand = true,
				};
				this.selector_row.append(projects);
				this.selector_row.append(spacer);
				this.selector_row.append(files);
				files.notify["visible"].connect(() => {
					spacer.visible = !files.visible;
				});
				projects.opened.connect(() => {
					if (form != "desktop") {
						return;
					}
					((FileOverlay) files).list.visible = false;
				});
				files.opened.connect(() => {
					projects.list.visible = false;
				});
				projects.chosen.connect((folder) => {
					files.project = folder;
				});
				this.has_selector = true;
			}
		}
		if (this.pair_baselines.length == 0) {
#if !ANDROID_SOURCE_DIFF
			this.window = new Gtk.Window() {
				title = "Selectors",
				default_width = 720,
				default_height = 520,
			};
			if (opt_phone) {
				this.window.default_width = 400;
				this.window.default_height = 700;
			}
#endif
			var host = this.coder as Gtk.Widget;
#if ANDROID_SOURCE_DIFF
			var configure_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				halign = Gtk.Align.END,
				margin_end = 6,
				margin_top = 4,
			};
			var configure = new Gtk.Button.from_icon_name("applications-system-symbolic") {
				tooltip_text = "Settings",
				hexpand = false,
				valign = Gtk.Align.CENTER,
			};
			configure.add_css_class("flat");
			configure_row.append(configure);
			var file_add = new OLLMapp.SettingsDialog.FileConnectionAdd();
			configure.clicked.connect(() => {
				file_add.show_add();
				file_add.present(this.window);
			});
			file_add.dialog_closed.connect(() => {
				var paired_url = file_add.registered_url;
				if (paired_url == null) {
					return;
				}
				OLLMchat.Settings.Config2.config_path = GLib.Path.build_filename(
					GLib.Environment.get_user_config_dir(), "ollmchat", "config.2.json");
				var saved = new OLLMchat.Settings.Config2();
				if (GLib.FileUtils.test(
					OLLMchat.Settings.Config2.config_path, GLib.FileTest.EXISTS)) {
					saved = OLLMchat.Settings.Config2.load();
				}
				saved.filesd_client.url = paired_url;
				saved.filesd_client.addresses = file_add.registered_addresses;
				saved.filesd_client.server_id = file_add.server_id;
				saved.filesd_client.state = OLLMchat.Settings.FilesdClient.State.ENABLED;
				saved.save();
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat",
						saved.filesd_client.server_id),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
				};
				tls.ensure();
				var rpc = new OLLMrpc.Client("", "", saved.filesd_client.url);
				rpc.configure_tls.connect((connection) => {
					connection.certificate = tls.certificate;
					connection.database = tls.trust;
				});
				this.project_manager.replace_rpc(rpc);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "oc-test-source-diff")
				};
				rpc.connect.begin(hello, null, (obj, res) => {
					if (!rpc.connect.end(res)) {
						GLib.warning("file server: %s", rpc.connect_error);
						return;
					}
					saved.filesd_client.state = OLLMchat.Settings.FilesdClient.State.LIVE;
					saved.save();
					this.project_manager.rpc_load_projects_from_db.begin((load_obj, load_res) => {
						try {
							this.project_manager.rpc_load_projects_from_db.end(load_res);
						} catch (GLib.Error e) {
							GLib.warning("file server: %s", e.message);
						}
					});
				});
			});
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			column.append(configure_row);
			column.append(this.coder);
			host = column;
#endif
			if (!this.show_pull) {
				this.window.child = host;
			}
			if (this.show_pull) {
				var cover = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
				};
				cover.set_child(host);
				cover.add_overlay(this.selector_pull);
				this.window.child = cover;
			}
			var selector_loop = new GLib.MainLoop();
			this.window.close_request.connect(() => {
				selector_loop.quit();
				return false;
			});
#if !ANDROID_SOURCE_DIFF
			this.window.present();
#endif
		if (opt_test_flow) {
			this.test_flow(command_line, selector_loop);
		}
		// The load-projects reply resumes this method inside the
		// socket read callback. Running the window loop there holds
		// that callback, so the activate reply is never read.
		GLib.Idle.add(() => {
			selector_loop.run();
			this.run_test.callback();
			return false;
		});
		yield;
		if (opt_test_flow && this.coder.files.folder_tree.folders.flat.size == 0) {
			throw new GLib.IOError.FAILED("folder list stayed empty");
		}
		return;
		}
		this.window = new Gtk.Window() {
			title = this.pair_titles[0],
			default_width = 720,
			default_height = 520
		};
		this.source_view = new OLLMcoder.SourceView(new OLLMfiles.ProjectManager()) {
			hexpand = true,
			vexpand = true,
		};
		this.review_bar = new OLLMcoder.Diff.ReviewBar(
			this.source_view, pair_count, opt_mock_inactive, 0, this.pair_titles);
		var review_responses = new Gee.ArrayList<OLLMcoder.Diff.ReviewResponse>();
		review_responses.add(new OLLMcoder.Diff.ReviewResponse() {
			label = "Coding standards",
			prompt = "This section of code does not follow coding standards. "
				+ "Please refer to docs/coding-standards-router.md and the mapped "
				+ "sections in docs/coding-standards.md.",
			tooltip = "Report coding standards issue for this hunk",
			is_bulk = false,
		});
		review_responses.add(new OLLMcoder.Diff.ReviewResponse() {
			label = "Helper methods (whole file)",
			prompt = "This file contains helper methods that were not requested. "
				+ "Do not add helper methods unless the user or plan names them.",
			tooltip = "Report unauthorized helper methods for the whole file",
			is_bulk = true,
		});
		this.review_bar.responses(review_responses);
		this.add_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-add" },
			visible = false,
		};
		this.remove_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-remove" },
			visible = false,
		};
		this.add_active_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-add-active" },
			visible = false,
		};
		this.remove_active_swatch = new Gtk.Label("") {
			css_classes = { "oc-diff-remove-active" },
			visible = false,
		};
		this.review_bar.file_index_changed.connect((index) => {
			if (index < 0 || index >= this.pair_baselines.length) {
				return;
			}
			this.current_file_index = index;
			this.highlight_line = -2;
			this.window.title = this.pair_titles[index];
			var differ = new OLLMfiles.Diff.Differ(
				this.pair_baselines[index], this.pair_currents[index]);
			this.source_view.show_diff(differ);
			this.review_bar.update_diff_old(differ, index);
			this.apply_highlight();
		});
		this.editor_overlay = new Gtk.Overlay() {
			vexpand = true,
			hexpand = true,
		};
		this.editor_overlay.set_child(this.source_view);
		this.editor_overlay.add_overlay(this.review_bar.review_overlay);
		if (this.has_selector) {
			var projects = (ProjectSelector) this.selector_row.get_first_child();
			this.editor_overlay.add_overlay(projects.shade);
			this.editor_overlay.add_overlay(projects.list);
			if (!this.show_pull) {
				this.editor_overlay.add_overlay(
					((FileOverlay) this.selector_row.get_last_child()).list);
			}
		}
		this.root_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			hexpand = true,
			vexpand = true,
		};
		this.root_box.append(this.editor_overlay);
		this.root_box.append(this.review_bar);
		this.root_box.append(this.add_swatch);
		this.root_box.append(this.remove_swatch);
		this.root_box.append(this.add_active_swatch);
		this.root_box.append(this.remove_active_swatch);
		if (this.has_selector) {
			this.root_box.prepend(this.selector_row);
		}
		if (!this.show_pull) {
			this.window.set_child(this.root_box);
		}
		if (this.show_pull) {
			var cover = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
			};
			cover.set_child(this.root_box);
			cover.add_overlay(this.selector_pull);
			this.window.set_child(cover);
		}
		var text_view = (GtkSource.View) ((Gtk.ScrolledWindow) ((Gtk.Overlay) this.source_view
			.get_first_child().get_next_sibling()).get_child()).child;
		var hunk_click = new Gtk.GestureClick();
		hunk_click.pressed.connect((n_press, x, y) => {
			if (n_press < 1) {
				return;
			}
			var bx = 0;
			var by = 0;
			text_view.window_to_buffer_coords(
				Gtk.TextWindowType.WIDGET, (int) x, (int) y, out bx, out by);
			Gtk.TextIter at;
			if (!text_view.get_iter_at_location(out at, bx, by)) {
				return;
			}
			var add_tag = this.source_view.current_buffer.tag_table.lookup("diff-add");
			var remove_tag = this.source_view.current_buffer.tag_table.lookup("diff-remove");
			if (add_tag == null || remove_tag == null) {
				return;
			}
			Gtk.TextIter line_iter;
			this.source_view.current_buffer.get_iter_at_line(out line_iter, at.get_line());
			if (!line_iter.has_tag(add_tag) && !line_iter.has_tag(remove_tag)) {
				this.highlight_line = -1;
				this.apply_highlight();
				return;
			}
			this.highlight_line = at.get_line();
			this.apply_highlight();
		});
		text_view.add_controller(hunk_click);
		this.current_file_index = 0;
		this.window.title = this.pair_titles[0];
		var differ = new OLLMfiles.Diff.Differ(
			this.pair_baselines[0], this.pair_currents[0]);
		this.source_view.show_diff(differ);
		this.review_bar.update_diff_old(differ, 0);
		this.review_bar.review_response.connect((response, file_index, hunk_index) => {
			GLib.print("Review response [%s] file=%d hunk=%d:\n%s\n\n".printf(
				response.label, file_index, hunk_index, response.prompt));
		});
		var loop = new GLib.MainLoop();
		this.window.close_request.connect(() => {
			loop.quit();
			return false;
		});
#if ANDROID_SOURCE_DIFF
		if (activity_ready) {
			this.window.present();
		}
		if (!activity_ready) {
			this.activate.connect(() => {
				this.window.present();
			});
		}
#else
		this.window.present();
#endif
		GLib.Idle.add(() => {
			this.apply_highlight();
			return Source.REMOVE;
		});
		loop.run();
	}

	/**
	 * Copy the hunk-wash CSS ``color`` onto the diff line backgrounds.
	 *
	 * Inactive lines use ``.oc-diff-add`` and ``.oc-diff-remove``. The hunk at
	 * {@link highlight_line} uses the ``-active`` rules. A value below 0, other
	 * than -1, means the first changed hunk. -1 clears that wash and hides
	 * Accept and Reject.
	 */
	private void apply_highlight()
	{
		var add_tag = this.source_view.current_buffer.tag_table.lookup("diff-add");
		var remove_tag = this.source_view.current_buffer.tag_table.lookup("diff-remove");
		if (add_tag == null || remove_tag == null) {
			return;
		}
		add_tag.paragraph_background_rgba = this.add_swatch.get_color();
		remove_tag.paragraph_background_rgba = this.remove_swatch.get_color();
		var active_add = this.source_view.current_buffer.tag_table.lookup("diff-add-active");
		if (active_add == null) {
			active_add = new Gtk.TextTag("diff-add-active");
			this.source_view.current_buffer.tag_table.add(active_add);
		}
		var active_remove = this.source_view.current_buffer.tag_table.lookup("diff-remove-active");
		if (active_remove == null) {
			active_remove = new Gtk.TextTag("diff-remove-active");
			this.source_view.current_buffer.tag_table.add(active_remove);
		}
		active_add.paragraph_background_rgba = this.add_active_swatch.get_color();
		active_remove.paragraph_background_rgba = this.remove_active_swatch.get_color();
		Gtk.TextIter bounds_start, bounds_end;
		this.source_view.current_buffer.get_bounds(out bounds_start, out bounds_end);
		this.source_view.current_buffer.remove_tag(active_add, bounds_start, bounds_end);
		this.source_view.current_buffer.remove_tag(active_remove, bounds_start, bounds_end);
		if (this.highlight_line == -1) {
			this.review_bar.review_overlay.visible = false;
			return;
		}
		var anchor = this.highlight_line;
		if (anchor < 0) {
			anchor = -1;
			for (var i = 0; i < this.source_view.current_buffer.get_line_count(); i++) {
				Gtk.TextIter line_iter;
				this.source_view.current_buffer.get_iter_at_line(out line_iter, i);
				if (!line_iter.has_tag(add_tag) && !line_iter.has_tag(remove_tag)) {
					continue;
				}
				anchor = i;
				break;
			}
		}
		if (anchor < 0) {
			this.review_bar.review_overlay.visible = false;
			return;
		}
		var hunk_start = anchor;
		while (hunk_start > 0) {
			Gtk.TextIter prev;
			this.source_view.current_buffer.get_iter_at_line(out prev, hunk_start - 1);
			if (!prev.has_tag(add_tag) && !prev.has_tag(remove_tag)) {
				break;
			}
			hunk_start--;
		}
		var hunk_end = anchor;
		while (hunk_end + 1 < this.source_view.current_buffer.get_line_count()) {
			Gtk.TextIter next;
			this.source_view.current_buffer.get_iter_at_line(out next, hunk_end + 1);
			if (!next.has_tag(add_tag) && !next.has_tag(remove_tag)) {
				break;
			}
			hunk_end++;
		}
		for (var i = hunk_start; i <= hunk_end; i++) {
			Gtk.TextIter from, to;
			this.source_view.current_buffer.get_iter_at_line(out from, i);
			to = from;
			if (!to.ends_line()) {
				to.forward_to_line_end();
			}
			if (from.has_tag(add_tag)) {
				this.source_view.current_buffer.apply_tag(active_add, from, to);
			}
			if (from.has_tag(remove_tag)) {
				this.source_view.current_buffer.apply_tag(active_remove, from, to);
			}
		}
		this.review_bar.review_overlay.visible = true;
	}

	public static int main(string[] args)
	{
		return new TestSourceDiff().run(args);
	}
}
