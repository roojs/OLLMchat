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

/**
 * Browser tool scheme gate.
 *
 * Fetch and download must reject every URL whose scheme is not http or
 * https, before WebKit reads it. An http(s) page must not be able to
 * navigate the same view onto a file URL and have that text returned.
 * The permission provider below allows every prompt, so a prompt alone
 * does not satisfy these checks.
 */
public class SchemePerm : OLLMchat.ChatPermission.Provider
{
	public int asks = 0;

	public SchemePerm()
	{
		base("");
	}

	/**
	 * Allow the operation. The scheme gate must still refuse first.
	 *
	 * @param request tool request that asked
	 * @return allow once
	 */
	protected override async OLLMchat.ChatPermission.PermissionResponse request_user(
		OLLMchat.Tool.RequestBase request
	) {
		this.asks++;
		return OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE;
	}
}

/**
 * Agent surface the browser tool calls while a case runs.
 */
public class SchemeAgent : Object, OLLMchat.Agent.Interface
{
	public SchemePerm perms { get; set; default = new SchemePerm(); }
	public OLLMchat.Settings.Config2 cfg {
		get; set; default = new OLLMchat.Settings.Config2();
	}
	public SchemeChat harness_chat { get; set; default = new SchemeChat(); }

	/**
	 * @return chat object required by the agent interface
	 */
	public OLLMchat.Call.ChatBase chat()
	{
		return this.harness_chat;
	}

	/**
	 * @return provider that allows every prompt
	 */
	public OLLMchat.ChatPermission.Provider get_permission_provider()
	{
		return this.perms;
	}

	/**
	 * @return empty configuration
	 */
	public OLLMchat.Settings.Config2 config()
	{
		return this.cfg;
	}

	/**
	 * @param message transcript line from the tool
	 */
	public void add_message(OLLMchat.Message message)
	{
	}
}

/**
 * Chat call stub. The browser cases never send a model request.
 */
public class SchemeChat : OLLMchat.Call.ChatBase
{
	public override string model { get; set; default = "scheme-probe"; }
	public override OLLMchat.Call.Options options {
		get; set; default = new OLLMchat.Call.Options();
	}

	public SchemeChat()
	{
		base(null);
	}

	/**
	 * @param messages unused
	 * @param cancellable unused
	 * @return nothing; this stub does not send
	 * @throws GLib.Error always
	 */
	public override async OLLMchat.Response.Chat send(
		Gee.ArrayList<OLLMchat.Message> messages,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		throw new GLib.IOError.FAILED("scheme probe does not send chat");
	}
}

/**
 * Drives OLLMwebkit.Tool the way a model tool call does.
 */
public class BrowserSchemeProbe : OLLMwebkit.Tool
{
	public SchemeAgent harness { get; set; default = new SchemeAgent(); }
	public string marker = "";
	public string http_marker = "";
	public string file_uri = "";
	public string body_path = "";
	public string download_dir = "";
	public int failures = 0;
	public string log = "";
	public Soup.Server server { get; set; default = new Soup.Server(null); }
	public uint port = 0;
	public bool call_done = false;
	public string call_result = "";

	/**
	 * Load one browser tool call and return its tool result.
	 *
	 * Arguments travel as a JSON string, the same shape
	 * CallFunction accepts from a model reply.
	 *
	 * @param action browser action
	 * @param url url argument
	 * @return tool result, including the ERROR prefix on failure
	 */
	public async string call_tool(string action, string url) throws GLib.Error
	{
		var args = new Json.Object();
		args.set_string_member("action", action);
		args.set_string_member("url", url);
		var args_node = new Json.Node(Json.NodeType.OBJECT);
		args_node.set_object(args);
		var gen = new Json.Generator();
		gen.set_root(args_node);
		var call = new Json.Object();
		call.set_string_member("id", "call-scheme");
		var function_obj = new Json.Object();
		function_obj.set_string_member("name", "browser");
		function_obj.set_string_member("arguments", gen.to_data(null));
		call.set_object_member("function", function_obj);
		var call_node = new Json.Node(Json.NodeType.OBJECT);
		call_node.set_object(call);
		var tool_call = Json.gobject_deserialize(
			typeof(OLLMchat.Response.ToolCall), call_node)
			as OLLMchat.Response.ToolCall;
		if (tool_call == null) {
			throw new GLib.IOError.FAILED("tool call did not deserialize");
		}
		var parameters_node = new Json.Node(Json.NodeType.OBJECT);
		parameters_node.set_object(tool_call.function.arguments);
		var request = this.deserialize(parameters_node);
		if (request == null) {
			throw new GLib.IOError.FAILED("browser request did not deserialize");
		}
		request.tool = this;
		request.agent = this.harness;
		this.last_request = request;
		return yield request.execute();
	}

