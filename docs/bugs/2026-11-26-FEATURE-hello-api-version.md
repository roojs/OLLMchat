# `RPC-Daemon.hello` has no shared compare of the first two version numbers.

**Status:** ✔️

## User decisions required

None.

## User reported

- 🔷 Propose a generic version compare on the hello object the daemon returns.
- 🔷 Decide whether that compare is implemented in Argus or in OCRPC.
- 🔷 If it is OCRPC, open a bug report there.
- 🔷 A 0.1.60 client connecting to a 0.1.59 server should be allowed. The second-dot versions are the same, 0.1.
- 🔷 A mismatch is reported only when those versions differ. The last number is not a refusal.
- 🔷 The method is `compare`. There is no operator argument.
- 🔷 The second argument is the depth. Depth `1` is the first number, `2` is the first two, `3` is all three.
- 🔷 Return `1` when this version is greater at that depth, `-1` when it is smaller, and `0` when those numbers match.
- 🔷 Append `.0.0.0.0`, split on the dot, join the leading range, and run the usual filename collation compare on those two strings.

## Success scenario

- `Daemon.compare` compares `this.version` to one other version, for a depth of `1`, `2`, or `3`.
- Return is `1` when this version is greater at that depth, `-1` when it is smaller, and `0` when those numbers match.
- A missing number is `0`. `0.1` against `0.1.0` at depth `3` is `0`.
- Hello uses depth `2`. A daemon at `0.1.59` against `0.1.60` returns `0`.
- `compare("0.2.0", 2)` on a `0.1` daemon returns `-1`. The server refuses. The sentence names both full versions.
- A client whose first two numbers are older is accepted. The server logs the warning sentence.
- `ollmfilesd.Daemon` is an `OLLMrpc.Daemon`. Hello sets `version` and calls `this.compare` at depth `2`.
- `Client.connect` calls `compare` at depth `2` on the `Daemon` it got back.
- Argus stops keeping its own copy of the cut once this library method is in the build it links.

## Current behavior

- What you said
  - A 0.1.60 client is refused by a 0.1.59 server.
  - The first two numbers are both 0.1, so that pair should connect.
- Observable product outcome
  - The refusal sentence is `The server is 0.1.59. This client is 0.1.60.`
  - The server that still compares the whole string treats the higher last number as a newer client.

## Codebase observed behavior

- [`libocrpc/Daemon.vala`](../../libocrpc/Daemon.vala) is the hello object. It has `protocol`, `server`, and `ready`. It has no version and no compare.

```vala
public int protocol { get; set; default = 1; }
public string server { get; set; default = ""; }
public bool ready { get; set; default = false; }
```

- [`ollmfilesd/Daemon.vala`](../../ollmfilesd/Daemon.vala) hello is `is` and returns that object. No version is set.

```vala
request.reply(new OLLMrpc.Response() {
	retval = OLLMrpc.val("o", this)
});
```

- [`libocrpc/Client.vala`](../../libocrpc/Client.vala) `connect` treats hello as success when `error` is null. It does not read a version.

```vala
if (hello.error != null) {
	…
	return false;
}
GLib.debug("connect ok hello id=%d", hello_request.id);
return true;
```

- Argus `server/Daemon.vala` compares with `strverscmp` after cutting at the second dot, and returns the full version as a string, not this object.
- Argus clients repeat that cut. The server side uses `strverscmp`. The client side uses `collate_key_for_filename`. Windows has no `strverscmp`.

## Debugging

### Current debug output

- Source: `/tmp/argus-vercmp.c`, `strverscmp` on the pairs below.
  - Takeaway: a whole-string compare refuses 0.1.60 against 0.1.59. The prefix `0.1` does not.

```text
strverscmp("0.1.60", "0.1.59") = 1
strverscmp("0.1", "0.1.59") = -46
strverscmp("0.2", "0.1.59") = 1
strverscmp("0.1", "0.2.0") = -1
strverscmp("0.1", "0.1") = 0
```

### Debug code added (remove when complete)

None.

## Proposed fix

The compare is an instance method on the hello object. `this.version` is the left side. The first argument is the other version. The second argument is the depth. There is no operator. Argus and ollmfilesd both use that object. A second copy in Argus is what drifted (GNU `strverscmp` on the server, `collate_key_for_filename` on the client, and a full-string compare on servers built before the cut).

Apply phases in order. Wiring of the third hello argument and `OLLMchat.VERSION` stays in [`2026-11-21-FEATURE-rpc-daemon-hello-version-mismatch.md`](2026-11-21-FEATURE-rpc-daemon-hello-version-mismatch.md). Where that report compares the whole string, use phase 1's method instead.

### ✔️ Phase 1 — `Daemon.compare`

**Why:** One method. Append `.0.0.0.0`, split on the dot, join the leading range, and compare with `collate_key_for_filename`. Depth is only how long that range is. No per-number loop. No operator argument.

**Where:** [`libocrpc/Daemon.vala`](../../libocrpc/Daemon.vala).

#### Add — property, after `ready`

```vala
public string version { get; set; default = "0.0.0"; }
```

#### Add — method, after `rpc_register`

