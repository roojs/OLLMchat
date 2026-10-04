# Avahi broadcast does not start with the PIN dialog

**Status:** ✅ closed 2026-10-04. Publish starts after the client, A records use `hostname-rpc.local`, and the stale `ollmfilesd` process was restarted.

## Problem

- **🔷** Opening **Allow New Device** toasts that the pairing broadcast could not start.
- **🔷** Expected: `_rpc._tcp` is published for the listen addresses while the PIN is showing.

### Evidence

- **ℹ️** The toast is `Could not publish the pairing service`, from `PairPublish.failed` in `ollmapp/SettingsDialog/PairingDialog.vala`.
- **ℹ️** `avahi-daemon` is `active` (0.8) on this machine. State `2` is `GA_CLIENT_STATE_S_RUNNING`.
- **✔️** `/tmp/avahi-order` against the system `libavahi-gobject`:
  - `ga_entry_group_attach` before `ga_client_start` prints `CRITICAL: ga_entry_group_attach: assertion 'client->avahi_client' failed`, returns false, and sets no `GError`.
  - `state-changed 2` is printed from inside `ga_client_start`, before that call returns, and `avahi_client` is set by then.
  - `ga_entry_group_attach` after `ga_client_start` returns true.
- **ℹ️** `ga_entry_group_attach` (`avahi-gobject/ga-entry-group.c`) starts with `g_return_val_if_fail(client->avahi_client, FALSE)`. `client->avahi_client` is assigned only inside `ga_client_start` → `avahi_client_new`.
- **ℹ️** `avahi_client_new` calls `client_set_state`, which calls the client callback before `avahi_client_new` returns (`avahi-client/client.c`). `ga_client_start` emits `state-changed` from that callback (`avahi-gobject/ga-client.c`).

### Root cause

- **🚫** The start/attach order was a real bug, and it is not what still toasts. After that reorder, `client.start()` and `group.attach()` succeed. `commit()` then adds an A record for `hostname.local`. Avahi already owns that name, so the add fails with **Local name collision**. The catch returns false and never calls `group.commit()`, so the service is not published and the dialog toasts.
- **✔️** `/tmp/avahi-commit` uses this machine's name and the configured socket address `192.168.0.16:8422`:
  - `add_service` for `fastboy` / `_rpc._tcp` / host `fastboy.local` returns success.
  - `add_record` for `fastboy.local` → `192.168.0.16` returns **Setting raw record failed: Local name collision**.
  - That is the same call `PairPublish.commit` makes, and that catch is what emits `failed`.
- **✔️** A record browse of the name Avahi already publishes, `fastboy.local`: `192.168.0.16` (wifi), `10.0.3.1` (lxc), `172.17.0.1` (docker), `127.0.0.1` (lo). The VPN address `10.9.188.16` on `tun3` is not among them.
- **✔️** `/tmp/avahi-multi` with host `fastboy-rpc.local` (a name Avahi does not own): both `192.168.0.16` and `10.9.188.16` are added, `commit` succeeds, and a record browse sees both A records. `avahi-browse -rt _rpc._tcp` resolves that service.
- **ℹ️** The first proposal only ran attach-versus-start. It never called `add_record` or `commit`.

## Proposed fix — host name Avahi does not already own

### `libocrpc/Transport/PairPublish.vala` — `commit`: A records on our own name

**Why:** An A record on `hostname.local` collides with the daemon's host records, and `commit` treats that as a failed publish.

**Where:** `PairPublish.commit`, the line that builds `host`, after the hostname is trimmed at the first dot.

**Depends on:** the start/attach reorder already in `start`.

#### Remove

```vala
			var host = name + ".local";
```

#### Replace with

The service name stays the hostname. The SRV target and the A records use a name this process owns, so the listen addresses can be published beside the daemon's own host records.

```vala
			var host = name + "-rpc.local";
```

## Proposed fix

### `libocrpc/Transport/PairPublish.vala` — `start`: start, then attach, then commit

**Why:** Attach needs the client that `start` creates. The `S_RUNNING` signal fires inside `start`, before the method returns, so the handler cannot run until the group is stored.

**Where:** `PairPublish.start`, from `var fresh` through the `fresh ||` return. The `commit()` call under that return stays.

**Depends on:** none.

##### Part 1 — create the client once, without `fresh`

#### Keep

```vala
			this.addresses = addresses;
			this.port = port;
```

#### Remove

```vala
			var fresh = this.client == null;
			if (fresh) {
```

#### Replace with

The client is created on the first call. Later calls reuse it and commit below.

```vala
			if (this.client == null) {
```

##### Part 2 — start, attach, store, then listen

#### Keep

```vala
				var client = new Avahi.Client(Avahi.ClientFlags.NO_FAIL);
				var group = new Avahi.EntryGroup();
```

#### Remove

```vala
				client.state_changed.connect((state) => {
					if (state == Avahi.ClientState.FAILURE) {
						this.failed();
						return;
					}
					if (state != Avahi.ClientState.S_RUNNING) {
						return;
					}
					if (this.commit()) {
						return;
					}
					this.failed();
				});
				try {
					group.attach(client);
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				try {
					client.start();
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				this.client = client;
				this.group = group;
```

#### Replace with

`start` first, so `avahi_client` exists. Attach second. Store the group, then connect, so the synchronous `S_RUNNING` inside `start` is not the call that commits.

```vala
				try {
					client.start();
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				try {
					group.attach(client);
				} catch (Avahi.Error e) {
					this.failed();
					return false;
				}
				this.client = client;
				this.group = group;
				client.state_changed.connect((state) => {
					if (state == Avahi.ClientState.FAILURE) {
						this.failed();
						return;
					}
					if (state != Avahi.ClientState.S_RUNNING) {
						return;
					}
					if (this.commit()) {
						return;
					}
					this.failed();
				});
```

##### Part 3 — commit when the client is already running

#### Keep

```vala
			}
```

#### Remove

```vala
			if (this.client.state == Avahi.ClientState.FAILURE) {
				return false;
			}
			if (fresh || this.client.state != Avahi.ClientState.S_RUNNING) {
				return true;
			}
```

#### Replace with

A failure toasts. `S_RUNNING` reached inside `start` (before the signal was connected) commits here. Any other state waits for the signal.

```vala
			if (this.client.state == Avahi.ClientState.FAILURE) {
				this.failed();
				return false;
			}
			if (this.client.state != Avahi.ClientState.S_RUNNING) {
				return true;
			}
```

#### Keep

```vala
			if (this.commit()) {
				return true;
			}
```

- **🚫** One `Replace with` of the whole method. The old lines and the new lines have to sit next to each other.
- **🚫** Connecting `state_changed` before `start` and committing from that first signal. That signal runs before `attach` can succeed.

## Attempts / changelog

- **✔️** Reproduction program `/tmp/avahi-order.c` (not in the tree).
- **✔️** `libocrpc/Transport/PairPublish.vala` `start`: the three hunks above. `ninja -C build ollmapp/ollmchat`. Opening **Allow New Device** still toasts.
- **✔️** `/tmp/avahi-commit`, `/tmp/avahi-owned`, `/tmp/avahi-multi` (not in the tree). Collision is on `fastboy.local`. `fastboy-rpc.local` publishes both listen addresses.
- **✔️** `PairPublish.commit`: `name + ".local"` is now `name + "-rpc.local"`.

## Next

- **✅** Closed. Allow New Device publishes, and the title bar dismisses the dialog.