	/**
	 * Scheme of the view URI, or empty when it is not a URI.
	 *
	 * @param uri web view URI
	 * @return lowercase scheme
	 */
	public string uri_scheme(string uri)
	{
		if (uri.strip() == "") {
			return "";
		}
		try {
			var parsed = GLib.Uri.parse(uri, GLib.UriFlags.NONE);
			if (parsed.get_scheme() == null) {
				return "";
			}
			return parsed.get_scheme().down();
		} catch (GLib.Error e) {
			return "";
		}
	}

	/**
	 * Visible text in the live view, or empty when script fails.
	 *
	 * @return document body text
	 */
	public async string page_text()
	{
		try {
			var js = yield this.stack.primary.web_view.evaluate_javascript(
				"document.body ? document.body.innerText : ''",
				-1,
				null,
				"scheme-probe");
			return js.to_string();
		} catch (GLib.Error e) {
			return "";
		}
	}

	/**
	 * Record a failed case.
	 *
	 * @param name case name
	 * @param detail what was observed
	 */
	public void fail(string name, string detail)
	{
		this.failures++;
		this.log += name + ": " + detail + "\n";
		stdout.printf("FAIL %s: %s\n", name, detail);
		stdout.flush();
	}

	/**
	 * True when a non-http(s) load did not expose the local marker.
	 *
	 * @param name case name
	 * @param result tool result
	 * @param page live document text
	 */
	public void expect_blocked(string name, string result, string page)
	{
		var scheme = this.uri_scheme(this.stack.primary.current_uri);
		var preview = result.length > 240 ? result.substring(0, 240) : result;
		if (!result.has_prefix("ERROR:")) {
			this.fail(name, "tool returned content: " + preview);
			return;
		}
		if (result.contains(this.marker) || page.contains(this.marker)) {
			this.fail(name, "marker reached the tool or the view: " + preview);
			return;
		}
		if (scheme != "" && scheme != "http" && scheme != "https") {
			this.fail(name, "view scheme is " + scheme + " after " + preview);
			return;
		}
		stdout.printf("PASS %s (asks=%d scheme=%s)\n",
			name, this.harness.perms.asks, scheme);
		stdout.flush();
	}

	/**
	 * An http(s) fetch must not end on a file or data document.
	 *
	 * The result may be an error or the http page. It must not
	 * include the local file marker.
	 *
	 * @param name case name
	 * @param result tool result
	 * @param page live document text
	 */
	public void expect_no_local(string name, string result, string page)
	{
		var scheme = this.uri_scheme(this.stack.primary.current_uri);
		var preview = result.length > 240 ? result.substring(0, 240) : result;
		if (result.contains(this.marker) || page.contains(this.marker)) {
			this.fail(name, "marker reached the tool or the view: " + preview);
			return;
		}
		if (scheme == "file" || scheme == "data") {
			this.fail(name, "view scheme is " + scheme + " after " + preview);
			return;
		}
		stdout.printf("PASS %s (scheme=%s)\n", name, scheme);
		stdout.flush();
	}

