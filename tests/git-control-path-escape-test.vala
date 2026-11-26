/*
 * Fails while project writes can change git control files.
 *
 * Runs OLLMbwrap.Bubble against a real repository, then
 * OLLMfilesd.File.rpc_write for the same paths. A later fix should
 * leave .git unchanged and still copy an ordinary project file.
 */

class GitControlPath : Object
{
	public int failures = 0;
	public int controls = 0;

	public async void run()
	{
		var root = GLib.DirUtils.make_tmp("ollm-git-control-XXXXXX");
		var marker_dir = GLib.DirUtils.make_tmp("ollm-git-marker-XXXXXX");
		var db_path = GLib.Path.build_filename(root, "files.sqlite");
		var db = new SQ.Database(db_path, false);
		var manager = new OLLMfilesd.ProjectManager(db);
		var project = new OLLMfilesd.Folder(manager);
		project.path = root;
		project.is_project = true;
		project.project_files.folder_map.set(project.path, project);
		manager.projects.append(project);
		OLLMfilesd.Folder.background_recurse = false;
		var request = new OLLMrpc.Request();
		request.connection = new OLLMrpc.Transport.Connection(null);
		yield manager.activate_project(request, project, true);

		Posix.system("git init -q '" + root + "'");
		Posix.system(
			"git -C '" + root + "' config user.email test@example.com"
		);
		Posix.system(
			"git -C '" + root + "' config user.name test"
		);
		GLib.FileUtils.set_contents(
			GLib.Path.build_filename(root, "README"),
			"hello\n"
		);
		Posix.system(
			"git -C '" + root + "' add README && git -C '" + root
			+ "' commit -q -m init"
		);
		var config_before = "";
		GLib.FileUtils.get_contents(
			GLib.Path.build_filename(root, ".git", "config"),
			out config_before
		);

		var marker = GLib.Path.build_filename(marker_dir, "hook");
		yield this.sandbox(
			manager,
			project,
			"mkdir -p .git/hooks && printf '%s\\n' '#!/bin/sh' 'echo ran >> "
			+ marker
			+ "' > .git/hooks/pre-commit && chmod 755 .git/hooks/pre-commit"
		);
		var hook = GLib.Path.build_filename(root, ".git", "hooks", "pre-commit");
		if (GLib.FileUtils.test(hook, GLib.FileTest.EXISTS)) {
			this.fail("pre-commit hook was copied onto the real repository");
		}
		Posix.system(
			"git -C '" + root + "' commit -q --allow-empty -m next"
		);
		if (GLib.FileUtils.test(marker, GLib.FileTest.EXISTS)) {
			this.fail("git commit ran a hook written by the sandbox");
		}

		var fs_marker = GLib.Path.build_filename(marker_dir, "fsmonitor");
		var fs_script = GLib.Path.build_filename(marker_dir, "fs.sh");
		GLib.FileUtils.set_contents(
			fs_script,
			"#!/bin/sh\necho ran >> '" + fs_marker + "'\n"
		);
		Posix.chmod(fs_script, 0755);
		yield this.sandbox(
			manager,
			project,
			"git config core.fsmonitor '" + fs_script + "'"
		);
		var config_after = "";
		GLib.FileUtils.get_contents(
			GLib.Path.build_filename(root, ".git", "config"),
			out config_after
		);
		if (config_after != config_before) {
			this.fail("sandbox git config changed the real .git/config");
		}
		Posix.system("git -C '" + root + "' status --porcelain");
		if (GLib.FileUtils.test(fs_marker, GLib.FileTest.EXISTS)) {
			this.fail("git status ran core.fsmonitor from the sandbox");
		}

		var link = GLib.Path.build_filename(root, ".git", "hooks", "post-commit");
		yield this.sandbox(
			manager,
			project,
			"ln -s /bin/true .git/hooks/post-commit"
		);
		if (GLib.FileUtils.test(link, GLib.FileTest.IS_SYMLINK)) {
			this.fail("sandbox symlink was copied under .git/hooks");
		}

		var sample = GLib.Path.build_filename(
			root, ".git", "hooks", "pre-commit.sample"
		);
		var sample_before = "";
		GLib.FileUtils.get_contents(sample, out sample_before);
		yield this.sandbox(
			manager,
			project,
			"printf '%s\\n' '#!/bin/sh' 'echo changed' > .git/hooks/pre-commit.sample && chmod 755 .git/hooks/pre-commit.sample"
		);
		var sample_after = "";
		GLib.FileUtils.get_contents(sample, out sample_after);
		if (sample_after != sample_before) {
			this.fail("sandbox overwrote an existing .git/hooks file");
		}
		var indexed = new OLLMfilesd.File(manager);
		indexed.path = GLib.Path.build_filename(root, ".git", "config");
		indexed.base_type = "f";
		indexed.id = 50;
		manager.file_cache.set(indexed.path, indexed);

		yield this.sandbox(manager, project, "rm -f .git/config");
		if (!GLib.FileUtils.test(
			GLib.Path.build_filename(root, ".git", "config"),
			GLib.FileTest.EXISTS
		)) {
			this.fail("sandbox removed the real .git/config");
		}

		yield this.sandbox(
			manager,
			project,
			"printf '%s\\n' 'ordinary' > NOTES"
		);
		var notes = "";
		var notes_path = GLib.Path.build_filename(root, "NOTES");
		if (!GLib.FileUtils.test(notes_path, GLib.FileTest.EXISTS)) {
			this.control_fail("ordinary project file was not copied back");
		}
		if (GLib.FileUtils.test(notes_path, GLib.FileTest.EXISTS)) {
			GLib.FileUtils.get_contents(notes_path, out notes);
			if (notes != "ordinary\n") {
				this.control_fail("ordinary project file has the wrong bytes");
			}
		}

		var planted = "core.fsmonitor = echo planted\n";
		var writer = new OLLMfilesd.File(manager);
		var write_request = new OLLMrpc.Request();
		write_request.connection = new OLLMrpc.Transport.Connection(null);
		write_request.args = OLLMrpc.args(
			"ssssu",
			GLib.Path.build_filename(root, ".git", "config"),
			planted,
			"f",
			"",
			(uint) 0644
		);
		writer.rpc_write(
			write_request,
			GLib.Path.build_filename(root, ".git", "config"),
			planted,
			"f",
			"",
			0644
		);
		GLib.Timeout.add(500, () => {
			this.run.callback();
			return false;
		});
		yield;
		var config_rpc = "";
		GLib.FileUtils.get_contents(
			GLib.Path.build_filename(root, ".git", "config"),
			out config_rpc
		);
		if (config_rpc != config_before && config_rpc.contains("planted")) {
			this.fail("File.rpc_write replaced .git/config");
		}

		var hook_body = "#!/bin/sh\necho planted\n";
		var hook_request = new OLLMrpc.Request();
		hook_request.connection = new OLLMrpc.Transport.Connection(null);
		hook_request.args = OLLMrpc.args(
			"ssssu",
			hook,
			hook_body,
			"f",
			"",
			(uint) 0755
		);
		writer.rpc_write(
			hook_request,
			hook,
			hook_body,
			"f",
			"",
			0755
		);
		GLib.Timeout.add(500, () => {
			this.run.callback();
			return false;
		});
		yield;
		if (GLib.FileUtils.test(hook, GLib.FileTest.EXISTS)) {
			this.fail("File.rpc_write created .git/hooks/pre-commit");
		}

		stdout.printf("failures %d\n", this.failures);
		stdout.printf("control_failures %d\n", this.controls);
	}

