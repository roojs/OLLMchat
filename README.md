# OLLMchat

<div align="center">
  <img src="https://raw.githubusercontent.com/roojs/OLLMchat/fdae4de262289db49def51443d6b28be06b9eece/pixmaps/scalable/apps/org.roojs.ollmchat.svg" alt="OLLMchat Logo" width="200">
</div>

## Summary

OLLMchat is a work-in-progress AI application for interacting with LLMs (Large Language Models) such as Ollama and OpenAI, featuring a full-featured chat interface with code assistant capabilities including semantic codebase search. The project is built as a modular set of reusable libraries that can be integrated into other applications, with the main application serving as a complete AI chat client. The project focuses on Vala and GTK4, with all libraries written in pure Vala.

**Development status:** The core chat stack (`libollmchat`, tools, GTK UI, markdown, and in-process vector search) is mature enough for everyday use. The **skills / task-runner** pipeline in `liboccoder` is mostly working but still very early beta — useful for multi-step agent work, but expect rough edges. Active or experimental areas include the **`ollmfilesd`** file daemon with **`libocrpc`** and **`libocvector2`** (semantic indexing moving out of the UI process; wiring still in progress), **`libollamaweb`** (live Ollama.com model search — partially integrated), local **GGUF inference** via `CallLocal` (proof of concept only, optional at build time), and the **Chatter** agent (summarized history — in progress).

- **Main Application (`ollmchat`)** - A complete AI chat client with:
  - Full-featured chat interface for interacting with LLMs (Ollama/OpenAI)
  - Settings dialog with model search and download from Ollama
  - Code assistant agent with semantic codebase search capabilities
  - Chat history management with session browser
  - Tool integration: ReadFile, EditMode, RunCommand, WebFetch, CodebaseSearch (semantic search), and MCP servers (Model Context Protocol)
  - Project management and file tracking
  - Permission system for secure tool access
  - Support for multiple agent types (Just Ask, Code Assistant)
- **Libraries** - A set of reusable libraries for LLM access, tool integration, and markdown processing
  - `libocmarkdown.so` - Markdown parsing and rendering library (no GTK dependencies)
  - `libocmarkdowngtk.so` - Markdown GTK rendering library (includes GTK components)
  - `libocsqlite.so` - SQLite query builder library (no GTK dependencies)
  - `libocrpc.so` - Binary RPC wire types for daemon clients (`OLLMrpc.Bin`; no GTK dependencies)
  - `libocfiles.so` - File and project management library (no GTK dependencies)
  - `liboccoder.so` - Code editor, skills/task runner, and project management (includes GTK components)
  - `libocvector.so` - Semantic codebase search using vector embeddings and FAISS (no GTK dependencies; in-process)
  - `libocvector2.so` - Slimmer vector index/search for the file daemon (no `libocfiles`; used by `ollmfilesd`)
  - `libollmchat.so` - Base library for Ollama/OpenAI API access, agents, and optional local GGUF backend (no GTK dependencies)
  - `libollamaweb.so` - Live search and model metadata from ollama.com (no GTK dependencies)
  - `liboctools.so` - Tools library for file operations and utilities (no GTK dependencies)
  - `libocmcp.so` - MCP (Model Context Protocol) client: load servers from `~/.config/ollmchat/mcp.json`, discover tools, expose them as `mcp:{server_id}:{tool_name}` agent tools (stdio subprocess or HTTP JSON-RPC; stdio uses `OLLMfiles.Sandbox` via `libocfiles`)
  - `libollmchatgtk.so` - GTK library with chat widgets (includes GTK components)
  - `ollmfilesd` - Headless file and semantic-index daemon (binary RPC over `libocrpc` via stdio or TCP; not a shared library)
