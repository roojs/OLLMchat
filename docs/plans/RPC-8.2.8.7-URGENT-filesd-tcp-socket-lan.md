# 8.2.8.7 — URGENT — File-daemon TCP socket on the LAN (TLS + registration)

**Status:** **URGENT** — design only; code proposals not yet written

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:**

- [`RPC-8.2.7-client-cert-registration.md`](RPC-8.2.7-client-cert-registration.md) — `filesd.socket` reserved; HTTPS registration already in tree
- [`RPC-8.2.8.3-DONE-filesd-file-server-tls.md`](done/RPC-8.2.8.3-DONE-filesd-file-server-tls.md) — File Server expander is HTTPS host/port/proxy/systemd
- **Windows loopback port** is a **bug**, not this plan: [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md)

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- 🔷 Bind the **bin TCP** listener from `filesd.socket` (`host:port`), the same way HTTPS is bound from `filesd.https`.
- 🔷 Linux: `filesd.socket` empty or port **0** → **do not** bind TCP; the **Unix** socket stays the local app path (`filesd.unix`).
- 🔷 Opening that TCP socket on a **LAN interface** (not only loopback) needs **TLS + client-certificate registration**, the same idea as the HTTPS file server.
- 🔷 LAN only. This path is **not** for the public internet: no nginx PROXY, no WAN registration, no reverse-proxy IP rewrite.
- 🔷 The phone uses this socket on the home LAN and the office LAN. HTTPS is only for when the phone is outside those networks.
- 🔷 Connections calls the row Desktop server. It expands. That row has no control on the right. Subtitle says what is running.
- ℹ️ HTTPS remains the internet / proxy path ([`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md)).
- ℹ️ Today the row is File Server in `ollmapp/SettingsDialog/FileServerRow.vala`: one Enabled switch, then Host / Port / Proxy, and systemd as an inner row.
- ⏳ Row layout is below. Code fences after the TLS-on-bin-TCP shape is agreed.

---

## Current behaviour

- ℹ️ `Config2.filesd.unix` (bool, default on) and `filesd.socket` (`host:port`, default empty) are **config-only**. `ollmfilesd` never starts `TcpListen` from `filesd.socket`.
- ℹ️ Linux daemon: Unix `SocketListen` unless CLI `--tcp` / `--tcp-host` / `--tcp-port`. HTTPS is a **second** listener from `filesd.https`.
- ℹ️ `TcpListen` is **plaintext** bin RPC. Docblock already says a public bind needs an authenticated transport first (`libocrpc/Transport/TcpListen.vala`).
- ℹ️ HTTPS registration: product-CA TLS + `OLLMfilesd.Https.allow_rpc` + `ClientCert` (`request_registration` / accept / reject / ban).
- ℹ️ File Server UI edits `https` / `proxy` / `systemd` only. No socket host/port rows.
- ℹ️ Windows loopback TCP is hardcoded **4141** — [`2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md).

---

## Design decisions

- 🔷 `filesd.socket` stays `host:port` (empty = TCP off). Same split as `filesd.https` (`last_index_of(":")`).
- 🔷 Linux port **0** or missing port → treat as **off** (Unix only). Not an ephemeral TCP bind.
- 🔷 Unix on Linux, and localhost TCP on Windows, stay up. Those rows have no switch.
- 🔷 LAN bind (an address that is not loopback) uses TLS and the same registration gate as HTTPS (client cert, pending / accept / ban).
- 🔷 No PROXY Protocol on the local network socket. Client IP is the TCP peer.
- 🔷 Do not publish this socket past the local network. WAN clients use HTTPS + nginx as today.
- 🔷 Local network socket default port is 8422. HTTPS default port is 8443.
- 🔷 Local network socket host list excludes localhost (`127.0.0.1`).
- 🔷 `⏳` Joining still needs a client certificate and the approval process. Anyone can make a certificate and request to join. Whether that is enough is not decided.

- 💩 Reuse the existing `ClientCert` SQLite rows (same fingerprints) so Accept once covers HTTPS and LAN TCP.
- 💩 Loopback `127.0.0.1` TCP may stay plaintext (Windows pattern). TLS required only when the host is a LAN address.
- 💩 Bin framing on the TLS stream (not HTTP/JSON). First-byte JSON line mode stays out of this plan.
- 💩 `filesd.unix` stays true. The Unix row does not write it false.

---

## Phase 1 — Honor `filesd.socket` on Linux (`⏳`)

- 🔷 `⏳` `ollmfilesd` starts `TcpListen` when `filesd.socket` is a valid `host:port` and port is in **1024–65535**.
- 🔷 `⏳` Empty / port 0 → no `TcpListen`. Unix listen unchanged when `filesd.unix` is true.
- 🔷 `⏳` CLI `--tcp*` remains for tests; config is the desktop path (no new listen flags).
- ⏳ Code proposals — after Phase 2 TLS shape, or a first plaintext-loopback-only slice if that is approved.

---

## Phase 2 — TLS on the LAN TCP socket (`⏳`)

- 🔷 `⏳` Non-loopback `filesd.socket` wraps the accepted stream in TLS (product CA leaf, same `Transport.Cert` install as `Https.listen`).
- 🔷 `⏳` Request a **client certificate**. Unknown cert: only `request_registration`. Approved cert: full bin RPC.
- 🔷 `⏳` Ban list: drop by peer IP before TLS, same as HTTPS (`HttpServer.banned_ips`).
- 💩 `⏳` Implement as TLS on `TcpListen` / `Connection`, not a second Soup HTTP server on that port.
- ⏳ Code proposals — after this wrap is chosen.

---

## Connections rows

🔷 Desktop server is one expander. Nothing sits on the right of that row. The subtitle says what is running, for example Running on socket, or Running via systemd.

```
Linux — expanded

┌ Desktop server                                          ┐
│  subtitle: Running on socket                            │
│    Unix socket                               Running    │
│    systemd                                   [  ○   ]   │
│  ▸ HTTPS server                              [  ○   ]   │
│  ▸ Local network socket                      [  ○   ]   │
└─────────────────────────────────────────────────────────┘
```

🔷 Unix socket is the first row on Linux. It is not an expander and it has no toggle. The row says Running.

🔷 systemd is the next row, above HTTPS server. The toggle is on that row.

🔷 HTTPS server has an on/off toggle. It expands to Host, Port, and Proxy. Port placeholder is 8443. The listener is `filesd.https`.

```
│  ▾ HTTPS server                              [  ○   ]   │
│      Host                                     [ ▾ ip ]  │
│      Port                                     [ 8443 ]  │
│      Proxy                                    [  ○   ]  │
```

🔷 Local network socket has an on/off toggle. It expands to Host and Port. Port placeholder is 8422. The host list leaves out `127.0.0.1`. Subtitle: Don't put this on the internet.

```
│  ▾ Local network socket                      [  ○   ]   │
│      Don't put this on the internet                     │
│      Host                        [ ▾ ip, no 127.0.0.1 ] │
│      Port                                     [ 8422 ]  │
```

🔷 The local network socket toggle shows after a host and port are saved. Before that, the row expands to Host and Port with no toggle.

🔷 Windows has no Unix socket row and no systemd row. Localhost TCP is the first row: listed Running, no toggle.

```
Windows — expanded

┌ Desktop server                                          ┐
│  subtitle: Running on localhost TCP                     │
│    Localhost TCP                             Running    │
│  ▸ HTTPS server                              [  ○   ]   │
│  ▸ Local network socket                      [  ○   ]   │
└─────────────────────────────────────────────────────────┘
```

- 🔷 `⏳` Replace the File Server Enabled suffix with this layout in `FileServerRow`.
- 🔷 `⏳` HTTPS server and Local network socket each have an on/off toggle. Off keeps the saved host and port and does not listen.
- 💩 `⏳` Those toggles are `Gtk.Switch`, same as today's File Server Enabled switch.
- 💩 `⏳` “Set up” means `filesd.socket` has a host and a port in 1024–65535.
- 💩 `⏳` Localhost TCP subtitle can show the live listen address. The row stays status-only.
- ℹ️ Windows loopback port is still [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md). This row does not add a port editor for it.
- ℹ️ Windows does not build `FileServerRow` today (`ConnectionsPage.vala`, `#if !ANDROID && !G_OS_WIN32`).

## Phase 3 — Client + Connections UI (`⏳`)

- 🔷 `⏳` A LAN client connects with device cert + trust (same `Cert.ensure` as HTTPS file connection), to the socket `host:port`, not an `https://` URL.
- 🔷 `⏳` Desktop server Local network socket edits `filesd.socket` host and port. Apply/reboot when those fields change (same bounce as HTTPS).
- ℹ️ Outbound “Add file connection” today is HTTPS URL only ([`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md)). A `tcp://` / TLS-socket client row is this phase if we want phone-on-LAN without HTTPS.
- ⏳ Code proposals — after Phase 2 compiles. Row layout is Connections rows above.

---

## Suggested order

1. ⏳ Phase 1 — daemon binds `filesd.socket` (Linux; port 0 / empty = Unix only)
2. ⏳ Phase 2 — TLS + registration on non-loopback
3. ⏳ Phase 3 — client + Desktop server rows (Unix or Localhost TCP, systemd on Linux, HTTPS server, Local network socket)
4. ℹ️ Windows localhost TCP stays a Running row here. Changing its port is the bug log, not these phases.

---

## LLM notes

- ℹ️ Parent 8.2.8 HTTPS UI and Android takeover stay on their sub-plans.
- 🚫 nginx stream / PROXY Protocol on `filesd.socket`.
- 🚫 Advertising this socket on the public internet.
- 🚫 Replacing HTTPS with TCP for WAN / Android-over-internet.
- 🚫 A control on the right of the Desktop server row. Subtitle only.
- 🚫 A toggle on Unix socket, or on Windows Localhost TCP.
- 🚫 `127.0.0.1` in the Local network socket host list.
- 🚫 systemd on the Desktop server header. It is a row under Unix socket and above HTTPS server.
- 🚫 Titling the TLS row HTTP server. The title is HTTPS server.
- 🚫 A Proxy row on Local network socket.
- 🚫 Turning off the Unix socket because Local network socket is on.
- 🚫 New CLI flags for listen host/port (config object already exists).
- 🚫 Helper methods “for TLS accept” — inline on the existing listen/accept path unless a later fence names one.
