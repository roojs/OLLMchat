# OLLMchat

<div align="center">
  <img src="https://raw.githubusercontent.com/roojs/OLLMchat/fdae4de262289db49def51443d6b28be06b9eece/pixmaps/scalable/apps/org.roojs.ollmchat.svg" alt="OLLMchat Logo" width="200">
</div>

## Summary

OLLMchat is an AI application for interacting with LLMs (Large Language Models) such as Ollama and OpenAI. It has a full chat interface and a code assistant with semantic codebase search. The main application is a complete AI chat client, built from reusable libraries that other applications can use. The project is written in Vala, with GTK4 for the desktop UI.

The application is split in two. **`ollmfilesd`** is the file server: it handles file operations, file monitoring, and running applications, and it can run on another machine. The desktop and mobile clients talk to that server. A client can run on the same machine as the server, or on a separate desktop, tablet, or phone.

**Development status:** The chat client, tools, and file server are in everyday use. The **skills / task-runner** pipeline in `liboccoder` is mostly working and still early — useful for multi-step agent work, with rough edges. Local **GGUF inference** via `CallLocal` is optional at build time.

- **Main Application (`ollmchat`)** - A complete AI chat client with:
  - Full-featured chat interface for interacting with LLMs (Ollama/OpenAI)
  - Settings dialog with model search and download from Ollama
  - Code assistant agent with semantic codebase search capabilities
  - Chat history management with session browser
  - Tool integration: ReadFile, EditMode, RunCommand, WebFetch, CodebaseSearch (semantic search), and MCP servers (Model Context Protocol)
  - Project management and file tracking
  - Support for multiple agent types (Just Ask, Code Assistant)
- **Core libraries** - Chat, files, editor, markdown, and the file server
  - `libollmchat.so` - Ollama/OpenAI API access, agents, and optional local GGUF backend
  - `libollmchatgtk.so` - GTK chat widgets
  - `libocmarkdown.so` - Markdown parsing and rendering
  - `libocmarkdowngtk.so` - Markdown rendering widgets
  - `libocsqlite.so` - SQLite query builder
  - `libocrpc.so` - Binary RPC wire types for clients of the file server
  - `libocfiles.so` - Client-side file and project management
  - `liboccoder.so` - Code editor, skills/task runner, and project management
  - `libocvector2.so` - Vector index and semantic search, used by the file server
  - `ollmfilesd` - File server (file operations, monitoring, application execution, and semantic indexing; not a shared library)
- **Tool libraries** - Agent tools and live model catalogs
  - `liboctools.so` - File, command, web fetch, and codebase-search tools
  - `libocmcp.so` - MCP (Model Context Protocol) client: load servers from `~/.config/ollmchat/mcp.json`, discover tools, and expose them as `mcp:{server_id}:{tool_name}`
  - `libollamaweb.so` - Live search and model metadata from ollama.com
- **Example Tools** - Command-line utilities demonstrating library capabilities:
  - `ollmchat-cli` - Command-line LLM chat and agent-tool testing (models, chat, streaming, `--agent-tool`)
  - `oc-test-files` - Test tool for file operations (read/write files with line ranges, project management, buffer operations, backups)
  - `oc-markdown-test` - Markdown parser test tool (parses markdown and outputs callback trace)
  - `oc-html2md` - HTML to Markdown converter (reads HTML from stdin, outputs Markdown)
  - `oc-md2html` - Markdown to HTML converter (converts markdown file to HTML)
  - `oc-diff` - Unified diff tool (compares two files and outputs differences in unified diff format)
  - `oc-vector-index` - Codebase indexing client for the file server
  - `oc-vector-search` - Semantic code search client for the file server
  - `oc-migrate-editors` - Project migration tool (migrates projects from Cursor editor configuration)
  - `oc-test-fetch` - Web fetch test tool (fetches web content from URLs with format conversion support)

Risky commands, such as executing bash and posting browser data, require approval. Approval can be permanent or temporary.

As with Pi, you can edit the prompt templates.

## Demo


<video src="https://private-user-images.githubusercontent.com/415282/531191747-fe26dd80-43a4-452f-a6c8-a8eb2b08e272.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjcxNzM0OTMsIm5iZiI6MTc2NzE3MzE5MywicGF0aCI6Ii80MTUyODIvNTMxMTkxNzQ3LWZlMjZkZDgwLTQzYTQtNDUyZi1hNmM4LWE4ZWIyYjA4ZTI3Mi5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMjMxJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTIzMVQwOTI2MzNaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT0xNWFlZDI4OGEwZGQyNmNhOGJjMTQ1YmQ1NmMxYjI1ZjdhMmY5MjZjOTJiYTg2ZTJlY2Y1YjI1MjhmZjMxM2QwJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.jcRmckGG_ypxbnC399j9ebIN8ANhVeWt9Zx6Bxe0tyE" controls width="100%"></video>

This is using gpt-oss to implement a plan and create code


