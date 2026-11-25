/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Path containment: write, read, and edit must not touch a file whose
 * real path is outside the open project, even when the tool path string
 * starts with the project directory. These tests fail while that check
 * is only a raw prefix (or is repeated on the same string at use time).
 */

/**
 * Chat that does not contact a model. Edit mode calls this only after
 * the file RPC, to continue the conversation.
 */
public class PathContainmentQuietChat : OLLMchat.Call.Chat
{
	public PathContainmentQuietChat(
		OLLMchat.Settings.Connection connection,
		string model
	) {
		base(connection, model);
	}

	public override async OLLMchat.Response.Chat send(
		Gee.ArrayList<OLLMchat.Message> messages,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		var response = new OLLMchat.Response.Chat(this.connection, this);
		response.done = true;
		response.message = new OLLMchat.Message("assistant", "");
		return response;
	}
}

/**
 * Denies every prompt. A skipped prompt therefore cannot be an approval.
 */
public class PathContainmentDeny : OLLMchat.ChatPermission.Provider
{
	public int asks = 0;

	public PathContainmentDeny()
	{
		base("");
	}

	protected override async OLLMchat.ChatPermission.PermissionResponse request_user(
		OLLMchat.Tool.RequestBase request
	) {
		this.asks++;
		return OLLMchat.ChatPermission.PermissionResponse.DENY_ONCE;
	}
}

/**
 * Non-agentic stand-in for {@link OLLMchat.Agent.Interface}. Tool
 * execution reads the permission provider and the chat from here.
 */
public class PathContainmentAgent : Object, OLLMchat.Agent.Interface
{
	private OLLMchat.Call.ChatBase chat_call;
	private PathContainmentDeny deny;
	private OLLMchat.Settings.Config2 stored_config;
	public Gee.ArrayList<string> notes {
		get; set; default = new Gee.ArrayList<string>();
	}

	public PathContainmentAgent(
		OLLMchat.Call.ChatBase chat_call,
		PathContainmentDeny deny,
		OLLMchat.Settings.Config2 stored_config
	) {
		this.chat_call = chat_call;
		this.deny = deny;
		this.stored_config = stored_config;
	}

	public OLLMchat.Call.ChatBase chat()
	{
		return this.chat_call;
	}

	public OLLMchat.ChatPermission.Provider get_permission_provider()
	{
		return this.deny;
	}

	public OLLMchat.Settings.Config2 config()
	{
		return this.stored_config;
	}

	public void add_message(OLLMchat.Message message)
	{
		this.notes.add(message.content);
	}
}

/**
 * Drives the file tools and the file daemon against a temporary project.
 */
public class PathContainmentTest
{
	private string root = "";
	private string project_path = "";
	private string outside_file = "";
	private string inside_file = "";
	private string data_dir = "";
	private OLLMfiles.ProjectManager manager;
	private PathContainmentAgent agent;
	private PathContainmentDeny deny;
	private string[] failures = {};

	public static int main(string[] args)
	{
		var test = new PathContainmentTest();
		test.run.begin((obj, res) => {
			var code = 1;
			try {
				code = test.run.end(res);
			} catch (GLib.Error e) {
				GLib.printerr("path containment harness: %s\n", e.message);
				code = 1;
			}
			if (code == 0) {
				GLib.print("path containment: all cases held\n");
			}
			GLib.Process.exit(code);
		});
		new GLib.MainLoop().run();
		return 0;
	}