- **Example Tools** - Command-line utilities demonstrating library capabilities:
  - `ollmchat-cli` - Command-line LLM chat and agent-tool testing (models, chat, streaming, `--agent-tool`)
  - `oc-test-files` - Test tool for file operations (read/write files with line ranges, project management, buffer operations, backups)
  - `oc-markdown-test` - Markdown parser test tool (parses markdown and outputs callback trace)
  - `oc-html2md` - HTML to Markdown converter (reads HTML from stdin, outputs Markdown)
  - `oc-md2html` - Markdown to HTML converter (converts markdown file to HTML)
  - `oc-diff` - Unified diff tool (compares two files and outputs differences in unified diff format)
  - `oc-vector-index` - Codebase indexing tool for semantic search (indexes files/folders using tree-sitter and vector embeddings)
  - `oc-vector-search` - Command-line semantic code search tool (searches indexed codebase by semantic meaning)
  - `oc-migrate-editors` - Project migration tool (migrates projects from Cursor editor configuration)
  - `oc-test-fetch` - Web fetch test tool (fetches web content from URLs with format conversion support)
- **Technology Stack** - Written in pure Vala, focusing on Vala and GTK4
- **Tool Dependencies** - Some tools will rely on third-party applications
- **Tool Calling** - Supports tool calling functionality
- **Permission System** - Includes a permission system for secure tool access
- **Prompt Manipulation** - Provides prompt manipulation capabilities
- **Generation** - Supports text generation from LLM models
- **Embeddable Widget** - Reusable chat widget (`ChatWidget`) that can be embedded in applications

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
- **[Creating releases](docs/creating-releases.md)** - How tagged releases and CI packaging work

## Releases