```vala
/**
 * Compare this version to ''version'' for ''depth'' leading numbers.
 *
 * Append .0.0.0.0, split on the dot, join the leading range,
 * and compare those strings with filename collation. Depth 1
 * is the first number. Depth 2 is the first two. Depth 3 is
 * all three. A missing number is 0.
 *
 * @param version the other version
 * @param depth how many leading numbers to compare
 * @return 1 when this version is greater, -1 when it is smaller,
 *   0 when they match
 */
public int compare(string version, int depth)
{
	var ours = string.joinv(".", (this.version + ".0.0.0.0").split(".")[0:depth]);
	var theirs = string.joinv(".", (version + ".0.0.0.0").split(".")[0:depth]);
	var order = GLib.strcmp(ours.collate_key_for_filename(), theirs.collate_key_for_filename());
	return order > 0 ? 1 : order < 0 ? -1 : 0;
}
```

### ✔️ Phase 2 — hello sets `version` and uses `compare`

**Why:** The server daemon is the hello object, so the gate is `this.compare` at depth `2`.

**Where:** [`ollmfilesd/Daemon.vala`](../../ollmfilesd/Daemon.vala). Subclass `OLLMrpc.Daemon` and drop the copied `protocol`, `server`, and `ready` properties. `hello` is the body below, after the version argument from the 2026-11-21 report exists.

#### Replace with

```vala
public class Daemon : OLLMrpc.Daemon
```

```vala
public void hello(OLLMrpc.Request request, int protocol, string client, string? version = null)
{
	if (protocol > 0) {
		this.protocol = protocol;
	}
	var theirs = (version == null || version == "") ? "0.0.0" : version;
	GLib.debug("hello %s %d %s", client, protocol, theirs);
	this.version = OLLMchat.VERSION;
	if (this.compare(theirs, 2) < 0) {
		request.reply(new OLLMrpc.Response() {
			error = new OLLMrpc.Error.INVALID_PARAMS("The server is " + this.version +
				". This client is " + theirs + ".")
		});
		return;
	}
	var notice = "ok";
	if (this.compare(theirs, 2) > 0) {
		notice = "This client is " + theirs + ". The server is " + this.version + ".";
		GLib.warning("%s", notice);
	}
	request.reply(new OLLMrpc.Response() {
		msg = notice,
		retval = OLLMrpc.val("o", this)
	});
}
```

### ✔️ Phase 3 — `Client.connect` uses `compare`

**Why:** The object that came back holds the server version. A reply that is only a version string is put on a `Daemon` so the same method runs. The gate is depth `2`.

**Where:** [`libocrpc/Client.vala`](../../libocrpc/Client.vala), after hello `error` is null and before `connect ok`.

#### Add

```vala
var client_version = "0.0.0";
if (hello_request.args.size >= 3 &&
	hello_request.args.get(2).holds(typeof(string)) &&
	hello_request.args.get(2).get_string() != "") {
	client_version = hello_request.args.get(2).get_string();
}
var daemon = new OLLMrpc.Daemon();
if (hello.retval.holds(typeof(OLLMrpc.Daemon))) {
	daemon = (OLLMrpc.Daemon) hello.retval.get_object();
}
if (hello.retval.holds(typeof(string)) && hello.retval.get_string() != "") {
	daemon.version = hello.retval.get_string();
}
if (daemon.compare(client_version, 2) < 0) {
	this.connect_error = "The server is " + daemon.version + ". This client is " + client_version + ".";
	GLib.critical("hello version id=%d: %s", hello_request.id, this.connect_error);
	this.disconnect();
	return false;
}
if (daemon.compare(client_version, 2) > 0) {
	GLib.warning("This client is %s. The server is %s.", client_version, daemon.version);
}
```

## LLM

- ℹ️ 2026-11-26: the method is `compare`. No operator. The second argument is the depth (`1`, `2`, or `3`). Return stays `1`, `0`, or `-1`.
- ℹ️ Pad with `.0.0.0.0`, `split(".")`, `string.joinv` the `[0:depth]` range, then `GLib.strcmp` of `collate_key_for_filename`. The return is `order > 0 ? 1 : order < 0 ? -1 : 0`.
- 🚫 PHP operator form (`version_compare(other, ">")`). The caller tests the int.
- ℹ️ The compare is in OCRPC because Argus and ollmfilesd both speak `RPC-Daemon.hello`, and Windows cannot call `strverscmp`.
- ℹ️ Argus today cuts at the second dot in `server/Daemon.vala` and again in each client. That cut is `compare` at depth `2`. Argus adoption is after this library is in the Argus build, not in this report's apply.
- 🚫 Do not ship an Argus-only second copy as the design. A client that sends only `0.1` hides the last number from an old full-string server. That is a workaround, not `compare`.
- ℹ️ Related: [`2026-11-21-FEATURE-rpc-daemon-hello-version-mismatch.md`](2026-11-21-FEATURE-rpc-daemon-hello-version-mismatch.md) Topics 1, 4, 5, and 6 still apply. Topics 2 and 3 call `compare` at depth `2`.
- ✔️ 2026-11-26: phases 1–3 applied. `OLLMchat.VERSION` comes from `libollmchat/version.vala.in`. Hello's wire signature is `iss`. Callers in this repo send that third argument.
- ℹ️ `ollmfilesd.Daemon` also lists `OLLMrpc.Bin.Serializable` so `bin_write_prop` can still skip `app`. `rpc_register` is `new` because the parent has the same name.
- ⏳ Argus hello and its clients still need to call `Daemon.compare` once they link this library.
