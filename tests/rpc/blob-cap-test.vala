/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * Oversized peer blob lengths must be rejected before allocation.
 * These cases lock the cap at 16 MiB: 16 MiB + 1 (wire 0x01000001)
 * and the top of the uint32 range must throw StreamError with no
 * multi-megabyte map. Socket Connection.on_input_ready and the HTTP
 * octet-stream parser both call Stream.parse before allow_request /
 * allow_rpc, so those entries are covered too.
 *
 * Left untested: compact strings and numeric arrays. Their counts
 * are at most 32767 on the wire, so they cannot ask for 16 MiB.
 * Typelib slab sizes in Gi are not taken from the peer.
 */

[CCode (cheader_filename = "blob-cap-rlimit.h")]
extern int blob_cap_getrlimit_as (out uint64 cur, out uint64 max);

[CCode (cheader_filename = "blob-cap-rlimit.h")]
extern int blob_cap_setrlimit_as (uint64 cur, uint64 max);

namespace OLLMrpcTests
{
	/**
	 * String property long enough that the encoder uses a uint32 blob.
	 */
	public class CapPair : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string name { get; set; default = ""; }
		public int count { get; set; default = 0; }
	}

	/**
	 * Records whether {@link OLLMrpc.Transport.Connection.allow_request}
	 * ran. Returns false so dispatch does not run.
	 */
	public class GateConnection : OLLMrpc.Transport.Connection
	{
		public bool allowed { get; set; default = false; }

		public GateConnection (GLib.SocketConnection stream)
		{
			Object (stream: stream);
		}

		public override bool allow_request (OLLMrpc.Request request)
		{
			this.allowed = request.method.length >= 0;
			return false;
		}
	}

	/**
	 * Records whether {@link OLLMrpc.Transport.HttpServer.allow_rpc}
	 * ran. Returns true so a parsed request is not mistaken for a
	 * parse failure.
	 */
	public class GateHttp : OLLMrpc.Transport.HttpServer
	{
		public bool allowed { get; set; default = false; }

		public GateHttp ()
		{
			Object ();
			this.port = 0;
		}

		protected override bool allow_rpc (
			OLLMrpc.Transport.HttpReply reply,
			OLLMrpc.Request request
		) {
			this.allowed = request.method.length >= 0 && reply.client_ip.length >= 0;
			return true;
		}
	}
}