Packages are published from [roojs/repos](https://github.com/roojs/repos)
at **https://roojs.github.io/repos/**. All current builds are pre-release quality — expect bugs and missing polish.

### APT (Debian / Ubuntu)

Debian 13 (`trixie`). Ubuntu 25.04 (`plucky`), 25.10 (`questing`), 26.04
(`resolute`). Architectures: `amd64`, `arm64`.

Add the signing key and the sources file, replacing `@suite@` with your
suite from `lsb_release -cs`:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://roojs.github.io/repos/key.gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/roojs.gpg

curl -fsSL https://roojs.github.io/repos/sources \
  | sed "s/@suite@/$(lsb_release -cs)/" \
  | sudo tee /etc/apt/sources.list.d/roojs.sources

sudo apt update
sudo apt install ollmchat
```

(`ollmchat-remote-only` is the same app without libllama / local GGUF.
`libocrpc-dev` and the other `liboc*-dev` / `liboll*-dev` packages are in
the same repository.)

### DNF (Fedora)

Fedora 44.

```bash
sudo curl -fsSL https://roojs.github.io/repos/key.gpg \
  -o /etc/pki/rpm-gpg/RPM-GPG-KEY-roojs
sudo curl -fsSL https://roojs.github.io/repos/repo \
  -o /etc/yum.repos.d/roojs.repo
sudo dnf makecache
sudo dnf install ollmchat
```

More details (supported suites, openSUSE Tumbleweed, package list, and
repository layout) are on the [roojs package repositories](https://roojs.github.io/repos/) page.

AppImage, Windows, and the Android POC APK are on the version GitHub Release (for example `v1.3.0`). The `.deb` / `.rpm` files for that version are on the matching `v1.3.0-packages` Release; prefer the repositories above instead of installing those files by hand.

| Format | Platforms |
|--------|-----------|
| **APT** (`ollmchat`) | Debian / Ubuntu amd64 (also arm64 libs in the repo) |
| **RPM** (`ollmchat`) | Fedora 44 and openSUSE Tumbleweed x86_64 |
| **AppImage** | Linux x86_64 and aarch64 |
| **Windows installer** (`.exe`) | Windows x86_64 |
| **Android APK** | arm64-v8a remote-chat POC (sideload) |

To build from source instead, see **[docs/BUILD.md](docs/BUILD.md)**.

## Project Structure

The project is organized into component directories, each with its own `meson.build` file:

**Markdown Libraries:**
- `libocmarkdown/` - Markdown parsing and rendering (libocmarkdown.so, namespace: `Markdown`)
- `libocmarkdowngtk/` - Embeddable widget for rendering markdown using GtkTextView and GtkSourceView (libocmarkdowngtk.so, namespace: `MarkdownGtk`)

**SQLite Library:**
- `libocsqlite/` - SQLite query builder (libocsqlite.so, namespace: `SQ`)

**RPC Library (`libocrpc.so`):**
- `libocrpc/` - Binary RPC wire protocol for daemon clients (libocrpc.so, namespace: `OLLMrpc`)
  - `Bin/` - `Serializable`, `Stream`, and GObject property encoding on the wire
  - `Transport/` - stdio and TCP connection helpers
  - `Client.vala`, `Daemon.vala`, `Request.vala`, `Response.vala` - request/response dispatch
  - Wire format: **[Binary RPC wire format](docs/bin-rpc-protocol.md)**

**File daemon (`ollmfilesd`):**
- `ollmfilesd/` - Headless file and semantic-index service (namespace: `OLLMfilesd`)
  - SQLite, project scan, file I/O, and vector indexing run out-of-process
  - UI and tools talk to it through `libocrpc` (binary protocol over stdio on Unix, TCP on Windows)

**File Management Library (`libocfiles.so`):**
- `libocfiles/` - File and project management (libocfiles.so, namespace: `OLLMfiles`)
  - Provides file tracking and project management without GTK/git dependencies
  - Used by `libocvector` for file operations
  - `File.vala`, `FileBase.vala`, `FileAlias.vala`, `FileBuffer.vala`, `FileChange.vala` - File classes
  - `Folder.vala`, `FolderFiles.vala` - Folder classes
  - `ProjectFile.vala`, `ProjectFiles.vala`, `ProjectList.vala`, `ProjectManager.vala`, `ProjectMigrate.vala` - Project management
  - `BufferProvider.vala`, `BufferProviderBase.vala`, `DummyFileBuffer.vala` - Buffer providers
  - `GitProvider.vala`, `GitProviderBase.vala` - Git provider classes
  - `Diff/` - Diff and patch utilities (Differ.vala, Patch.vala, PatchApplier.vala)

**Code Editor Library (`liboccoder.so`):**
- `liboccoder/` - Code editor and project management (liboccoder.so, namespace: `OLLMcoder`)
  - `SourceView.vala` - Code editor component with syntax highlighting
  - `GtkSourceFileBuffer.vala` - GTK SourceView buffer implementation
  - `BufferProvider.vala`, `GitProvider.vala` - Buffer and git providers for GTK contexts
  - `SearchableDropdown.vala`, `ProjectDropdown.vala`, `FileDropdown.vala` - Dropdown widgets
  - `Prompt/CodeAssistant.vala` - Code assistant agent with semantic search capabilities
    - The code assistant can perform semantic codebase search using the vector indexing system
    - Includes an indexer tool (`oc-vector-index`) for indexing codebases to enable semantic search
    - Semantic search allows finding code elements by meaning rather than just text matching

**Vector Search Library (`libocvector.so`):**
- `libocvector/` - Semantic codebase search using vector embeddings and FAISS (libocvector.so, namespace: `OLLMvector`)
  - **Status**: Mostly complete - Provides semantic code search capabilities by indexing code elements (classes, methods, functions, etc.) using tree-sitter AST parsing, LLM analysis for descriptions, and FAISS for vector similarity search
  - `Index.vala` - FAISS vector index integration
  - `Database.vala` - Vector database with embeddings storage
  - `VectorMetadata.vala` - Metadata storage (SQL database) mapping vector IDs to code locations
  - `Indexing/` - Code indexing components (namespace: `OLLMvector.Indexing`)
    - `Tree.vala` - Tree-sitter AST parsing and code element extraction
    - `Analysis.vala` - LLM-based code analysis and description generation
    - `VectorBuilder.vala` - Vector generation and FAISS storage
    - `Indexer.vala` - Main indexing orchestrator for files and folders
  - `Search/` - Search components (namespace: `OLLMvector.Search`)
    - `Search.vala` - Vector similarity search execution
    - `SearchResult.vala` - Search result representation
  - `Tool/` - Tool integration (namespace: `OLLMvector.Tool`)
    - `CodebaseSearchTool.vala` - Tool interface for semantic codebase search
    - `RequestCodebaseSearch.vala` - Request handling for codebase search tool
  - Uses `libocfiles` (OLLMfiles namespace) for file tracking and project management
  - Example tool: `oc-vector-index` - Command-line tool for indexing files/folders
  - **Tree-sitter language support**: Parser packages (`libtree-sitter-vala`, `libtree-sitter-python`, …) come from the [roojs APT/DNF repositories](https://roojs.github.io/repos/).

**Vector Search Library v2 (`libocvector2.so`):**
- `libocvector2/` - Slim FAISS index/search for `ollmfilesd` (libocvector2.so, namespace: `OLLMvector2`)
  - No `libocfiles` dependency; used by the daemon instead of in-process `libocvector`

**OLLMchat Base Library (`libollmchat.so`):**
- `libollmchat/` - Main namespace (`OLLMchat`)
  - `Client.vala` - Main client class for Ollama/OpenAI API access
  - `Call/` - API call implementations (Chat, Embed, Generate, etc.)
  - `Response/` - Response handling classes
  - `Tool/` - Tool interface and base classes (namespace: `OLLMchat.Tool`)
  - `ChatPermission/` - Permission system for tool access control (namespace: `OLLMchat.ChatPermission`)
  - `Prompt/` - Prompt generation system for different agent types with agent management (namespace: `OLLMchat.Prompt`)
  - `History/` - Chat history management (namespace: `OLLMchat.History`)
  - `Message.vala`, `ChatContentInterface.vala`, `OllamaBase.vala` - Core message and base classes

**Tools Library (`liboctools.so`):**
- `liboctools/` - Tools for file operations and utilities (namespace: `OLLMtools`)
  - `ReadFile.vala`, `RequestReadFile.vala` - File reading tool with line range support
  - `EditMode.vala`, `RequestEditMode.vala`, `EditModeChange.vala` - File editing tool
  - `RunCommand.vala`, `RequestRunCommand.vala` - Terminal command execution tool
  - `WebFetchTool.vala`, `RequestWebFetch.vala` - Web content fetching tool
  - Tools have access to `ProjectManager` for project context awareness
  - Files in active project automatically skip permission prompts

**OLLMchat GTK Library (`libollmchatgtk.so`):**
- `libollmchatgtk/` - GTK UI components (namespace: `OLLMchatGtk`)
  - `ChatWidget.vala` - Main chat widget
  - `ChatView.vala` - Chat view component
  - `ChatInput.vala` - Chat input component
  - `ChatPermission.vala` - Permission UI component
  - `HistoryBrowser.vala` - History browser component
  - `Message.vala`, `ClipboardManager.vala`, `ClipboardMetadata.vala` - Supporting components

**Main Application (`ollmapp/`):**
- `ollmapp/` - Main application directory (namespace: `OLLMapp`)
  - `Application.vala` - Main application class (`OLLMapp.OllmchatApplication`)
  - `Window.vala` - Main window class (`OLLMapp.OllmchatWindow`)
  - `SettingsDialog/` - Settings dialog components (namespace: `OLLMapp.SettingsDialog`)
    - `MainDialog.vala` - Main settings dialog
    - `ConnectionsPage.vala` - Connection management page
    - `ModelsPage.vala` - Model management page
    - `ToolsPage.vala` - Tool configuration page
    - `Rows/` - Settings row widgets (namespace: `OLLMapp.SettingsDialog.Rows`)
  - Note: The application uses `OLLMapp` namespace to distinguish it from the `libollmchat` library which uses `OLLMchat` namespace

**Other Directories:**
- `examples/` - Example programs and test code (each with its own meson.build)
- `docs/` - Generated documentation (Valadoc) and implementation plans
- `resources/` - Resource files including prompt templates
- `vapi/` - VAPI files for external dependencies

## License

This project is licensed under the GNU Lesser General Public License version 3.0 (LGPL-3.0). See the [LICENSE](LICENSE) file for details.

**Exceptions** (third-party / derived files, e.g. Pi MIT prompt text): see [`licenses/README.md`](licenses/README.md).

