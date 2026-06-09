# MCP server settings

OLLMchat can load [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) servers and expose their tools to the agent alongside built-in tools (`read_file`, `run_command`, etc.).

Configuration is a single file:

`~/.config/ollmchat/mcp.json`

The file must be a **JSON array**. Each element is one MCP server. If the file is missing or invalid, no MCP tools are loaded (the app still runs normally).

Implementation details and history: [plans/done/2.11-DONE-mcp-loader-tool.md](plans/done/2.11-DONE-mcp-loader-tool.md).

---

## How it works

1. On startup, `OLLMmcp.Registry` reads `mcp.json`.
2. For each entry with `"enabled": true`, the app creates a client (`stdio` or `http`).
3. The client calls MCP `initialize`, then `tools/list`.
4. Each tool is registered as `mcp:{id}:{tool_name}` (for example `mcp:chrome:navigate`).
5. When the agent calls that tool, OLLMchat sends MCP `tools/call` to the same server.

MCP tools appear in the agent tool list like any other tool. There is no separate MCP settings UI yet; edit `mcp.json` and restart the app (or open a new chat session after changing tools, depending on when your build calls `fill_tools`).

---

## Minimal example

Create the config directory if needed:

```bash
mkdir -p ~/.config/ollmchat
```

Example `~/.config/ollmchat/mcp.json`:

```json
[
  {
    "id": "filesystem",
    "enabled": true,
    "transport": "stdio",
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/mcp-allowed"],
    "env": {}
  }
]
```

After restart, tools from that server should show up with names like `mcp:filesystem:read_file`.

---

## Field reference

| Field | Required | Default | Applies to |
|-------|----------|---------|------------|
| `id` | yes | — | all | Unique server key; used in tool names (`mcp:{id}:…`). |
| `enabled` | no | `true` | all | If `false`, this server is skipped. |
| `transport` | no | `"stdio"` | all | `"stdio"` or `"http"`. |
| `command` | stdio | `""` | stdio | Executable to run (e.g. `npx`, `node`). |
| `args` | no | `[]` | stdio | JSON array of command-line arguments. |
| `env` | no | `{}` | stdio | JSON object of extra environment variables. |
| `url` | http | `""` | http | Base URL of a running MCP HTTP server. |
| `network` | no | `false` | stdio | If `true`, allow network inside the sandbox (see below). |
| `allow_write` | no | (none) | stdio | Extra writable host paths (see below). |
| `allow_unsandboxed` | no | `false` | stdio | Opt in to stdio MCP without bubblewrap (see below). |

### stdio transport

OLLMchat **starts** the MCP server as a subprocess and talks JSON-RPC over stdin/stdout (newline-delimited messages).

On a normal Linux host (not Flatpak), the subprocess is started under **bubblewrap** with restricted filesystem and network access. You need `bwrap` installed (`bubblewrap` package). On that path, `network` and `allow_write` apply; `allow_unsandboxed` is ignored.

If bubblewrap is unavailable (Flatpak, Windows), stdio MCP requires `"allow_unsandboxed": true` and runs as a direct subprocess without OLLMchat's sandbox — see [Unsandboxed stdio](#unsandboxed-stdio-allow_unsandboxed).

Typical pattern for Node-based MCP packages:

```json
{
  "id": "chrome",
  "enabled": true,
  "transport": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-chrome"],
  "env": {},
  "network": true
}
```

Set `"network": true` when the MCP server must reach the network (browser control, remote APIs, etc.). Default is no network (`--unshare-net` in the sandbox).

### http transport

OLLMchat **connects** to an MCP server that is already running. No subprocess is spawned.

```json
{
  "id": "local",
  "enabled": true,
  "transport": "http",
  "url": "http://127.0.0.1:3000"
}
```

Use the URL your MCP server documents (path included if the server expects it on the base URL).

---

## Filesystem writes (`allow_write`)

For stdio servers, extra host write access is controlled by `allow_write` in `mcp.json` (JSON key is singular **`allow_write`**, not `allow_writes`).

- **Omitted:** default sandbox only (with an active project, project overlay rules apply; without a project, very limited writes such as `/tmp`).
- **String:** colon-separated list of absolute directory roots, e.g. `"/home/you/data:/tmp/mcp-out"`.
- **Array:** JSON array of roots, e.g. `["/home/you/data", "/tmp/mcp-out"]`.
- **`"project"`:** request project-directory writes (only meaningful when a project is open in OLLMchat).

Example:

```json
"allow_write": ["/home/you/mcp-workspace"]
```

Policy is fixed in config at spawn time; MCP does not show a separate permission dialog for these paths.

**Note:** `allow_write` only applies when bubblewrap is used (normal Linux host). It has no effect on the unsandboxed path (Flatpak or Windows with `allow_unsandboxed`).

---

## Unsandboxed stdio (`allow_unsandboxed`)

By default, OLLMchat refuses to run stdio MCP unless it can apply its own **bubblewrap** sandbox (read-only root, optional network lockdown, project overlay, seccomp monitoring).

Set `"allow_unsandboxed": true` only when bubblewrap cannot be used and you accept running the MCP server as a **direct subprocess** with no OLLMchat sandbox layer:

| Environment | Default behaviour | With `"allow_unsandboxed": true` |
|-------------|-------------------|----------------------------------|
| Linux host (bwrap installed) | Always sandboxed; flag ignored | Still sandboxed (flag ignored) |
| Linux host (no bwrap) | Refused | Refused |
| Flatpak | Refused | Direct spawn (Flatpak outer sandbox only) |
| Windows | Refused | Direct spawn (full user privileges) |

```json
"allow_unsandboxed": true
```

On the unsandboxed path:

- The MCP server can access anything OLLMchat (or the Flatpak sandbox) can access.
- **`network` and `allow_write` do not apply** — there is no bubblewrap layer to configure.
- Seccomp violation hints are not appended to tool output.

Only enable this for servers you trust. HTTP transport is unaffected (no local spawn).

---

## Multiple servers

You can list several objects in the array. Tool names are always prefixed with the server `id`, so names do not collide:

```json
[
  {
    "id": "chrome",
    "enabled": true,
    "transport": "stdio",
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-chrome"],
    "network": true
  },
  {
    "id": "mysql",
    "enabled": true,
    "transport": "http",
    "url": "http://127.0.0.1:3000"
  }
]
```

Disable a server temporarily with `"enabled": false` without removing its block.

---

## Troubleshooting

| Symptom | Things to check |
|---------|------------------|
| No MCP tools | File path `~/.config/ollmchat/mcp.json`; root must be a JSON **array**; `"enabled": true`; check app logs for parse/load warnings. |
| stdio fails immediately | `command` on PATH; `args` correct; on Linux host, `bwrap` installed; in Flatpak or on Windows, `allow_unsandboxed: true`. |
| Server needs network | `"network": true` for stdio (bubblewrap path only). |
| Tool call fails / empty result | Server logs; MCP `tools/call` errors appear in tool output; seccomp appendix may mention `mcp.json` and server `id`. |
| HTTP connection fails | Server running; `url` correct; firewall. |

Enable debug logging when running from a terminal to see messages such as `Loaded N MCP server(s) from …`.

---

## Related

- Library: `libocmcp` (`OLLMmcp.*`)
- README: [MCP servers section](../README.md#mcp-servers-libocmcp)
- Plans: [done/2.11-DONE-mcp-loader-tool.md](plans/done/2.11-DONE-mcp-loader-tool.md)
