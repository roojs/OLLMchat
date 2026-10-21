# Project structure

Directory layout for the libraries, the file server, and the main application. The [README](../README.md) is the short version: core libraries, tool libraries (`libollamaweb`, `liboctools`, `libocmcp`), and how the file server and the desktop or mobile client split.

Each component directory has its own `meson.build`.

**Markdown libraries:**

- `libocmarkdown/` - Markdown parsing and rendering (libocmarkdown.so, namespace: `Markdown`)
- `libocmarkdowngtk/` - Embeddable widget for rendering markdown using GtkTextView and GtkSourceView (libocmarkdowngtk.so, namespace: `MarkdownGtk`)

**SQLite library:**

- `libocsqlite/` - SQLite query builder (libocsqlite.so, namespace: `SQ`)

**RPC library (`libocrpc.so`):**

- `libocrpc/` - Binary RPC wire protocol for daemon clients (libocrpc.so, namespace: `OLLMrpc`)
  - `Bin/` - `Serializable`, `Stream`, and GObject property encoding on the wire
  - `Transport/` - stdio and TCP connection helpers
  - `Client.vala`, `Daemon.vala`, `Request.vala`, `Response.vala` - request/response dispatch
  - Wire format: **[Binary RPC wire format](bin-rpc-protocol.md)**

**File server (`ollmfilesd`):**

- `ollmfilesd/` - Headless file server (namespace: `OLLMfilesd`)
  - File operations, file monitoring, application execution, and semantic indexing run here
  - Can run on the same machine as the client or on another machine
  - UI and tools talk to it through `libocrpc` (binary protocol over a socket; stdio is for tests and scripts)
  - Tree-sitter language packages (`libtree-sitter-vala`, `libtree-sitter-python`, …) come from the [roojs APT/DNF repositories](https://roojs.github.io/repos/)

**File management library (`libocfiles.so`):**

- `libocfiles/` - File and project management (libocfiles.so, namespace: `OLLMfiles`)
  - Client-side file and project types. File I/O, monitoring, and application execution run in `ollmfilesd`
  - `File.vala`, `FileBase.vala`, `FileAlias.vala`, `FileBuffer.vala`, `FileChange.vala` - File classes
  - `Folder.vala`, `FolderFiles.vala` - Folder classes
  - `ProjectFile.vala`, `ProjectFiles.vala`, `ProjectList.vala`, `ProjectManager.vala`, `ProjectMigrate.vala` - Project management
  - `BufferProvider.vala`, `BufferProviderBase.vala`, `DummyFileBuffer.vala` - Buffer providers
  - `GitProvider.vala`, `GitProviderBase.vala` - Git provider classes
  - `Diff/` - Diff and patch utilities (Differ.vala, Patch.vala, PatchApplier.vala)

**Code editor library (`liboccoder.so`):**

- `liboccoder/` - Code editor and project management (liboccoder.so, namespace: `OLLMcoder`)
  - `SourceView.vala` - Code editor component with syntax highlighting
  - `GtkSourceFileBuffer.vala` - GTK SourceView buffer implementation
  - `BufferProvider.vala`, `GitProvider.vala` - Buffer and git providers for GTK contexts
  - `SearchableDropdown.vala`, `ProjectDropdown.vala`, `FileDropdown.vala` - Dropdown widgets
  - Semantic search runs through the file server's vector index (`libocvector2`)
  - `oc-vector-index` and `oc-vector-search` are command-line clients of that server

**Vector search (`libocvector2.so`):**

- `libocvector2/` - FAISS index and search for the file server (libocvector2.so, namespace: `OLLMvector2`)
  - `Index.vala` - FAISS vector index
  - `Database.vala` - Embeddings storage
  - `Search.vala` - Similarity search
  - `VectorBuilder.vala` - Vector generation
  - `VectorBase.vala`, `VectorToolConfig.vala` - Shared types and tool configuration
  - `SQT/VectorMetadata.vala` - Metadata mapping vector IDs to code locations
  - Used by `ollmfilesd`. No `libocfiles` dependency

**OLLMchat base library (`libollmchat.so`):**

- `libollmchat/` - Main namespace (`OLLMchat`)
  - `Client.vala` - Main client class for Ollama/OpenAI API access
  - `Call/` - API call implementations (Chat, Embed, Generate, etc.)
  - `Response/` - Response handling classes
  - `Tool/` - Tool interface and base classes (namespace: `OLLMchat.Tool`)
  - `ChatPermission/` - Permission system for tool access control (namespace: `OLLMchat.ChatPermission`)
  - `Prompt/` - Prompt generation system for different agent types with agent management (namespace: `OLLMchat.Prompt`)
  - `History/` - Chat history management (namespace: `OLLMchat.History`)
  - `Message.vala`, `ChatContentInterface.vala`, `MessageQueue.vala` - Core message types

**Ollama.com library (`libollamaweb.so`):**

- `libollamaweb/` - Live search and model metadata from ollama.com (namespace: `OllamaWeb`)

**Tools library (`liboctools.so`):**

- `liboctools/` - Agent tools (namespace: `OLLMtools`)
  - `ReadFile/` - File reading, including line ranges
  - `EditMode/` - File editing
  - `WriteFile/` - File writing
  - `RunCommand/` - Running commands
  - `WebFetch/` - Fetching web content
  - `CodebaseSearch/` - Semantic search through the file server
  - `SessionFetch/`, `GoogleSearch/`, `HuggingFace/`, `Child/` - Further tools
  - Files in the active project automatically skip permission prompts

**MCP library (`libocmcp.so`):**

- `libocmcp/` - MCP (Model Context Protocol) client (namespace: `OLLMmcp`)
  - Load servers from `~/.config/ollmchat/mcp.json`, discover tools, and expose them as `mcp:{server_id}:{tool_name}` agent tools
  - stdio subprocess or HTTP JSON-RPC

**OLLMchat GTK library (`libollmchatgtk.so`):**

- `libollmchatgtk/` - GTK UI components (namespace: `OLLMchatGtk`)
  - `ChatWidget.vala` - Main chat widget
  - `ChatView.vala` - Chat view component
  - `ChatInput.vala` - Chat input component
  - `ChatPermission.vala` - Permission UI component
  - `HistoryBrowser.vala` - History browser component
  - `Message.vala`, `ClipboardManager.vala`, `ClipboardMetadata.vala` - Supporting components

**Main application (`ollmapp/`):**

- `ollmapp/` - Main application directory (namespace: `OLLMapp`)
  - `Application.vala` - Main application class (`OLLMapp.OllmchatApplication`)
  - `Window.vala` - Main window class (`OLLMapp.OllmchatWindow`)
  - `SettingsDialog/` - Settings dialog components (namespace: `OLLMapp.SettingsDialog`)
    - `MainDialog.vala` - Main settings dialog
    - `ConnectionsPage.vala` - Connection management page
    - `ModelsPage.vala` - Model management page
    - `ToolsPage.vala` - Tool configuration page
    - `Rows/` - Settings row widgets (namespace: `OLLMapp.SettingsDialog.Rows`)
  - The application uses the `OLLMapp` namespace so it stays distinct from the `libollmchat` library (`OLLMchat`)

**Other directories:**

- `examples/` - Example programs and test code (each with its own meson.build)
- `docs/` - Generated documentation (Valadoc) and implementation plans
- `resources/` - Resource files including prompt templates
- `vapi/` - VAPI files for external dependencies