int main (string[] args)
{
	if (args.length == 4 && args[1] == "--case") {
		var name = args[2];
		var reject = !name.has_suffix ("-ok");
		printerr ("case %s\n", name);
		stderr.flush ();
		uint8[] data = {};
		try {
			GLib.FileUtils.get_data (args[3], out data);
		} catch (GLib.Error e) {
			printerr ("read frame: %s\n", e.message);
			return 1;
		}
		try {
			OLLMrpc.Request.rpc_register ();
			OLLMrpc.Response.rpc_register ();
			OLLMrpc.Error.rpc_register ();
			OLLMrpc.Bin.register ("GLib.VariantType", typeof (GLib.VariantType));
			OLLMrpc.Bin.register ("CapPair", typeof (OLLMrpcTests.CapPair));
		} catch (GLib.Error e) {
			printerr ("register: %s\n", e.message);
			return 1;
		}

		var mem_in = new GLib.MemoryInputStream.from_bytes (new GLib.Bytes (data));
		var bin = new OLLMrpc.Bin.Stream (
			new GLib.DataInputStream (mem_in), null, true);
		var sv = new int[2];
		if (Posix.socketpair (Posix.AF_UNIX, Posix.SOCK_STREAM, 0, sv) != 0) {
			printerr ("socketpair failed\n");
			return 1;
		}
		GLib.Socket server_sock;
		GLib.Socket client_sock;
		try {
			server_sock = new GLib.Socket.from_fd (sv[0]);
			client_sock = new GLib.Socket.from_fd (sv[1]);
		} catch (GLib.Error e) {
			printerr ("from_fd: %s\n", e.message);
			return 1;
		}
		var server_stream = (GLib.SocketConnection) GLib.Object.new (
			typeof (GLib.SocketConnection), "socket", server_sock, null);
		var client_stream = (GLib.SocketConnection) GLib.Object.new (
			typeof (GLib.SocketConnection), "socket", client_sock, null);
		var gate = new OLLMrpcTests.GateConnection (server_stream);
		var http = new OLLMrpcTests.GateHttp ();
		var session = new Soup.Session ();
		session.timeout = 5;
		var msg = new Soup.Message ("POST", "http://127.0.0.1:9/rpc");
		msg.set_request_body_from_bytes (
			"application/octet-stream", new GLib.Bytes (data));
		if (name.has_prefix ("sock-")) {
			gate.start ();
			try {
				size_t written;
				client_stream.output_stream.write_all (data, out written);
				client_sock.shutdown (false, true);
			} catch (GLib.Error e) {
				printerr ("sock write: %s\n", e.message);
				return 1;
			}
		}
		if (name.has_prefix ("http-")) {
			if (!http.start ()) {
				printerr ("http start failed\n");
				return 1;
			}
			try {
				msg.set_uri (GLib.Uri.parse (
					"http://127.0.0.1:%u/rpc".printf (http.port),
					GLib.UriFlags.NONE));
			} catch (GLib.Error e) {
				printerr ("uri: %s\n", e.message);
				return 1;
			}
		}

		if (name.has_prefix ("http-")) {
			var warm_mem = new GLib.MemoryOutputStream.resizable ();
			var warm_out = new GLib.DataOutputStream (warm_mem);
			var warm_writer = new OLLMrpc.Bin.Stream (null, warm_out);
			try {
				warm_writer.write (new OLLMrpc.Request () {
					id = 1,
					method = "ClientCert.request_registration"
				});
				warm_out.close ();
			} catch (GLib.Error e) {
				printerr ("warmup encode: %s\n", e.message);
				return 1;
			}
			var warm = new Soup.Message ("POST", msg.uri.to_string ());
			warm.set_request_body_from_bytes (
				"application/octet-stream", warm_mem.steal_as_bytes ());
			var warm_loop = new GLib.MainLoop ();
			var warm_ok = false;
			session.send_and_read_async.begin (
				warm, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						session.send_and_read_async.end (res);
						warm_ok = warm.status_code != 0;
					} catch (GLib.Error e) {
						printerr ("warmup: %s\n", e.message);
					}
					warm_loop.quit ();
				});
			warm_loop.run ();
			if (!warm_ok || !http.allowed) {
				printerr ("warmup did not reach allow_rpc\n");
				return 1;
			}
			http.allowed = false;
		}

		var status_text = "";
		try {
			GLib.FileUtils.get_contents ("/proc/self/status", out status_text);
		} catch (GLib.Error e) {
			printerr ("status: %s\n", e.message);
			return 1;
		}
		var vm_size = (uint64) 0;
		foreach (var line in status_text.split ("\n")) {
			if (!line.has_prefix ("VmSize:")) {
				continue;
			}
			foreach (var piece in line.split (" ")) {
				var parsed = (uint64) 0;
				if (!uint64.try_parse (piece, out parsed)) {
					continue;
				}
				vm_size = parsed;
			}
		}
		if (vm_size == 0) {
			printerr ("VmSize missing\n");
			return 1;
		}
		/* Headroom is under 16 MiB, so a peer length of 16 MiB + 1
		 * cannot be reserved. Measured after the HTTP warmup so the
		 * first request's library maps are already in the total. */
		var saved_cur = (uint64) 0;
		var saved_max = (uint64) 0;
		if (blob_cap_getrlimit_as (out saved_cur, out saved_max) != 0) {
			printerr ("getrlimit failed\n");
			return 1;
		}
		var tight_cur = vm_size * 1024 + (uint64) (12 * 1024 * 1024);
		if (blob_cap_setrlimit_as (tight_cur, saved_max) != 0) {
			printerr ("setrlimit failed\n");
			return 1;
		}
		stderr.flush ();

		var bin_returned = false;
		var bin_stream_error = false;
		var bin_other = "";
		var http_status = (uint) 0;
		var http_sent = false;
		if (name.has_prefix ("bin-")) {
			try {
				var parsed = bin.parse ();
				bin_returned = true;
				if (name == "bin-ok") {
					var req = parsed as OLLMrpc.Request;
					if (req == null || req.args.size != 1) {
						printerr ("bin-ok shape\n");
						return 1;
					}
					var got = (GLib.Bytes) req.args.get (0).get_boxed ();
					var body = got.get_data ();
					if (got.get_size () != 4 || body[0] != 0xDE ||
						body[1] != 0xAD || body[2] != 0xBE || body[3] != 0xEF) {
						printerr ("bin-ok payload\n");
						return 1;
					}
				}
			} catch (OLLMrpc.Bin.StreamError e) {
				bin_stream_error = true;
			} catch (GLib.Error e) {
				bin_other = e.message;
			}
		}
		if (name.has_prefix ("sock-")) {
			var loop = new GLib.MainLoop ();
			var ticks = 0;
			GLib.Timeout.add (50, () => {
				ticks++;
				if (gate.allowed || !gate.running || ticks > 40) {
					loop.quit ();
					return false;
				}
				return true;
			});
			loop.run ();
		}
		if (name.has_prefix ("http-")) {
			var loop = new GLib.MainLoop ();
			session.send_and_read_async.begin (
				msg, GLib.Priority.DEFAULT, null,
				(obj, res) => {
					try {
						session.send_and_read_async.end (res);
						http_status = msg.status_code;
						http_sent = true;
					} catch (GLib.Error e) {
						bin_other = e.message;
					}
					loop.quit ();
				});
			loop.run ();
		}

		if (name.has_prefix ("bin-") && reject) {
			if (!bin_stream_error || bin_other != "") {
				printerr ("want StreamError, other=%s stream=%s\n",
					bin_other, bin_stream_error ? "yes" : "no");
				return 1;
			}
			return 0;
		}
		if (name == "bin-ok") {
			if (!bin_returned) {
				printerr ("small blob rejected %s\n", bin_other);
				return 1;
			}
			return 0;
		}
		if (name.has_prefix ("sock-") && reject) {
			if (gate.allowed || gate.running) {
				printerr ("socket allow=%s running=%s\n",
					gate.allowed ? "yes" : "no",
					gate.running ? "yes" : "no");
				return 1;
			}
			return 0;
		}
		if (name == "sock-ok") {
			if (!gate.allowed) {
				printerr ("allow_request did not run\n");
				return 1;
			}
			return 0;
		}
		if (name.has_prefix ("http-") && reject) {
			if (http.allowed || !http_sent || http_status != 400) {
				printerr ("http status %u allowed=%s sent=%s %s\n",
					http_status,
					http.allowed ? "yes" : "no",
					http_sent ? "yes" : "no",
					bin_other);
				return 1;
			}
			return 0;
		}
		if (name == "http-ok") {
			if (!http.allowed || !http_sent) {
				printerr ("allow_rpc did not run %s\n", bin_other);
				return 1;
			}
			return 0;
		}
		printerr ("unknown case %s\n", name);
		return 1;
	}

	var exe = "";
	try {
		exe = GLib.FileUtils.read_link ("/proc/self/exe");
	} catch (GLib.Error e) {
		printerr ("exe: %s\n", e.message);
		return 1;
	}
	var dir = "";
	try {
		dir = GLib.DirUtils.make_tmp ("blob-cap-XXXXXX");
	} catch (GLib.Error e) {
		printerr ("tmp: %s\n", e.message);
		return 1;
	}
	try {
		OLLMrpc.Request.rpc_register ();
		OLLMrpc.Bin.register ("GLib.VariantType", typeof (GLib.VariantType));
		OLLMrpc.Bin.register ("CapPair", typeof (OLLMrpcTests.CapPair));
	} catch (GLib.Error e) {
		printerr ("register: %s\n", e.message);
		return 1;
	}

	var marker = new uint8[] { 0xDE, 0xAD, 0xBE, 0xEF };
	var needle = new uint8[] {
		0x00, 0x00, 0x00, 0x04, 0xDE, 0xAD, 0xBE, 0xEF
	};
	var prop_needle = new uint8[] { 0x00, 0x00, 0x80, 0x00, 0x7a };
	var vtype_needle = new uint8[] {
		0x00, 0x00, 0x00, 0x04, '(', 'a', 'y', ')'
	};
	var cap_len = new GLib.Bytes (new uint8[] { 0x01, 0x00, 0x00, 0x01 });
	var max_len = new GLib.Bytes (new uint8[] { 0xFF, 0xFF, 0xFF, 0xFF });
	/* VariantType adds one byte. uint32 max would wrap that add. */
	var vtype_max = new GLib.Bytes (new uint8[] { 0x7F, 0xFF, 0xFF, 0xFF });
	var none = new GLib.Bytes (new uint8[0]);

	var encoded = new Gee.ArrayList<GLib.Bytes> ();
	var needles = new Gee.ArrayList<GLib.Bytes> ();
	var repls = new Gee.ArrayList<GLib.Bytes> ();
	var fnames = new Gee.ArrayList<string> ();

	var mem = new GLib.MemoryOutputStream.resizable ();
	var outs = new GLib.DataOutputStream (mem);
	var writer = new OLLMrpc.Bin.Stream (null, outs);
	try {
		writer.write (new OLLMrpc.Request () {
			id = 7,
			method = "ClientCert.request_registration",
			args = OLLMrpc.args ("ay", new GLib.Bytes (marker))
		});
		outs.close ();
	} catch (GLib.Error e) {
		printerr ("encode bytes: %s\n", e.message);
		return 1;
	}
	var bytes_frame = mem.steal_as_bytes ();
	encoded.add (bytes_frame);
	needles.add (none);
	repls.add (none);
	fnames.add ("ok.bin");
	encoded.add (bytes_frame);
	needles.add (new GLib.Bytes (needle));
	repls.add (cap_len);
	fnames.add ("bytes-cap.bin");
	encoded.add (bytes_frame);
	needles.add (new GLib.Bytes (needle));
	repls.add (max_len);
	fnames.add ("bytes-max.bin");

	mem = new GLib.MemoryOutputStream.resizable ();
	outs = new GLib.DataOutputStream (mem);
	writer = new OLLMrpc.Bin.Stream (null, outs);
	var one = new GLib.Variant.from_bytes (
		new GLib.VariantType ("ay"), new GLib.Bytes (marker), true);
	GLib.Variant[] kids = { one };
	var arr = new GLib.Variant.array (new GLib.VariantType ("ay"), kids);
	var arr_val = GLib.Value (typeof (GLib.Variant));
	arr_val.set_variant (arr);
	var arr_req = new OLLMrpc.Request () {
		id = 8,
		method = "ClientCert.request_registration"
	};
	arr_req.args.add (arr_val);
	try {
		writer.write (arr_req);
		outs.close ();
	} catch (GLib.Error e) {
		printerr ("encode array: %s\n", e.message);
		return 1;
	}
	var array_frame = mem.steal_as_bytes ();
	encoded.add (array_frame);
	needles.add (new GLib.Bytes (needle));
	repls.add (cap_len);
	fnames.add ("array-cap.bin");
	encoded.add (array_frame);
	needles.add (new GLib.Bytes (needle));
	repls.add (max_len);
	fnames.add ("array-max.bin");

	mem = new GLib.MemoryOutputStream.resizable ();
	outs = new GLib.DataOutputStream (mem);
	writer = new OLLMrpc.Bin.Stream (null, outs);
	var framed = GLib.Value (typeof (GLib.VariantType));
	framed.set_boxed (new GLib.VariantType ("(ay)"));
	var vt_req = new OLLMrpc.Request () {
		id = 9,
		method = "ClientCert.request_registration"
	};
	vt_req.args.add (framed);
	try {
		writer.write (vt_req);
		outs.close ();
	} catch (GLib.Error e) {
		printerr ("encode vtype: %s\n", e.message);
		return 1;
	}
	var vtype_frame = mem.steal_as_bytes ();
	encoded.add (vtype_frame);
	needles.add (new GLib.Bytes (vtype_needle));
	repls.add (cap_len);
	fnames.add ("vtype-cap.bin");
	encoded.add (vtype_frame);
	needles.add (new GLib.Bytes (vtype_needle));
	repls.add (vtype_max);
	fnames.add ("vtype-max.bin");

	mem = new GLib.MemoryOutputStream.resizable ();
	outs = new GLib.DataOutputStream (mem);
	writer = new OLLMrpc.Bin.Stream (null, outs);
	try {
		writer.write (new OLLMrpcTests.CapPair () {
			name = string.nfill (32768, 'z'),
			count = 1
		});
		outs.close ();
	} catch (GLib.Error e) {
		printerr ("encode prop: %s\n", e.message);
		return 1;
	}
	var prop_frame = mem.steal_as_bytes ();
	encoded.add (prop_frame);
	needles.add (new GLib.Bytes (prop_needle));
	repls.add (cap_len);
	fnames.add ("prop-cap.bin");
	encoded.add (prop_frame);
	needles.add (new GLib.Bytes (prop_needle));
	repls.add (max_len);
	fnames.add ("prop-max.bin");

	for (var i = 0; i < encoded.size; i++) {
		var raw = encoded.get (i).get_data ();
		var nd = needles.get (i).get_data ();
		var at = -1;
		var matches = 0;
		if (nd.length > 0) {
			for (var p = 0; p + nd.length <= raw.length; p++) {
				var same = true;
				for (var q = 0; q < nd.length; q++) {
					if (raw[p + q] != nd[q]) {
						same = false;
						break;
					}
				}
				if (!same) {
					continue;
				}
				matches++;
				at = p;
			}
		}
		if (nd.length > 0 && matches != 1) {
			printerr ("frame %s needle matches %d\n", fnames.get (i), matches);
			return 1;
		}
		var copy = new uint8[raw.length];
		GLib.Memory.copy (copy, raw, raw.length);
		if (at >= 0) {
			var rep = repls.get (i).get_data ();
			for (var q = 0; q < rep.length; q++) {
				copy[at + q] = rep[q];
			}
		}
		var path = GLib.Path.build_filename (dir, fnames.get (i));
		try {
			GLib.FileUtils.set_data (path, copy);
		} catch (GLib.Error e) {
			printerr ("write %s: %s\n", path, e.message);
			return 1;
		}
	}

	var jobs = new Gee.ArrayList<string> ();
	var files = new Gee.ArrayList<string> ();
	jobs.add ("bin-ok");
	files.add ("ok.bin");
	jobs.add ("bin-bytes-cap");
	files.add ("bytes-cap.bin");
	jobs.add ("bin-bytes-max");
	files.add ("bytes-max.bin");
	jobs.add ("bin-array-cap");
	files.add ("array-cap.bin");
	jobs.add ("bin-array-max");
	files.add ("array-max.bin");
	jobs.add ("bin-vtype-cap");
	files.add ("vtype-cap.bin");
	jobs.add ("bin-vtype-max");
	files.add ("vtype-max.bin");
	jobs.add ("bin-prop-cap");
	files.add ("prop-cap.bin");
	jobs.add ("bin-prop-max");
	files.add ("prop-max.bin");
	jobs.add ("sock-ok");
	files.add ("ok.bin");
	jobs.add ("sock-cap");
	files.add ("bytes-cap.bin");
	jobs.add ("sock-max");
	files.add ("bytes-max.bin");
	jobs.add ("http-ok");
	files.add ("ok.bin");
	jobs.add ("http-cap");
	files.add ("bytes-cap.bin");
	jobs.add ("http-max");
	files.add ("bytes-max.bin");

	var failed = 0;
	for (var i = 0; i < jobs.size; i++) {
		var frame_path = GLib.Path.build_filename (dir, files.get (i));
		string[] argv = { exe, "--case", jobs.get (i), frame_path };
		GLib.Subprocess proc;
		try {
			proc = new GLib.Subprocess.newv (argv,
				GLib.SubprocessFlags.STDOUT_PIPE |
				GLib.SubprocessFlags.STDERR_MERGE);
		} catch (GLib.Error e) {
			printerr ("spawn %s: %s\n", jobs.get (i), e.message);
			failed++;
			continue;
		}
		string? output = null;
		string? err_out = null;
		try {
			proc.communicate_utf8 (null, null, out output, out err_out);
		} catch (GLib.Error e) {
			printerr ("wait %s: %s\n", jobs.get (i), e.message);
		}
		if (output != null && output != "") {
			print ("%s", output);
			if (!output.has_suffix ("\n")) {
				print ("\n");
			}
		}
		if (proc.get_if_signaled ()) {
			printerr ("FAIL %s signal %d\n", jobs.get (i), proc.get_term_sig ());
			failed++;
			continue;
		}
		if (!proc.get_if_exited () || proc.get_exit_status () != 0) {
			printerr ("FAIL %s status %d\n", jobs.get (i), proc.get_status ());
			failed++;
			continue;
		}
		print ("PASS %s\n", jobs.get (i));
	}
	if (failed != 0) {
		return 1;
	}
	return 0;
}