	/**
	 * Run every scheme case. Returns the process status.
	 *
	 * @param app application that owns the window
	 * @return 0 when every case passed
	 */
	public async int run(Gtk.Application app) throws GLib.Error
	{
		this.marker = "scheme-probe-local-marker";
		this.http_marker = "scheme-probe-http-marker";
		var dir = GLib.DirUtils.make_tmp("ollm-browser-scheme-XXXXXX");
		this.body_path = GLib.Path.build_filename(dir, "body.html");
		var html = "<!DOCTYPE html><html><body><p>" + this.marker + "</p></body></html>";
		GLib.FileUtils.set_contents(this.body_path, html);
		this.file_uri = GLib.Filename.to_uri(this.body_path);
		this.download_dir = GLib.Path.build_filename(
			GLib.Environment.get_home_dir(), "Downloads");
		GLib.DirUtils.create_with_parents(this.download_dir, 0700);

		this.server.add_handler("/page", (srv, msg, path, query) => {
			msg.set_status(200, null);
			var body = "<!DOCTYPE html><html><body><p>" + this.http_marker + "</p></body></html>";
			msg.set_response("text/html", Soup.MemoryUse.COPY, body.data);
		});
		this.server.add_handler("/to-file", (srv, msg, path, query) => {
			msg.set_status(302, null);
			msg.get_response_headers().replace("Location", this.file_uri);
		});
		this.server.add_handler("/js-file", (srv, msg, path, query) => {
			msg.set_status(200, null);
			var body = "<!DOCTYPE html><html><body><p>hop</p><script>location.replace(\""
				+ this.file_uri + "\");</script></body></html>";
			msg.set_response("text/html", Soup.MemoryUse.COPY, body.data);
		});
		this.server.add_handler("/frame-file", (srv, msg, path, query) => {
			msg.set_status(200, null);
			var body = "<!DOCTYPE html><html><body><iframe src=\""
				+ this.file_uri + "\"></iframe></body></html>";
			msg.set_response("text/html", Soup.MemoryUse.COPY, body.data);
		});
		this.server.listen_local(0, Soup.ServerListenOptions.IPV4_ONLY);
		foreach (var listen_uri in this.server.get_uris()) {
			this.port = listen_uri.get_port();
		}

		var window = new Gtk.ApplicationWindow(app);
		window.set_default_size(900, 700);
		window.set_child(this.stack);
		window.present();
		GLib.Timeout.add(300, () => {
			run.callback();
			return GLib.Source.REMOVE;
		});
		yield;

		var base_url = "http://127.0.0.1:" + this.port.to_string();
		var http_result = yield this.call_tool("fetch", base_url + "/page");
		var http_page = yield this.page_text();
		if (!http_result.contains(this.http_marker) && !http_page.contains(this.http_marker)) {
			var preview = http_result.length > 400 ? http_result.substring(0, 400) : http_result;
			this.fail("http-control", "local http page was not returned: " + preview);
		}
		if (this.failures == 0) {
			stdout.printf("PASS http-control\n");
			stdout.flush();
		}

		string[] blocked = {
			this.file_uri,
			"FILE" + this.file_uri.substring(4),
			"file://localhost" + this.file_uri.substring(7),
			"file:" + this.body_path,
			" " + this.file_uri + " ",
		};
		string[] blocked_names = {
			"fetch-file",
			"fetch-FILE",
			"fetch-file-localhost",
			"fetch-file-one-slash",
			"fetch-file-padded",
		};
		var asks_before_file = this.harness.perms.asks;
		for (var i = 0; i < blocked.length; i++) {
			var result = yield this.call_tool("fetch", blocked[i]);
			var page = yield this.page_text();
			this.expect_blocked(blocked_names[i], result, page);
		}
		stdout.printf("fetch file asks=%d\n", this.harness.perms.asks - asks_before_file);
		stdout.flush();

		var data_url = "data:text/html;charset=utf-8,"
			+ GLib.Uri.escape_string("<p>" + this.marker + "</p>");
		var data_result = yield this.call_tool("fetch", data_url);
		var data_page = yield this.page_text();
		this.expect_blocked("fetch-data", data_result, data_page);

		var about_result = yield this.call_tool("fetch", "about:blank");
		var about_page = yield this.page_text();
		this.expect_blocked("fetch-about", about_result, about_page);

		var bounce_result = yield this.call_tool("fetch", base_url + "/to-file");
		var bounce_page = yield this.page_text();
		this.expect_no_local("fetch-http-redirect-file", bounce_result, bounce_page);

		var js_result = yield this.call_tool("fetch", base_url + "/js-file");
		var js_page = yield this.page_text();
		this.expect_no_local("fetch-http-js-file", js_result, js_page);

		var frame_result = yield this.call_tool("fetch", base_url + "/frame-file");
		var frame_page = yield this.page_text();
		this.expect_no_local("fetch-http-frame-file", frame_result, frame_page);

		string[] dl_names = { "download-file", "download-http-redirect-file" };
		string[] dl_urls = { this.file_uri, base_url + "/to-file" };
		for (var d = 0; d < dl_names.length; d++) {
			this.call_done = false;
			this.call_result = "";
			this.call_tool.begin("download", dl_urls[d], (obj, res) => {
				try {
					this.call_result = this.call_tool.end(res);
				} catch (GLib.Error e) {
					this.call_result = "ERROR: " + e.message;
				}
				this.call_done = true;
			});
			var ticks = 0;
			while (!this.call_done && ticks < 80 && !this.download_has_marker()) {
				GLib.Timeout.add(100, () => {
					run.callback();
					return GLib.Source.REMOVE;
				});
				yield;
				ticks++;
			}
			if (this.download_has_marker()) {
				this.fail(dl_names[d], "download wrote the local marker");
				continue;
			}
			if (!this.call_done && dl_names[d] == "download-file") {
				this.fail(dl_names[d], "download did not finish");
				continue;
			}
			if (!this.call_done) {
				stdout.printf("PASS %s (no local file written)\n", dl_names[d]);
				stdout.flush();
				continue;
			}
			var dl_page = yield this.page_text();
			this.expect_blocked(dl_names[d], this.call_result, dl_page);
		}

		var again = yield this.call_tool("fetch", base_url + "/page");
		var again_page = yield this.page_text();
		if (again.contains(this.marker) || again_page.contains(this.marker)) {
			this.fail("http-still-works", "local marker returned for an http page");
		}
		if (!again.contains(this.http_marker) && !again_page.contains(this.http_marker)) {
			var again_preview = again.length > 240 ? again.substring(0, 240) : again;
			this.fail("http-still-works", again_preview);
		}
		if (!again.contains(this.marker) && !again_page.contains(this.marker) &&
				(again.contains(this.http_marker) || again_page.contains(this.http_marker))) {
			stdout.printf("PASS http-still-works\n");
			stdout.flush();
		}

		stdout.printf("permission asks=%d\n", this.harness.perms.asks);
		stdout.flush();
		if (this.failures > 0) {
			stdout.printf("%d failure(s)\n%s", this.failures, this.log);
			stdout.flush();
			return 1;
		}
		stdout.printf("all scheme cases passed\n");
		stdout.flush();
		return 0;
	}

