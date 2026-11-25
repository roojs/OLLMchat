/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Confirms web_fetch refuses loopback, link-local, and RFC1918 targets,
 * and does not follow a redirect onto those targets, unless the permission
 * provider allowed that exact host. Fails while the unrestricted fetch is
 * still present.
 */

public class SsrfApp : GLib.Object, OLLMchat.ApplicationInterface
{
	public OLLMchat.Settings.Config2 config { get; set; }
	public string data_dir { get; set; default = ""; }

	public OLLMchat.Settings.Config2 load_config()
	{
		return this.config;
	}
}

public class SsrfPerm : OLLMchat.ChatPermission.Provider
{
	public int asked = 0;
	public string allow_host = "";
	public string forbid_host = "";

	public SsrfPerm()
	{
		base("");
	}

	protected override async OLLMchat.ChatPermission.PermissionResponse request_user(
		OLLMchat.Tool.RequestBase request
	) {
		this.asked++;
		var shown = request.permission_target_path + "\n" +
			request.permission_question + "\n" + request.to_summary();
		if (this.allow_host != "" && shown.contains(this.allow_host) &&
				(this.forbid_host == "" || !shown.contains(this.forbid_host))) {
			return OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE;
		}
		return OLLMchat.ChatPermission.PermissionResponse.DENY_ONCE;
	}
}

public class SsrfTest
{
	public string fail = "";
	public int hits = 0;
	public int hop_hits = 0;
	public int query_hits = 0;
	public uint v4_port = 0;
	public uint v6_port = 0;
	public uint doc_port = 0;
	public uint rfc_port = 0;
	public uint lan_port = 0;
	public uint priv_port = 0;
	public uint link_port = 0;
	public uint loop2_port = 0;
	private Soup.Server server;
	private OLLMchat.History.Manager manager;
	private SsrfPerm perm;