	private async int run() throws GLib.Error
	{
		Gtk.init();
		this.root = GLib.DirUtils.make_tmp("path-containment-XXXXXX");
		this.project_path = GLib.Path.build_filename(this.root, "project");
		this.outside_file = GLib.Path.build_filename(this.root, "outside", "secret");
		this.inside_file = GLib.Path.build_filename(this.project_path, "note.txt");
		GLib.DirUtils.create_with_parents(
			GLib.Path.build_filename(this.root, "outside"), 0700);
		GLib.DirUtils.create_with_parents(this.project_path, 0700);
		this.plant("outside-body", "inside-body");

		GLib.Environment.set_variable("OLLMFILES_IS_TEST", "1", true);
		OLLMfiles.rpc_register();
		this.data_dir = GLib.DirUtils.make_tmp("path-containment-daemon-XXXXXX");
		this.manager = new OLLMfiles.ProjectManager();
		var rpc = new OLLMrpc.Client(this.data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
		this.manager.replace_rpc(rpc);
		var boot = new OLLMrpc.ClientBoot(
			this.data_dir, "ollmfilesd.pid", "ollmfilesd.sock", false, true);
		boot.startup_wait = 20;
		var connected = yield rpc.connect(new OLLMrpc.Request() {
			method = "RPC-Daemon.hello",
			args = OLLMrpc.args("is", 1, "path-containment")
		}, boot);
		if (!connected) {
			GLib.printerr("daemon did not connect: %s\n", rpc.connect_error);
			return 1;
		}

		this.manager.buffer_provider = new OLLMcoder.BufferProvider();
		var project = yield this.manager.rpc_create_project(this.project_path);
		this.manager.disable_initial_scan = true;
		yield this.manager.activate_project(project, false);
		if (this.manager.active_project == null ||
			this.manager.active_project.path != this.project_path) {
			GLib.printerr("project did not activate\n");
			return 1;
		}

		var connection = new OLLMchat.Settings.Connection();
		connection.url = "http://127.0.0.1:9/api";
		var chat = new PathContainmentQuietChat(connection, "path-containment");
		chat.stream = false;
		this.deny = new PathContainmentDeny();
		this.agent = new PathContainmentAgent(
			chat, this.deny, new OLLMchat.Settings.Config2());

		yield this.case_inside_write();
		this.plant("outside-body", "inside-body");
		yield this.case_tool_write(this.project_path + "/../outside/secret",
			"write absolute dotdot");
		this.plant("outside-body", "inside-body");
		yield this.case_tool_write("../outside/secret", "write relative dotdot");
		this.plant("outside-body", "inside-body");
		yield this.case_tool_read(this.project_path + "/../outside/secret",
			"read absolute dotdot");
		yield this.case_tool_read("../outside/secret", "read relative dotdot");
		this.plant("outside-body", "inside-body");
		yield this.case_symlink_write(false);
		this.plant("outside-body", "inside-body");
		yield this.case_symlink_write(true);
		this.plant("outside-body", "inside-body");
		yield this.case_edit(this.project_path + "/../outside/secret");
		this.plant("outside-body", "inside-body");
		yield this.case_daemon_read(this.project_path + "/../outside/secret");
		yield this.case_daemon_write(this.project_path + "/../outside/secret");
		this.plant("outside-body", "inside-body");
		yield this.case_create_outside();

		yield boot.kill();
		if (this.failures.length == 0) {
			return 0;
		}
		foreach (var failure in this.failures) {
			GLib.printerr("FAIL %s\n", failure);
		}
		return 1;
	}

	private void plant(string outside_body, string inside_body)
	{
		GLib.FileUtils.set_contents(this.outside_file, outside_body);
		GLib.FileUtils.set_contents(this.inside_file, inside_body);
	}

	private string disk(string path)
	{
		var body = "";
		try {
			GLib.FileUtils.get_contents(path, out body);
		} catch (GLib.Error e) {
			return "";
		}
		return body;
	}

	private async void case_inside_write() throws GLib.Error
	{
		this.deny.asks = 0;
		var result = yield this.write_request(this.inside_file, "inside-updated");
		if (this.disk(this.inside_file) != "inside-updated") {
			this.failures += "inside write did not update the project file: " + result;
		}
		if (this.deny.asks != 0) {
			this.failures += "inside write prompted";
		}
		if (this.disk(this.outside_file) != "outside-body") {
			this.failures += "inside write changed the outside file";
		}
	}

	private async void case_tool_write(string file_path, string label) throws GLib.Error
	{
		this.deny.asks = 0;
		var result = yield this.write_request(file_path, "replacement-body");
		if (this.disk(this.outside_file) != "outside-body") {
			this.failures += label + " wrote outside the project (" +
				result + ", prompts=" + this.deny.asks.to_string() + ")";
		}
	}

	private async void case_tool_read(string file_path, string label) throws GLib.Error
	{
		this.deny.asks = 0;
		var obj = new Json.Object();
		obj.set_string_member("file_path", file_path);
		obj.set_boolean_member("read_entire_file", true);
		var node = new Json.Node(Json.NodeType.OBJECT);
		node.set_object(obj);
		var request = Json.gobject_deserialize(
			typeof(OLLMtools.ReadFile.Request), node) as OLLMtools.ReadFile.Request;
		request.tool = new OLLMtools.ReadFile.Tool(this.manager);
		request.agent = this.agent;
		var result = yield request.execute();
		if (result.index_of("outside-body") >= 0) {
			this.failures += label + " returned the outside file (prompts=" +
				this.deny.asks.to_string() + ")";
		}
	}

	private async void case_symlink_write(bool retarget_after_check) throws GLib.Error
	{
		var link = GLib.Path.build_filename(this.project_path, "link");
		if (GLib.FileUtils.test(link, GLib.FileTest.IS_SYMLINK) ||
			GLib.FileUtils.test(link, GLib.FileTest.EXISTS)) {
			GLib.FileUtils.unlink(link);
		}
		Posix.symlink(retarget_after_check ? this.inside_file : this.outside_file, link);
		this.deny.asks = 0;
		if (retarget_after_check) {
			GLib.Timeout.add_full(GLib.Priority.HIGH, 0, () => {
				GLib.FileUtils.unlink(link);
				Posix.symlink(this.outside_file, link);
				return false;
			});
		}
		var result = yield this.write_request(link, "replacement-body");
		if (this.disk(this.outside_file) != "outside-body") {
			var label = retarget_after_check
				? "symlink retarget between check and write"
				: "symlink inside the project";
			this.failures += label + " wrote outside the project (" +
				result + ", prompts=" + this.deny.asks.to_string() + ")";
		}
		GLib.FileUtils.unlink(link);
	}

	private async void case_edit(string file_path) throws GLib.Error
	{
		this.deny.asks = 0;
		this.agent.notes.clear();
		var obj = new Json.Object();
		obj.set_string_member("file_path", file_path);
		obj.set_string_member("edit_mode", "complete_file");
		obj.set_boolean_member("overwrite", true);
		var node = new Json.Node(Json.NodeType.OBJECT);
		node.set_object(obj);
		var request = Json.gobject_deserialize(
			typeof(OLLMtools.EditMode.Request), node) as OLLMtools.EditMode.Request;
		request.tool = new OLLMtools.EditMode.Tool(this.manager);
		request.agent = this.agent;
		yield request.execute();
		var response = new OLLMchat.Response.Chat(
			this.agent.chat().connection, this.agent.chat());
		response.done = true;
		response.message = new OLLMchat.Message("assistant",
			"```text\nreplacement-body\n```\n");
		request.on_message_completed(response);
		var loop = new GLib.MainLoop();
		GLib.Timeout.add(2000, () => {
			loop.quit();
			return false;
		});
		loop.run();
		if (this.disk(this.outside_file) != "outside-body") {
			this.failures += "edit dotdot wrote outside the project (prompts=" +
				this.deny.asks.to_string() + ")";
		}
	}

	private async void case_daemon_write(string file_path) throws GLib.Error
	{
		var accepted = false;
		try {
			yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.rpc_write",
				args = OLLMrpc.args(
					"ssssu", file_path, "replacement-body", "f", "", (uint) 0)
			});
			accepted = true;
		} catch (GLib.Error e) {
			accepted = false;
		}
		if (accepted || this.disk(this.outside_file) != "outside-body") {
			this.failures += "daemon File.rpc_write " +
				(accepted ? "accepted" : "changed") + " a path outside the project";
		}
	}

	private async void case_daemon_read(string file_path) throws GLib.Error
	{
		var leaked = false;
		try {
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.read",
				args = OLLMrpc.args("s", file_path)
			});
			var body = response.msg;
			if (response.msg_encode == 1 && body != "") {
				body = (string) GLib.Base64.decode(body);
			}
			if (body.index_of("outside-body") >= 0) {
				leaked = true;
			}
		} catch (GLib.Error e) {
			leaked = false;
		}
		if (leaked) {
			this.failures += "daemon File.read returned a file outside the project";
		}
	}

	private async void case_create_outside() throws GLib.Error
	{
		var created = GLib.Path.build_filename(this.root, "brand-new-file");
		if (GLib.FileUtils.test(created, GLib.FileTest.EXISTS)) {
			GLib.FileUtils.unlink(created);
		}
		yield this.write_request(this.project_path + "/../brand-new-file",
			"replacement-body");
		if (GLib.FileUtils.test(created, GLib.FileTest.EXISTS)) {
			this.failures += "write created a file outside the project";
			GLib.FileUtils.unlink(created);
		}
	}

	private async string write_request(string file_path, string content) throws GLib.Error
	{
		var obj = new Json.Object();
		obj.set_string_member("file_path", file_path);
		obj.set_string_member("content", content);
		obj.set_boolean_member("complete_file", true);
		obj.set_boolean_member("overwrite", true);
		var node = new Json.Node(Json.NodeType.OBJECT);
		node.set_object(obj);
		var request = Json.gobject_deserialize(
			typeof(OLLMtools.WriteFile.Request), node) as OLLMtools.WriteFile.Request;
		request.tool = new OLLMtools.WriteFile.Tool(this.manager);
		request.agent = this.agent;
		return yield request.execute();
	}
}
