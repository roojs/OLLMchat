# ollmfilesd behind nginx (PROXY Protocol)

How to expose **`ollmfilesd`** HTTPS to a phone (or other remote client) through
nginx, with end-to-end TLS and real client IPs for certificate registration.

**See also:** [`docs/plans/RPC-8.2.7-client-cert-registration.md`](plans/RPC-8.2.7-client-cert-registration.md).

---

## Layout

1. Android → nginx `:443` (stream, `proxy_protocol on`)
2. nginx → `ollmfilesd` HTTPS on a local `host:port` (e.g. `127.0.0.1:8443`)
3. TLS terminates on **`ollmfilesd`** (product CA leaf) so the client certificate
   reaches the daemon for registration / gating

Do **not** terminate TLS at nginx for this path — that would hide the client cert.

---

## `config.2.json`

Under `~/.config/ollmchat/config.2.json`:

```json
"filesd": {
  "unix": true,
  "socket": "",
  "https": "127.0.0.1:8443",
  "proxy": true,
  "systemd": true
}
```

| Key | Meaning |
|-----|---------|
| `https` | `host:port` for HTTPS RPC (empty = off) |
| `proxy` | Expect PROXY Protocol v1 from nginx |
| `systemd` | Install/enable the user unit on daemon start |
| `unix` / `socket` | Reserved; current Unix / `--tcp` behaviour unchanged |

On first HTTPS listen, `ollmfilesd` extracts the product CA PEM and private key
from GResource into `~/.local/share/ollmchat/tls/` (`ollmrpc-ca.pem` and
`ollmrpc-ca-key.pem`). Operators do not copy TLS files by hand. Leaf
`server.pem` / `server-key.pem` are minted there via `Transport.Cert`.

---

## nginx stream

```nginx
stream {
    server {
        listen 443;
        proxy_pass 127.0.0.1:8443;
        proxy_protocol on;
    }
}
```

Match `proxy_pass` to `filesd.https`. Keep TLS passthrough (no `ssl_preread`
required for this simple forward).

---

## systemd user unit

With `"systemd": true`, `Filesd.install()` writes
`~/.config/systemd/user/ollmfilesd.service` only when the contents differ,
reloads when it wrote, and runs `enable --now` only if the unit is not
already active (skipped when the process already has `INVOCATION_ID`).

Enable lingering if the daemon should survive logout:

```bash
loginctl enable-linger "$USER"
```

---

## Registration (admin)

Unknown client certs may only call `RPC-Daemon.request_registration`. Pending
rows are keyed by client IP (from the PROXY header when `proxy` is true).
Approve pending clients from the daemon CLI once Phase 2 lands (`list` /
`accept` / `reset`).