	public async void run()
	{
		Posix.system("sudo -n ip addr add 203.0.113.10/32 dev lo >/dev/null 2>&1");
		Posix.system("sudo -n ip addr add 10.255.255.1/32 dev lo >/dev/null 2>&1");
		Posix.system("sudo -n ip addr add 192.168.255.1/32 dev lo >/dev/null 2>&1");
		Posix.system("sudo -n ip addr add 172.16.255.1/32 dev lo >/dev/null 2>&1");
		Posix.system("sudo -n ip addr add 169.254.169.254/32 dev lo >/dev/null 2>&1");
		Posix.system("grep -q webfetch-ssrf.test /etc/hosts || echo '127.0.0.1 webfetch-ssrf.test' | sudo -n tee -a /etc/hosts >/dev/null");

		this.server = new Soup.Server("server-header", null);
		this.server.add_handler(null, (srv, msg, path, query) => {
			this.hits++;
			if (msg.get_uri().get_path() == "/hop") {
				this.hop_hits++;
			}
			var query_text = msg.get_uri().get_query();
			if (query_text != null && query_text.contains("ssrfq=EXFIL-MARKER")) {
				this.query_hits++;
			}
			if (msg.get_uri().get_path() == "/bounce") {
				msg.set_status(302, "Found");
				msg.get_response_headers().append("Location",
					"http://127.0.0.1:" + this.v4_port.to_string() + "/hop");
				return;
			}
			msg.set_status(200, "OK");
			var body = "SSRF-LOOP-BODY";
			if (msg.get_uri().get_path() == "/hop") {
				body = "SSRF-HOP-BODY";
			}
			msg.set_response("text/plain", Soup.MemoryUse.COPY, body.data);
		});
		try {
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("127.0.0.1"), 0), 0);
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("::1"), 0), 0);
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("127.0.0.2"), 0), 0);
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("203.0.113.10"), 0), 0);
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("10.255.255.1"), 0), 0);
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("192.168.255.1"), 0), 0);
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("172.16.255.1"), 0), 0);
			this.server.listen(
				new GLib.InetSocketAddress(new GLib.InetAddress.from_string("169.254.169.254"), 0), 0);
		} catch (GLib.Error e) {
			this.fail += "listen failed: " + e.message + "\n";
			return;
		}
		foreach (var uri in this.server.get_uris()) {
			if (uri.get_host() == "127.0.0.1") {
				this.v4_port = uri.get_port();
			}
			if (uri.get_host() == "::1") {
				this.v6_port = uri.get_port();
			}
			if (uri.get_host() == "127.0.0.2") {
				this.loop2_port = uri.get_port();
			}
			if (uri.get_host() == "203.0.113.10") {
				this.doc_port = uri.get_port();
			}
			if (uri.get_host() == "10.255.255.1") {
				this.rfc_port = uri.get_port();
			}
			if (uri.get_host() == "192.168.255.1") {
				this.lan_port = uri.get_port();
			}
			if (uri.get_host() == "172.16.255.1") {
				this.priv_port = uri.get_port();
			}
			if (uri.get_host() == "169.254.169.254") {
				this.link_port = uri.get_port();
			}
		}
		if (this.v4_port == 0 || this.v6_port == 0 || this.doc_port == 0 ||
				this.rfc_port == 0 || this.lan_port == 0 || this.priv_port == 0 ||
				this.link_port == 0 || this.loop2_port == 0) {
			this.fail += "missing listen port\n";
			return;
		}

		var config = new OLLMchat.Settings.Config2();
		config.connections.set("local", new OLLMchat.Settings.Connection() {
			name = "local",
			url = "http://127.0.0.1:9",
			is_default = true
		});
		config.usage.set("default_model", new OLLMchat.Settings.ModelUsage() {
			connection = "local",
			model = "ssrf-test"
		});
		var app = new SsrfApp() {
			config = config,
			data_dir = "/tmp/web-fetch-ssrf-test"
		};
		try {
			app.ensure_data_dir();
		} catch (GLib.Error e) {
			this.fail += "data dir: " + e.message + "\n";
			return;
		}
		this.manager = new OLLMchat.History.Manager(app);
		this.perm = new SsrfPerm();
		this.manager.permission_provider = this.perm;
		new OLLMtools.Registry().fill_tools(this.manager, null);
		if (!this.manager.tools.has_key("web_fetch")) {
			this.fail += "web_fetch is not in the default tool list\n";
			return;
		}
		((OLLMtools.WebFetch.Tool) this.manager.tools.get("web_fetch")).soup.timeout = 3;
		var model = new OLLMchat.Response.Model();
		model.capabilities.add("tools");
		this.manager.session.activate_model(new OLLMchat.Settings.ModelUsage() {
			connection = "local",
			model = "ssrf-test",
			model_obj = model
		});
		this.manager.session.ensure_agent_handler();
		if (!this.manager.session.agent.chat().tools.has_key("web_fetch")) {
			this.fail += "web_fetch was not offered to the agent\n";
			return;
		}

		var v4 = this.v4_port.to_string();
		string[] blocked = {
			"http://127.0.0.1:" + v4 + "/body?ssrfq=EXFIL-MARKER",
			"http://localhost:" + v4 + "/body",
			"http://webfetch-ssrf.test:" + v4 + "/body",
			"http://[::1]:" + this.v6_port.to_string() + "/body",
			"http://127.0.0.2:" + this.loop2_port.to_string() + "/body",
			"http://10.255.255.1:" + this.rfc_port.to_string() + "/body",
			"http://192.168.255.1:" + this.lan_port.to_string() + "/body",
			"http://172.16.255.1:" + this.priv_port.to_string() + "/body",
			"http://169.254.169.254:" + this.link_port.to_string() + "/body",
			"http://203.0.113.10:" + this.doc_port.to_string() + "/body?ssrfq=EXFIL-MARKER"
		};
		foreach (var url in blocked) {
			this.perm.allow_host = "";
			this.perm.forbid_host = "";
			var seen_hits = this.hits;
			var seen_query = this.query_hits;
			var reply = "ERROR: no tool reply";
			var parser = new Json.Parser();
			try {
				parser.load_from_data(
					"{\"id\":\"call-ssrf\",\"function\":{\"name\":\"web_fetch\",\"arguments\":{\"url\":\"" +
					url + "\",\"format\":\"raw\"}}}");
			} catch (GLib.Error e) {
				reply = "ERROR: bad fixture " + e.message;
			}
			if (!reply.contains("bad fixture")) {
				var tool_call = Json.gobject_deserialize(
					typeof(OLLMchat.Response.ToolCall),
					parser.get_root()) as OLLMchat.Response.ToolCall;
				var calls = new Gee.ArrayList<OLLMchat.Response.ToolCall>();
				calls.add(tool_call);
				var replies = yield this.manager.session.agent.execute_tools(calls);
				if (replies.size > 0) {
					reply = replies.get(0).content;
				}
			}
			if (this.hits != seen_hits || this.query_hits != seen_query ||
					reply.contains("SSRF-LOOP-BODY") || reply.contains("SSRF-HOP-BODY")) {
				this.fail += "fetched without permission: " + url +
					" hits " + seen_hits.to_string() + "->" + this.hits.to_string() +
					" query " + seen_query.to_string() + "->" + this.query_hits.to_string() +
					" reply " + reply + "\n";
			}
		}

		this.perm.allow_host = "203.0.113.10";
		this.perm.forbid_host = "127.0.0.1";
		var seen_hop = this.hop_hits;
		var bounce = "http://203.0.113.10:" + this.doc_port.to_string() + "/bounce";
		var bounce_reply = "ERROR: no tool reply";
		var bounce_parser = new Json.Parser();
		try {
			bounce_parser.load_from_data(
				"{\"id\":\"call-ssrf\",\"function\":{\"name\":\"web_fetch\",\"arguments\":{\"url\":\"" +
				bounce + "\",\"format\":\"raw\"}}}");
		} catch (GLib.Error e) {
			bounce_reply = "ERROR: bad fixture " + e.message;
		}
		if (!bounce_reply.contains("bad fixture")) {
			var bounce_call = Json.gobject_deserialize(
				typeof(OLLMchat.Response.ToolCall),
				bounce_parser.get_root()) as OLLMchat.Response.ToolCall;
			var bounce_calls = new Gee.ArrayList<OLLMchat.Response.ToolCall>();
			bounce_calls.add(bounce_call);
			var bounce_replies = yield this.manager.session.agent.execute_tools(bounce_calls);
			if (bounce_replies.size > 0) {
				bounce_reply = bounce_replies.get(0).content;
			}
		}
		if (this.hop_hits != seen_hop || bounce_reply.contains("SSRF-HOP-BODY")) {
			this.fail += "redirect from " + bounce + " reached loopback hops " +
				seen_hop.to_string() + "->" + this.hop_hits.to_string() +
				" reply " + bounce_reply + "\n";
		}

		((OLLMtools.WebFetch.Tool) this.manager.tools.get("web_fetch")).is_wrapped = true;
		this.perm.allow_host = "";
		this.perm.forbid_host = "";
		var seen_wrap = this.hits;
		var wrap_url = "http://127.0.0.1:" + v4 + "/body";
		var wrap_reply = "ERROR: no tool reply";
		var wrap_parser = new Json.Parser();
		try {
			wrap_parser.load_from_data(
				"{\"id\":\"call-ssrf\",\"function\":{\"name\":\"web_fetch\",\"arguments\":{\"url\":\"" +
				wrap_url + "\",\"format\":\"raw\"}}}");
		} catch (GLib.Error e) {
			wrap_reply = "ERROR: bad fixture " + e.message;
		}
		if (!wrap_reply.contains("bad fixture")) {
			var wrap_call = Json.gobject_deserialize(
				typeof(OLLMchat.Response.ToolCall),
				wrap_parser.get_root()) as OLLMchat.Response.ToolCall;
			var wrap_calls = new Gee.ArrayList<OLLMchat.Response.ToolCall>();
			wrap_calls.add(wrap_call);
			var wrap_replies = yield this.manager.session.agent.execute_tools(wrap_calls);
			if (wrap_replies.size > 0) {
				wrap_reply = wrap_replies.get(0).content;
			}
		}
		if (this.hits != seen_wrap || wrap_reply.contains("SSRF-LOOP-BODY")) {
			this.fail += "wrapped web_fetch fetched " + wrap_url + " reply " + wrap_reply + "\n";
		}
	}
}

int main()
{
	var test = new SsrfTest();
	var loop = new GLib.MainLoop();
	test.run.begin((obj, res) => {
		test.run.end(res);
		loop.quit();
	});
	loop.run();
	if (test.fail != "") {
		stdout.printf("%s", test.fail);
		return 1;
	}
	stdout.printf("web_fetch ssrf checks passed\n");
	return 0;
}