	public void fail(string message)
	{
		this.failures++;
		stdout.printf("FAIL %s\n", message);
	}

	public void control_fail(string message)
	{
		this.controls++;
		stdout.printf("CONTROL %s\n", message);
	}

	public async void sandbox(
		OLLMfilesd.ProjectManager manager,
		OLLMfilesd.Folder project,
		string command
	) throws GLib.Error
	{
		var bubble = new OLLMbwrap.Bubble(
			new OLLMfilesd.FileVerification(project, manager)
		);
		bubble.project_path = project.path;
		bubble.write_tokens = { "project" };
		bubble.write_roots.set(project.path, project.path);
		try {
			var output = yield bubble.exec(command, project.path);
			stdout.printf("SANDBOX %s\n", output);
		} catch (GLib.Error e) {
			this.control_fail(e.message);
		}
	}
}

int main()
{
	var loop = new GLib.MainLoop();
	var test = new GitControlPath();
	test.run.begin((obj, res) => {
		try {
			test.run.end(res);
		} catch (GLib.Error e) {
			stdout.printf("ERROR %s\n", e.message);
			test.failures++;
		}
		loop.quit();
	});
	loop.run();
	if (test.controls > 0) {
		return 2;
	}
	if (test.failures > 0) {
		return 1;
	}
	return 0;
}
