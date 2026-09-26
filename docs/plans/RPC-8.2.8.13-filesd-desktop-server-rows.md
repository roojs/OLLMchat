# 8.2.8.13 — Desktop server rows and LAN client

**Status:** **⏳** — not started. Linux rows and the LAN client. Windows build is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md).

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:** [`RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md) — `ssl_enabled`, `https_enabled`, and `SslListen` are in the tree

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- 🔷 Desktop server is one expander on the Connections tab. Nothing sits on the right of that row. The subtitle says what is running.
- 🔷 Linux order: Unix socket, systemd, HTTPS server, Local network SSL server.
- 🔷 The LAN client connects to `filesd.socket` `host:port`, not an `https://` URL.
- ℹ️ The TLS listener is already [`8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md). This plan is the rows and the client.
- ℹ️ Windows row layout is drawn below. Building it is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md), later.
- ⏳ Code proposals — not written.

---

## Desktop server rows

🔷 Desktop server is one expander. Nothing sits on the right of that row. The subtitle says what is running, for example Running on socket, or Running via systemd.

```
Linux — expanded

┌ Desktop server                                          ┐
│  subtitle: Running on socket                            │
│    Unix socket                               Running    │
│    systemd                                   [  ○   ]   │
│  ▸ HTTPS server                              [  ○   ]   │
│  ▸ Local network SSL server                  [  ○   ]   │
└─────────────────────────────────────────────────────────┘
```

🔷 Unix socket is the first row on Linux. It is not an expander and it has no toggle. The row says Running.

🔷 systemd is the next row, above HTTPS server. The toggle is on that row.

🔷 HTTPS server has an on/off toggle. It expands to Host, Port, and Proxy. Port placeholder is 8443. The listener is `filesd.https`.

```
│  ▾ HTTPS server                              [  ○   ]   │
│      Host                                     [ ▾ ip ]  │
│      Port                                     [ 8443 ]  │
│      Proxy                                    [  ○   ]   │
```

🔷 Local network SSL server has an on/off toggle. It expands to Host and Port. Port placeholder is 8422. The host list leaves out `127.0.0.1`. Subtitle: Recommended for local networks only.

```
│  ▾ Local network SSL server                  [  ○   ]   │
│      Recommended for local networks only                │
│      Host                        [ ▾ ip, no 127.0.0.1 ] │
│      Port                                     [ 8422 ]  │
```

🔷 The Local network SSL server toggle shows after a host and port are saved. Before that, the row expands to Host and Port with no toggle. The toggle writes `ssl_enabled`. The HTTPS server toggle writes `https_enabled`.

🔷 Windows has no Unix socket row and no systemd row. Localhost TCP is the first row: listed Running, no toggle.

```
Windows — expanded

┌ Desktop server                                          ┐
│  subtitle: Running on localhost TCP                     │
│    Localhost TCP                             Running    │
│  ▸ HTTPS server                              [  ○   ]   │
│  ▸ Local network SSL server                  [  ○   ]   │
└─────────────────────────────────────────────────────────┘
```

- 🔷 `⏳` Replace the File Server Enabled suffix with this layout in `FileServerRow`. Linux host list only.
- 🔷 `⏳` HTTPS server and Local network SSL server each have an on/off toggle. Off keeps the saved host and port and does not listen.
- 🔷 `⏳` Desktop server Local network SSL server edits `filesd.socket` host and port. Apply/reboot when those fields change (same bounce as HTTPS).
- 💩 `⏳` Those toggles are `Gtk.Switch`, same as today's File Server Enabled switch.
- 💩 `⏳` “Set up” means `filesd.socket` has a host and a port in 1024–65535.
- 💩 `⏳` Localhost TCP subtitle can show the live listen address. The row stays status-only.
- ℹ️ Windows loopback port is still [`docs/bugs/2026-09-20-filesd-windows-socket-port.md`](../bugs/2026-09-20-filesd-windows-socket-port.md). This row does not add a port editor for it.
- ℹ️ Windows does not build `FileServerRow` today (`ConnectionsPage.vala`, `#if !ANDROID && !G_OS_WIN32`). The Windows host list and per-user service are [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md).

## LAN client

- 🔷 `⏳` A LAN client connects with device cert + trust (same `Cert.ensure` as HTTPS file connection), to the socket `host:port`, not an `https://` URL.
- ℹ️ Outbound “Add file connection” today is HTTPS URL only ([`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md)). A `tcp://` / TLS-socket client row is this plan.
- ⏳ Code proposals — not written.

---

## LLM notes

- ℹ️ The listener, cert gate, and flags stay on [`8.2.8.7`](RPC-8.2.8.7-URGENT-filesd-tcp-socket-lan.md).
- 🚫 A control on the right of the Desktop server row. Subtitle only.
- 🚫 A toggle on Unix socket, or on Windows Localhost TCP.
- 🚫 `127.0.0.1` in the Local network SSL server host list.
- 🚫 systemd on the Desktop server header. It is a row under Unix socket and above HTTPS server.
- 🚫 Titling the TLS row HTTP server. The title is HTTPS server.
- 🚫 A Proxy row on Local network SSL server.
- 🚫 Turning off the Unix socket because Local network SSL server is on.
- 🚫 Building the Windows host list or a Windows per-user service here. That is [`8.2.8.14`](RPC-8.2.8.14-LATER-filesd-windows-desktop-server.md).