	/**
	 * True when a download wrote the local marker outside the source file.
	 *
	 * @return true when the marker was copied
	 */
	public bool download_has_marker()
	{
		string[] dirs = { this.download_dir, GLib.Environment.get_home_dir() };
		foreach (var dir in dirs) {
			try {
				var listing = GLib.Dir.open(dir);
				var entry = listing.read_name();
				while (entry != null) {
					var path = GLib.Path.build_filename(dir, entry);
					if (path == this.body_path) {
						entry = listing.read_name();
						continue;
					}
					if (GLib.FileUtils.test(path, GLib.FileTest.IS_DIR)) {
						entry = listing.read_name();
						continue;
					}
					var contents = "";
					try {
						GLib.FileUtils.get_contents(path, out contents);
					} catch (GLib.FileError e) {
						entry = listing.read_name();
						continue;
					}
					if (contents.contains(this.marker)) {
						GLib.FileUtils.remove(path);
						return true;
					}
					entry = listing.read_name();
				}
			} catch (GLib.FileError e) {
			}
		}
		return false;
	}
}

/**
 * Process entry. Sets the accessibility bus before GTK starts.
 */
public class BrowserSchemeMain : Object
{
	public int exit_code = 1;

	/**
	 * @param args process arguments
	 * @return 0 when the scheme cases pass
	 */
	public static int main(string[] args)
	{
		var home = GLib.DirUtils.make_tmp("ollm-browser-home-XXXXXX");
		GLib.Environment.set_variable("HOME", home, true);
		GLib.Environment.set_variable("XDG_CACHE_HOME",
			GLib.Path.build_filename(home, "cache"), true);
		GLib.Environment.set_variable("XDG_CONFIG_HOME",
			GLib.Path.build_filename(home, "config"), true);
		var download_dir = GLib.Path.build_filename(home, "Downloads");
		GLib.DirUtils.create_with_parents(download_dir, 0700);
		var config_dir = GLib.Path.build_filename(home, ".config");
		GLib.DirUtils.create_with_parents(config_dir, 0700);
		GLib.FileUtils.set_contents(
			GLib.Path.build_filename(config_dir, "user-dirs.dirs"),
			"XDG_DOWNLOAD_DIR=\"" + download_dir + "\"\n");
		GLib.Environment.set_variable("GTK_A11Y", "atspi", false);
		var holder = new BrowserSchemeMain();
		var app = new Gtk.Application(
			"com.roojs.ollmchat.browser-scheme",
			GLib.ApplicationFlags.NON_UNIQUE);
		app.activate.connect(() => {
			var probe = new BrowserSchemeProbe();
			probe.run.begin(app, (obj, res) => {
				try {
					holder.exit_code = probe.run.end(res);
				} catch (GLib.Error e) {
					stdout.printf("probe threw: %s\n", e.message);
					stdout.flush();
					holder.exit_code = 1;
				}
				app.quit();
			});
		});
		app.run(args);
		return holder.exit_code;
	}
}