<video src="https://private-user-images.githubusercontent.com/415282/524658129-c8c8dba0-86df-46ff-bdb5-0773ced236da.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjUzNDYyNjMsIm5iZiI6MTc2NTM0NTk2MywicGF0aCI6Ii80MTUyODIvNTI0NjU4MTI5LWM4YzhkYmEwLTg2ZGYtNDZmZi1iZGI1LTA3NzNjZWQyMzZkYS5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMjEwJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTIxMFQwNTUyNDNaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT1kN2QwOGRhNWVjZjM0ZDlkMDI0ZmVmY2EzM2ZkZjYyYzJlOGFmNjc1ODBkMDMzZGE5MDVkNTAyNjEzMDgzNGYyJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.GPlCLeqcdphew7wCeMQ5o29_kt9SW8Fiq3WhSJw_-54" controls width="100%"></video>

This is the basic bootstrapping window - and a walk around some of the earlier features.

**Note:** If the videos above dont display, you can 

[watch it directly here](https://private-user-images.githubusercontent.com/415282/531191747-fe26dd80-43a4-452f-a6c8-a8eb2b08e272.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjcxNzM0OTMsIm5iZiI6MTc2NzE3MzE5MywicGF0aCI6Ii80MTUyODIvNTMxMTkxNzQ3LWZlMjZkZDgwLTQzYTQtNDUyZi1hNmM4LWE4ZWIyYjA4ZTI3Mi5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMjMxJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTIzMVQwOTI2MzNaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT0xNWFlZDI4OGEwZGQyNmNhOGJjMTQ1YmQ1NmMxYjI1ZjdhMmY5MjZjOTJiYTg2ZTJlY2Y1YjI1MjhmZjMxM2QwJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.jcRmckGG_ypxbnC399j9ebIN8ANhVeWt9Zx6Bxe0tyE).



[watch it directly here](https://private-user-images.githubusercontent.com/415282/524658129-c8c8dba0-86df-46ff-bdb5-0773ced236da.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjUzNDYyNjMsIm5iZiI6MTc2NTM0NTk2MywicGF0aCI6Ii80MTUyODIvNTI0NjU4MTI5LWM4YzhkYmEwLTg2ZGYtNDZmZi1iZGI1LTA3NzNjZWQyMzZkYS5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMjEwJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTIxMFQwNTUyNDNaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT1kN2QwOGRhNWVjZjM0ZDlkMDI0ZmVmY2EzM2ZkZjYyYzJlOGFmNjc1ODBkMDMzZGE5MDVkNTAyNjEzMDgzNGYyJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.GPlCLeqcdphew7wCeMQ5o29_kt9SW8Fiq3WhSJw_-54).

## Documentation

Online API documentation is available:

- **[ollmchat API Reference](https://roojs.github.io/OLLMchat/ollmchat/index.htm)** - Unified library documentation (base and UI)

Implementation plans and roadmap:

- **[Building from source](docs/BUILD.md)** - Meson/Ninja, dependencies, and uninstalled runs
- **[Implementation Plans Summary](docs/plans/-README.md)** - Overview of all planned features with status indicators
- **[MCP server settings](docs/mcp-settings.md)** - How to configure `mcp.json` for Model Context Protocol tools
- **[Binary RPC wire format](docs/bin-rpc-protocol.md)** - On-the-wire layout for `ollmfilesd` ↔ client (`libocrpc`)

Development standards (written for AI agents; **mandatory** for agents, helpful guides for human contributors):

- **[Coding standards](docs/coding-standards.md)** - Vala style and patterns
- **[Build rules](docs/build-rules.md)** - Meson/Ninja workflow for agents
- **[Code documentation](docs/code-documentation.md)** - Valadoc markup for docblocks
- **[Guide to writing plans](docs/guide-to-writing-plans.md)** - Plan layout, checklist, and implementation workflow
- **[Project structure](docs/project-structure.md)** - Libraries, the file server, and directory layout
- **[Creating releases](docs/creating-releases.md)** - How tagged releases and CI packaging work

## Releases

Set up the APT or RPM repository from the [roojs package repositories](https://roojs.github.io/repos/) page, then:

```bash
sudo apt install ollmchat
```

```bash
sudo dnf install ollmchat
```

Windows, Android, and AppImage builds are on the [GitHub Releases](https://github.com/roojs/OLLMchat/releases).

## Artificial intelligence usage

This project was developed with the assistance of artificial intelligence.

- Architecture and design direction are human-led
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Changes were reviewed, revised, and approved before landing
- Application code is treated as author-approved

Limited exceptions apply mainly to build scaffolding.

## License

This project is licensed under the GNU Lesser General Public License version 3.0 (LGPL-3.0). See the [LICENSE](LICENSE) file for details.

**Exceptions** (third-party / derived files, e.g. Pi MIT prompt text): see [`licenses/README.md`](licenses/README.md).

